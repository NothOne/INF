/*
* Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

// sqflite channel 移到自管理 worker 线程，修复 issue #45/#65（THREAD_BLOCK_6S appfreeze）。
// 移植自 dev 分支 commit 6c42dd2。
//
// 核心改造：不再用 MethodChannel.setMethodCallHandler（其 onMessage 在平台主线程
// 同步 StandardMethodCodec.decodeMethodCall，单次大 batch 的巨型 message 解码 >6s
// → appfreeze → 闪退）。改用 BinaryMessenger.setMessageHandler 拿【未 decode 的原始
// ArrayBuffer】，主线程只分配 seq + 存 pending[seq]=reply + postMessage 抛 worker，
// decode + 执行全在 SqfliteWorker.ets（worker 线程）。主线程 onmessage 只设一次
// 永不重写，按 seq 精确路由 reply，根治 engine 重写 onmessage 的串号 bug。
// 等价 Android makeBackgroundTaskQueue + DatabaseWorkerPool(THREAD_COUNT=1)。

import common from '@ohos.app.ability.common';
import { ErrorEvent, MessageEvents, worker } from '@kit.ArkTS';
import {
  FlutterPlugin,
  FlutterPluginBinding
} from '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import {
  BinaryMessageHandler,
  BinaryMessenger,
  BinaryReply
} from '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import { Constant } from './Constant';

export default class SqflitePlugin implements FlutterPlugin {
  private context: common.Context | null = null;
  private messenger: BinaryMessenger | null = null;
  private sqfliteWorker: worker.ThreadWorker | null = null;
  // seq -> reply：每条 message 的原始 BinaryReply，worker 回传时按 seq 精确匹配。
  private pending: Map<number, BinaryReply> = new Map<number, BinaryReply>();
  private seq: number = 0;

  getUniqueClassName(): string {
    return "SqflitePlugin";
  }

  onAttachedToEngine(binding: FlutterPluginBinding): void {
    this.context = binding.getApplicationContext();
    this.messenger = binding.getBinaryMessenger();

    // 防御重复 attach（热重启 / 多引擎同实例）：先终止旧 worker，
    // 避免泄漏 worker 线程与 RdbStore 句柄。
    if (this.sqfliteWorker != null) {
      const previousWorker: worker.ThreadWorker = this.sqfliteWorker;
      this.sqfliteWorker = null;
      try {
        previousWorker.terminate();
      } catch (e) {
        Log.e('SqflitePlugin', 'terminate previous worker failed: ' + e);
      }
      // 与 onDetachedFromEngine 保持一致：旧 worker 已终止，flush 旧 pending
      // 避免异常重连场景下 Dart 侧请求永久悬挂。
      this.flushPending();
    }

    try {
      this.sqfliteWorker = new worker.ThreadWorker('./SqfliteWorker.ets', { name: 'SqfliteWorker' });
    } catch (e) {
      // worker 加载失败（scriptURL 解析不到 / ets 编译产物缺失）会让整条 channel 不可用。
      // 记录后继续注册 rawHandler（其对 null worker 兜底回 null reply），避免在主线程抛异常。
      Log.e('SqflitePlugin', 'create SqfliteWorker failed: ' + e);
      this.sqfliteWorker = null;
    }

    if (this.sqfliteWorker != null) {
      // 只设一次 onmessage：按 seq 精确路由 reply，永不重写——
      // 根治 engine 重写 onmessage 的串号 bug。
      this.sqfliteWorker.onmessage = (e: MessageEvents): void => {
        const data: SqfliteReply = e.data as SqfliteReply;
        const reply: BinaryReply | undefined = this.pending.get(data.seq);
        if (reply != null) {
          // 引擎关闭窗口期 reply 可能已失效（flushPending 同类调用已有防护），
          // 此处对齐防护标准，避免主线程事件回调未捕获异常
          try {
            reply.reply(data.result);
          } catch (err) {
            Log.e('SqflitePlugin', 'reply failed for seq=' + data.seq + ': ' + err);
          }
          // 无论成败都删除，防止条目残留
          this.pending.delete(data.seq);
        }
      };
      this.sqfliteWorker.onerror = (e: ErrorEvent): void => {
        Log.e('SqflitePlugin', 'SqfliteWorker error: ' + e.message);
      };
      // One-time init: context is structured-cloned only in this message and
      // stored in a worker module variable; port messages are FIFO, so init
      // always arrives before any task message.
      try {
        const initMessage: SqfliteInitMessage = { init: true, context: this.context };
        this.sqfliteWorker.postMessage(initMessage);
      } catch (e) {
        // Worker died right after creation: context-dependent methods fall
        // back to the worker-side uninitialized-context error.
        Log.e('SqflitePlugin', 'post init (context) to worker failed: ' + e);
      }
    }

    // raw handler：默认（不传 taskQueue）在平台主线程执行，
    // 但拿到的是【未 decode 的原始 ArrayBuffer】。
    // decode + 执行全部丢给 worker（见 SqfliteWorker.ets），
    // 主线程只做分配 seq + 存 reply + 抛 worker。
    const rawHandler: BinaryMessageHandler = {
      onMessage: (message: ArrayBuffer, reply: BinaryReply): void => {
        // worker 不可用（构造失败或已 detach）：
        // 按 engine 契约回 null reply，不在主线程抛异常。
        if (this.sqfliteWorker == null) {
          Log.e('SqflitePlugin', 'SqfliteWorker unavailable, replying null');
          reply.reply(null);
          return;
        }
        const id: number = ++(this.seq);
        this.pending.set(id, reply);
        // context is NOT shipped with task messages: it is delivered once via
        // the init message at attach, avoiding one common.Context structured
        // clone per message (a major source of shared-heap churn).
        try {
          // 拷贝后转发：engine 在 onMessage 返回后可能复用该 message 的 ArrayBuffer。
          const messageCopy = message.slice(0);
          this.sqfliteWorker!.postMessageWithSharedSendable(
            { seq: id, message: messageCopy }, [messageCopy]);
        } catch (e) {
          // worker 在 null 检查后被终止 / 序列化失败：回滚 pending 并回 null，保证 Dart 不挂。
          Log.e('SqflitePlugin', 'postMessage to worker failed, replying null: ' + e);
          this.pending.delete(id);
          reply.reply(null);
        }
      }
    };
    this.messenger.setMessageHandler(Constant.PLUGIN_KEY, rawHandler);
  }

  onDetachedFromEngine(binding: FlutterPluginBinding): void {
    if (this.messenger != null) {
      this.messenger.setMessageHandler(Constant.PLUGIN_KEY, null);
      // 显式断开 messenger → rawHandler 闭包 → this 的引用链
      this.messenger = null;
    }
    // engine 契约要求每条 message 都必须有回执，否则 Dart 侧 reply handler 泄漏。
    // detach 时对尚在 pending（worker 尚未回执）的请求统一回 null。
    this.flushPending();
    // 请求 worker 清理其持有的全部 RdbStore/游标/静态映射后自行退出
    this.disposeWorker();
    // 显式断开插件实例对 context 的引用（worker 的 onmessage/rawHandler 闭包
    // 随 worker 对象被回收而释放，孤岛引用环可被 GC 回收）
    this.context = null;
  }

  /**
   * 对尚未回执的 pending 请求统一回 null 并清空（engine 契约：每条 message 必须有回执）
   */
  private flushPending(): void {
    this.pending.forEach((reply: BinaryReply) => {
      try {
        reply.reply(null);
      } catch (e) {
        // ignore：引擎已关闭时 reply 可能已失效。
      }
    });
    this.pending.clear();
  }

  /**
   * 通知 worker 清理其模块内全部数据库/游标/静态状态后自行 close。
   * worker 静态状态（dbMap/cursorMap 等）只在 worker 线程可见，主线程无法直接清理，
   * 因此经 dispose 消息让 worker 自行释放；主线程以超时 terminate 兜底，
   * 防止 RdbStore.close() 挂起导致线程泄漏。
   */
  private disposeWorker(): void {
    const workerToDispose: worker.ThreadWorker | null = this.sqfliteWorker;
    if (workerToDispose == null) {
      return;
    }
    let disposeSent: boolean = false;
    try {
      const disposeTask: SqfliteTaskMessage = {
        seq: Constant.WORKER_DISPOSE_SEQ,
        message: new ArrayBuffer(0),
        dispose: true
      };
      workerToDispose.postMessage(disposeTask);
      disposeSent = true;
    } catch (e) {
      Log.e('SqflitePlugin', 'postMessage dispose to worker failed: ' + e);
    }
    if (!disposeSent) {
      this.terminateWorker();
      return;
    }
    setTimeout(() => {
      // 只终止捕获的旧 worker 引用，绝不误杀重连（热重启）后的新 worker；
      // worker 已自行 close 时 terminate 抛错/幂等均无碍。
      try {
        workerToDispose.terminate();
      } catch (e) {
        // ignore：worker 已退出时 terminate 可能抛错。
      }
      if (this.sqfliteWorker === workerToDispose) {
        this.sqfliteWorker = null;
      }
    }, Constant.WORKER_DISPOSE_TIMEOUT_MS);
  }

  /**
   * 终止当前 worker 并断开字段引用（terminate 增加容错，确保释放链不因异常中断）
   */
  private terminateWorker(): void {
    if (this.sqfliteWorker != null) {
      try {
        this.sqfliteWorker.terminate();
      } catch (e) {
        Log.e('SqflitePlugin', 'terminate worker failed: ' + e);
      }
      this.sqfliteWorker = null;
    }
  }
}

// worker 回传结构：seq 标识对应哪条原始 message，
// result 是编码后的 envelope（或 null=notImplemented）。
interface SqfliteReply {
  seq: number;
  result: ArrayBuffer | null;
}

// One-time init message sent to the worker: context appears only here (one per
// worker); the worker stores it in the module-level workerContext, so task
// messages carry no context.
interface SqfliteInitMessage {
  init: boolean;
  context: common.Context | null;
}

// 发送给 worker 的任务消息（与 SqfliteWorker.ets 的 SqfliteTask 对应；
// dispose=true 时 worker 清理全部资源后自行退出）
interface SqfliteTaskMessage {
  seq: number;
  message: ArrayBuffer;
  dispose?: boolean;
}
