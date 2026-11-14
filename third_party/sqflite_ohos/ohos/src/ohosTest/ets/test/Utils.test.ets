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

import { describe, it, expect } from '@ohos/hypium';
import { Tools } from '../../../main/ets/io/flutter/plugins/sqflite/Tools';
import { SqlCommand } from '../../../main/ets/io/flutter/plugins/sqflite/SqlCommand';
import { Constant } from '../../../main/ets/io/flutter/plugins/sqflite/Constant';
import { isVacuumStatement } from '../../../main/ets/io/flutter/plugins/sqflite/SqlHandler';
import { MethodCallOperation } from
  '../../../main/ets/io/flutter/plugins/sqflite/operation/MethodCallOperation';
import { BatchOperation, OperationError } from
  '../../../main/ets/io/flutter/plugins/sqflite/operation/BatchOperation';
import { TestResult, makeCall } from './TestUtils';

export default function UtilsTest(): void {
  describe('UtilsTest', () => {
    // Tools.stringEndWith: suffix match and edge cases
    it('stringEndWith_matches_and_rejects', 0, () => {
      expect(Tools.stringEndWith('test.db', '.db')).assertTrue();
      expect(Tools.stringEndWith('test.db', '.sqlite')).assertFalse();
      // Suffix longer than the origin can never match
      expect(Tools.stringEndWith('a', 'abc')).assertFalse();
      // Empty suffix trivially matches
      expect(Tools.stringEndWith('test', '')).assertTrue();
      // Comparison is case-sensitive
      expect(Tools.stringEndWith('test.DB', '.db')).assertFalse();
    });

    // Tools.startsWithIgnoreCase: case-insensitive prefix match
    it('startsWithIgnoreCase_matches_case_insensitive', 0, () => {
      expect(Tools.startsWithIgnoreCase('ATTACH DATABASE x AS y', 'attach')).assertTrue();
      expect(Tools.startsWithIgnoreCase('detach database x', 'DETACH')).assertTrue();
      expect(Tools.startsWithIgnoreCase('  vacuum', 'vacuum')).assertFalse();
      expect(Tools.startsWithIgnoreCase('rollback', 'attach')).assertFalse();
    });

    // SqlCommand: undefined arguments normalize to an empty array
    it('sqlCommand_normalizes_undefined_arguments', 0, () => {
      const command: SqlCommand = new SqlCommand('SELECT 1', undefined);
      expect(command.getSql()).assertEqual('SELECT 1');
      expect(command.getRawSqlArguments().length).assertEqual(0);
    });

    // SqlCommand keeps the given sql and argument values
    it('sqlCommand_keeps_sql_and_arguments', 0, () => {
      const command: SqlCommand = new SqlCommand('INSERT INTO t VALUES (?, ?)', [1, 'a']);
      expect(command.getSql()).assertEqual('INSERT INTO t VALUES (?, ?)');
      expect(command.getRawSqlArguments().length).assertEqual(2);
      expect(command.getRawSqlArguments()[0]).assertEqual(1);
      expect(command.getRawSqlArguments()[1]).assertEqual('a');
    });

    // isVacuumStatement: blank input is not vacuum, surrounding whitespace is
    // trimmed before matching, and only the VACUUM prefix matches
    it('isVacuumStatement_handles_blank_trimmed_and_prefixed', 0, () => {
      expect(isVacuumStatement('')).assertFalse();
      expect(isVacuumStatement('VACUUM')).assertTrue();
      expect(isVacuumStatement('  vacuum  ')).assertTrue();
      expect(isVacuumStatement('vacuum into /data/tmp/main.db')).assertTrue();
      expect(isVacuumStatement('VAC')).assertFalse();
      expect(isVacuumStatement('ANALYZE')).assertFalse();
    });

    // MethodCallOperation: getMethod returns the call method and toString
    // concatenates method, sql and arguments
    it('methodCallOperation_getMethod_and_toString', 0, () => {
      const args: Map<string, Object> = new Map<string, Object>();
      args.set(Constant.PARAM_SQL, 'SELECT 1');
      args.set(Constant.PARAM_SQL_ARGUMENTS, [1, 'a']);
      const operation: MethodCallOperation =
        new MethodCallOperation(makeCall('execute', args), new TestResult());
      expect(operation.getMethod()).assertEqual('execute');
      const text: string = operation.toString();
      expect(text).assertContain('execute');
      expect(text).assertContain('SELECT 1');
    });

    // getInTransactionChange: booleans pass through, any other type falls
    // back to false (getBoolean type guard)
    it('getInTransactionChange_parses_boolean_and_rejects_non_boolean', 0, () => {
      const truthyArgs: Map<string, Object> = new Map<string, Object>();
      truthyArgs.set(Constant.PARAM_IN_TRANSACTION_CHANGE, true);
      const truthy: MethodCallOperation =
        new MethodCallOperation(makeCall('execute', truthyArgs), new TestResult());
      expect(truthy.getInTransactionChange()).assertTrue();
      const falsyArgs: Map<string, Object> = new Map<string, Object>();
      falsyArgs.set(Constant.PARAM_IN_TRANSACTION_CHANGE, false);
      const falsy: MethodCallOperation =
        new MethodCallOperation(makeCall('execute', falsyArgs), new TestResult());
      expect(falsy.getInTransactionChange()).assertFalse();
      const stringArgs: Map<string, Object> = new Map<string, Object>();
      stringArgs.set(Constant.PARAM_IN_TRANSACTION_CHANGE, 'yes');
      const stringy: MethodCallOperation =
        new MethodCallOperation(makeCall('execute', stringArgs), new TestResult());
      expect(stringy.getInTransactionChange()).assertFalse();
    });

    // getArgument on sql arguments converts bigint values beyond the safe
    // integer range into their decimal string form (API >= 20 path)
    it('getArgument_converts_bigint_sql_arguments_to_strings', 0, () => {
      const list: Object[] = [BigInt('9007199254740993'), 'a'];
      const args: Map<string, Object> = new Map<string, Object>();
      args.set(Constant.PARAM_SQL_ARGUMENTS, list);
      const operation: MethodCallOperation =
        new MethodCallOperation(makeCall('execute', args), new TestResult());
      const out: Object[] = operation.getArgument<Object[]>(Constant.PARAM_SQL_ARGUMENTS);
      expect(out.length).assertEqual(2);
      expect(`${out[0]}`).assertEqual('9007199254740993');
      expect(`${out[1]}`).assertEqual('a');
    });

    // getArgument on batch operations converts bigint values inside each
    // operation's inner 'arguments' list into decimal strings
    it('getArgument_converts_bigint_inside_batch_operations', 0, () => {
      const innerArguments: Object[] = [BigInt('9007199254740994')];
      const inner: Map<string, Object> = new Map<string, Object>();
      inner.set(Constant.PARAM_METHOD, Constant.METHOD_INSERT);
      inner.set(Constant.PARAM_SQL, 'INSERT INTO t (v) VALUES (?)');
      inner.set(Constant.PARAM_SQL_ARGUMENTS, innerArguments);
      const operations: Object[] = [inner];
      const args: Map<string, Object> = new Map<string, Object>();
      args.set(Constant.PARAM_OPERATIONS, operations);
      const operation: MethodCallOperation =
        new MethodCallOperation(makeCall('batch', args), new TestResult());
      const out: Object[] = operation.getArgument<Object[]>(Constant.PARAM_OPERATIONS);
      expect(out.length).assertEqual(1);
      const innerOut: Map<string, Object> = out[0] as Map<string, Object>;
      const converted: Object[] = innerOut.get(Constant.PARAM_SQL_ARGUMENTS) as Object[];
      expect(`${converted[0]}`).assertEqual('9007199254740994');
    });

    // OperationError keeps the error code, message and data passed in
    it('operationError_keeps_fields', 0, () => {
      const error: OperationError = new OperationError('code1', 'message one', 'data one');
      expect(error.errorCode).assertEqual('code1');
      expect(error.errorMessage).assertEqual('message one');
      expect(`${error.errorData}`).assertEqual('data one');
    });

    // BatchOperation: constructor stores the map and noResult flag, and the
    // accessors reflect them (hasArgument, getMethod, getArgument, getNoResult)
    it('batchOperation_keeps_map_and_reflects_arguments', 0, () => {
      const map: Map<string, Object> = new Map<string, Object>();
      map.set(Constant.PARAM_METHOD, Constant.METHOD_INSERT);
      map.set(Constant.PARAM_SQL, 'INSERT INTO t (v) VALUES (?)');
      const operation: BatchOperation = new BatchOperation(map, false);
      expect(operation.getNoResult()).assertFalse();
      expect(operation.getMethod()).assertEqual(Constant.METHOD_INSERT);
      expect(operation.hasArgument(Constant.PARAM_SQL)).assertTrue();
      expect(operation.hasArgument(Constant.PARAM_SQL_ARGUMENTS)).assertFalse();
      expect(operation.getArgument<string>(Constant.PARAM_SQL)).assertEqual('INSERT INTO t (v) VALUES (?)');
    });
  });
}
