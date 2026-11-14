/*
 * Copyright (C) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
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

import { describe, beforeAll, it, expect } from '@ohos/hypium';
import FlutterEngine from '@ohos/flutter_ohos/src/main/ets/embedding/engine/FlutterEngine';
import { FlutterAssets, FlutterPluginBinding } from
  '@ohos/flutter_ohos/src/main/ets/embedding/engine/plugins/FlutterPlugin';
import { BinaryMessageHandler, BinaryMessenger, BinaryReply, TaskQueue, TaskQueueOptions } from
  '@ohos/flutter_ohos/src/main/ets/plugin/common/BinaryMessenger';
import { TextureRegistry } from '@ohos/flutter_ohos/src/main/ets/view/TextureRegistry';
import { Constant } from '../../../main/ets/io/flutter/plugins/sqflite/Constant';
import SqflitePlugin from '../../../main/ets/io/flutter/plugins/sqflite/SqflitePlugin';
import { initTestContext, getTestContext } from './TestUtils';

// Fake BinaryMessenger capturing raw handler registrations per channel.
class FakeMessenger implements BinaryMessenger {
  public registeredChannels: String[] = [];
  public registeredHandlers: (BinaryMessageHandler | null)[] = [];

  makeBackgroundTaskQueue(options?: TaskQueueOptions): TaskQueue {
    return {} as TaskQueue;
  }

  send(channel: String, message: ArrayBuffer | null, callback?: BinaryReply | null): void {
    // Sending is not exercised by these tests
  }

  setMessageHandler(channel: String, handler: BinaryMessageHandler | null,
    taskQueue?: TaskQueue, ...args: Object[]): void {
    this.registeredChannels.push(channel);
    this.registeredHandlers.push(handler);
  }
}

// Fake BinaryReply capturing whatever the plugin answers.
class CapturedReply implements BinaryReply {
  public replied: boolean = false;
  public payload: ArrayBuffer | null = null;

  reply(reply: ArrayBuffer | null): void {
    this.replied = true;
    this.payload = reply;
  }
}

// Fake BinaryReply whose reply() throws, simulating an already-closed
// engine-side reply channel.
class ThrowingReply implements BinaryReply {
  public called: boolean = false;

  reply(reply: ArrayBuffer | null): void {
    this.called = true;
    throw new Error('reply channel already closed');
  }
}

// The plugin only reads the context and the messenger from the binding; the
// engine-typed slots are filled with null casts for the test construction.
function makeBinding(messenger: FakeMessenger): FlutterPluginBinding {
  const unusedEngine: FlutterEngine = null as ESObject as FlutterEngine;
  const unusedAssets: FlutterAssets = null as ESObject as FlutterAssets;
  const unusedTextures: TextureRegistry = null as ESObject as TextureRegistry;
  return new FlutterPluginBinding(getTestContext(), unusedEngine, messenger,
    unusedAssets, unusedTextures);
}

const WORKER_ROUNDTRIP_WAIT_MS: number = 500;
const WORKER_ROUNDTRIP_DEADLINE_MS: number = 2000;
const WAIT_UNTIL_POLL_MS: number = 100;

function wait(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(() => {
      resolve();
    }, ms);
  });
}

async function waitUntil(condition: () => boolean, deadlineMs: number): Promise<boolean> {
  const deadline: number = Date.now() + deadlineMs;
  while (!condition()) {
    if (Date.now() >= deadline) {
      return false;
    }
    await wait(WAIT_UNTIL_POLL_MS);
  }
  return true;
}

export default function SqflitePluginTest(): void {
  describe('SqflitePluginTest', () => {
    // RDB rejects ApplicationContext with 401 'Illegal context'; capture the
    // UIAbility context of the injected test ability before any helper runs.
    beforeAll(async () => {
      await initTestContext();
    });

    // Interface: getUniqueClassName
    it('getUniqueClassName_returns_plugin_name', 0, () => {
      const plugin: SqflitePlugin = new SqflitePlugin();
      expect(plugin.getUniqueClassName()).assertEqual('SqflitePlugin');
    });

    // Interface: onAttachedToEngine registers the raw binary handler on the channel
    it('onAttachedToEngine_registers_raw_handler', 0, () => {
      const plugin: SqflitePlugin = new SqflitePlugin();
      const messenger: FakeMessenger = new FakeMessenger();
      plugin.onAttachedToEngine(makeBinding(messenger));
      expect(messenger.registeredChannels.length).assertEqual(1);
      expect(`${messenger.registeredChannels[0]}`).assertEqual(Constant.PLUGIN_KEY);
      // Boolean compare: hypium expect() is unreliable on interface objects
      expect(messenger.registeredHandlers[0] !== null).assertTrue();
      plugin.onDetachedFromEngine(makeBinding(messenger));
    });

    // Interface: the raw handler honors the engine contract that every message
    // gets a reply — immediately with null when the worker thread is not
    // available in the test process, or asynchronously with an envelope after a
    // worker round-trip when it is
    it('rawHandler_always_replies', 0, async () => {
      const plugin: SqflitePlugin = new SqflitePlugin();
      const messenger: FakeMessenger = new FakeMessenger();
      plugin.onAttachedToEngine(makeBinding(messenger));
      const handler: BinaryMessageHandler | null = messenger.registeredHandlers[0];
      expect(handler !== null).assertTrue();
      const rawHandler: BinaryMessageHandler = handler as BinaryMessageHandler;
      const reply: CapturedReply = new CapturedReply();
      rawHandler.onMessage(new ArrayBuffer(0), reply);
      // Worker round-trips are asynchronous; wait long enough for either path
      expect(await waitUntil(() => reply.replied, WORKER_ROUNDTRIP_DEADLINE_MS)).assertTrue();
      plugin.onDetachedFromEngine(makeBinding(messenger));
    });

    // Interface: onDetachedFromEngine clears the channel handler
    it('onDetachedFromEngine_clears_handler', 0, () => {
      const plugin: SqflitePlugin = new SqflitePlugin();
      const messenger: FakeMessenger = new FakeMessenger();
      plugin.onAttachedToEngine(makeBinding(messenger));
      plugin.onDetachedFromEngine(makeBinding(messenger));
      expect(messenger.registeredChannels.length).assertEqual(2);
      expect(`${messenger.registeredChannels[1]}`).assertEqual(Constant.PLUGIN_KEY);
      expect(messenger.registeredHandlers[1] === null).assertTrue();
    });

    // A message posted right before a re-attach must be flushed with a null
    // reply: the previous worker is terminated and its pending entries are
    // answered (engine contract: every message gets a reply). A throwing
    // reply during the flush must be tolerated without breaking the flush of
    // the remaining entries.
    it('doubleAttach_flushes_pending_and_reregisters_handler', 0, async () => {
      const plugin: SqflitePlugin = new SqflitePlugin();
      const first: FakeMessenger = new FakeMessenger();
      plugin.onAttachedToEngine(makeBinding(first));
      const handler: BinaryMessageHandler = first.registeredHandlers[0] as BinaryMessageHandler;
      // First pending entry with a reply channel that throws when flushed
      handler.onMessage(new ArrayBuffer(0), new ThrowingReply());
      const reply: CapturedReply = new CapturedReply();
      // Second pending entry with a healthy reply channel
      handler.onMessage(new ArrayBuffer(0), reply);
      // Synchronous re-attach right after onMessage: the worker cannot have
      // answered yet, so the pending entries are flushed with a null reply
      const second: FakeMessenger = new FakeMessenger();
      plugin.onAttachedToEngine(makeBinding(second));
      expect(reply.replied).assertTrue();
      expect(reply.payload).assertNull();
      expect(second.registeredChannels.length).assertEqual(1);
      expect(`${second.registeredChannels[0]}`).assertEqual(Constant.PLUGIN_KEY);
      plugin.onDetachedFromEngine(makeBinding(second));
    });

    // A throwing reply inside the worker onmessage handler must be caught and
    // the pending entry dropped; later messages are still served
    it('workerReplyThrow_does_not_break_later_messages', 0, async () => {
      const plugin: SqflitePlugin = new SqflitePlugin();
      const messenger: FakeMessenger = new FakeMessenger();
      plugin.onAttachedToEngine(makeBinding(messenger));
      const rawHandler: BinaryMessageHandler = messenger.registeredHandlers[0] as BinaryMessageHandler;
      // First message: the reply channel throws when the worker answers it
      const throwing: ThrowingReply = new ThrowingReply();
      rawHandler.onMessage(new ArrayBuffer(0), throwing);
      expect(await waitUntil(() => throwing.called, WORKER_ROUNDTRIP_DEADLINE_MS)).assertTrue();
      const later: CapturedReply = new CapturedReply();
      rawHandler.onMessage(new ArrayBuffer(0), later);
      expect(await waitUntil(() => later.replied, WORKER_ROUNDTRIP_DEADLINE_MS)).assertTrue();
      plugin.onDetachedFromEngine(makeBinding(messenger));
    });

    // After detach the dispose timeout nulls the worker reference; a late
    // message must get an immediate null reply instead of posting into the
    // dead worker (worker-unavailable fallback path)
    it('rawHandler_after_dispose_timeout_replies_null', 0, async () => {
      const originalTimeout: number = Constant.WORKER_DISPOSE_TIMEOUT_MS;
      Constant.WORKER_DISPOSE_TIMEOUT_MS = WORKER_ROUNDTRIP_WAIT_MS;
      try {
        const plugin: SqflitePlugin = new SqflitePlugin();
        const messenger: FakeMessenger = new FakeMessenger();
        plugin.onAttachedToEngine(makeBinding(messenger));
        const rawHandler: BinaryMessageHandler = messenger.registeredHandlers[0] as BinaryMessageHandler;
        plugin.onDetachedFromEngine(makeBinding(messenger));
        await wait(WORKER_ROUNDTRIP_WAIT_MS * 2);
        const late: CapturedReply = new CapturedReply();
        rawHandler.onMessage(new ArrayBuffer(0), late);
        expect(late.replied).assertTrue();
        expect(late.payload).assertNull();
        plugin.onDetachedFromEngine(makeBinding(new FakeMessenger()));
      } finally {
        Constant.WORKER_DISPOSE_TIMEOUT_MS = originalTimeout;
      }
    });
  });
}
