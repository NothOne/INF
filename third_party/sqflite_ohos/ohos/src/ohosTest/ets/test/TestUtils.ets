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

import abilityDelegatorRegistry from '@ohos.app.ability.abilityDelegatorRegistry';
import UIAbility from '@ohos.app.ability.UIAbility';
import common from '@ohos.app.ability.common';
import fs from '@ohos.file.fs';
import MethodCall from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodCall';
import { MethodResult } from '@ohos/flutter_ohos/src/main/ets/plugin/common/MethodChannel';
import { Any } from '@ohos/flutter_ohos';
import { Constant } from '../../../main/ets/io/flutter/plugins/sqflite/Constant';
import { DatabaseHelper } from '../../../main/ets/io/flutter/plugins/sqflite/DatabaseHelper';

/**
 * MethodResult implementation that captures replies so tests can assert on them,
 * mirroring how SqfliteWorker routes dispatch() replies.
 */
export class TestResult implements MethodResult {
  public successCalled: boolean = false;
  public successValue: Any | null = null;
  public errorCalled: boolean = false;
  public errorCode: string | null = null;
  public errorMessage: string | null = null;
  public errorDetails: Any | null = null;
  public notImplementedCalled: boolean = false;

  success(result: Any): void {
    this.successCalled = true;
    this.successValue = result;
  }

  error(errorCode: string, errorMessage: string, errorDetails: Any): void {
    this.errorCalled = true;
    this.errorCode = errorCode;
    this.errorMessage = errorMessage;
    this.errorDetails = errorDetails;
  }

  notImplemented(): void {
    this.notImplementedCalled = true;
  }
}

/**
 * Build a MethodCall the same way the worker decodes one: a Map-based argument bag.
 */
export function makeCall(method: string, args: Map<string, Object | null> | null): MethodCall {
  const safeArgs: Map<string, Object | null> = args ?? new Map<string, Object | null>();
  return new MethodCall(method, safeArgs);
}

/**
 * Context holder: RDB getRdbStore rejects ApplicationContext with 401
 * 'Illegal context', so tests must run against the real UIAbility context.
 */
let currentContext: common.Context | null = null;

// Must stay below Hypium's default 5s timeout: beforeAll callbacks are
// wrapped with the same per-case timeout, so a longer deadline would be
// cut off with 'execute timeout 5000ms' instead of our explicit error.
const CONTEXT_INIT_DEADLINE_MS: number = 4000;
const CONTEXT_INIT_POLL_MS: number = 200;

function wait(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(() => {
      resolve();
    }, ms);
  });
}

/**
 * Capture the UIAbility context of the hvigor-injected test ability once.
 * getAppContext() is not usable here: it returns an ApplicationContext that
 * the relational store rejects with 401 'Illegal context'. Right after
 * install the delegator may briefly fail to report the top ability, so poll
 * until a deadline instead of failing the whole suite on the first miss.
 */
export async function initTestContext(): Promise<void> {
  if (currentContext !== null) {
    return;
  }
  const delegator = abilityDelegatorRegistry.getAbilityDelegator();
  const deadline: number = Date.now() + CONTEXT_INIT_DEADLINE_MS;
  while (Date.now() < deadline) {
    try {
      const ability: UIAbility = await delegator.getCurrentTopAbility();
      if (ability !== null && ability !== undefined &&
        ability.context !== null && ability.context !== undefined) {
        currentContext = ability.context;
        return;
      }
    } catch (e) {
      // Ability delegator not ready yet: retry until the deadline
    }
    await wait(CONTEXT_INIT_POLL_MS);
  }
  throw new Error('Failed to obtain the test ability context from the ability delegator');
}

/**
 * Context used for every DatabaseHelper call in tests.
 */
export function getTestContext(): common.Context {
  if (currentContext !== null) {
    return currentContext;
  }
  throw new Error('Test context is not initialized; await initTestContext() first');
}

/**
 * Full database path following the plugin getDatabasesPath contract:
 * app-level <databaseDir>/rdb/<name>. The plugin parses only the file name
 * (and customDir) out of this path when opening through RDB.
 */
export function dbPathFor(name: string): string {
  return `${getTestContext().getApplicationContext().databaseDir}/rdb/${name}`;
}

/**
 * Module-scoped physical location where RDB actually places the file opened
 * from the test ability context. Needed for direct fs surgery and for the
 * raw path embedded in ATTACH statements.
 */
export function moduleDbPathFor(name: string): string {
  return `${getTestContext().databaseDir}/rdb/${name}`;
}

/**
 * Create an empty file at the app-level plugin path so checkDatabaseExisted
 * reports true (mirrors a database persisted from a previous session).
 */
export function touchDbFile(name: string): void {
  const file: string = dbPathFor(name);
  const dir: string = file.substring(0, file.lastIndexOf('/'));
  try {
    fs.mkdirSync(dir, true);
  } catch (e) {
    // Directory already exists
  }
  const fd = fs.openSync(file, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
  fs.closeSync(fd);
}

/**
 * Remove a database and its companion files in both path locations so tests
 * start from a clean state across runs.
 */
export function removeDbFiles(name: string): void {
  const suffixes: string[] = ['', '-wal', '-shm', '-dwr', '-journal', '-compare'];
  for (const suffix of suffixes) {
    for (const dir of [dbPathFor, moduleDbPathFor]) {
      const file = dir(name + suffix);
      try {
        fs.accessSync(file);
        fs.unlinkSync(file);
      } catch (e) {
        // Not present: nothing to clean
      }
    }
  }
}

/**
 * Outcome of a positive openDatabase call: captured reply plus the assigned dbId.
 */
export class OpenDbOutcome {
  public result: TestResult = new TestResult();
  public dbId: number = -1;
}

/**
 * Open a database through the public interface and capture id/reply.
 */
export async function openTestDatabase(dbPath: string, logLevel?: number): Promise<OpenDbOutcome> {
  const args: Map<string, Object | null> = new Map<string, Object | null>();
  args.set(Constant.PARAM_PATH, dbPath);
  if (logLevel !== undefined) {
    args.set(Constant.PARAM_LOG_LEVEL, logLevel);
  }
  const call: MethodCall = makeCall(Constant.METHOD_OPEN_DATABASE, args);
  const outcome: OpenDbOutcome = new OpenDbOutcome();
  await DatabaseHelper.openDatabase(getTestContext(), call, outcome.result);
  const successMap: Record<string, Object> = outcome.result.successValue as Record<string, Object>;
  if (successMap !== null) {
    outcome.dbId = successMap['id'] as number;
  }
  return outcome;
}

/**
 * Close a database by id, ignoring the reply (cleanup helper).
 */
export async function closeTestDatabase(dbId: number): Promise<void> {
  const args: Map<string, Object> = new Map<string, Object>();
  args.set(Constant.PARAM_ID, dbId);
  const call: MethodCall = makeCall(Constant.METHOD_CLOSE_DATABASE, args);
  await DatabaseHelper.closeDatabase(call, new TestResult());
}
