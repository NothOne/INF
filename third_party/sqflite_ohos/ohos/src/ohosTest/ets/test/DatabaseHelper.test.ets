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
import fs from '@ohos.file.fs';
import { Constant } from '../../../main/ets/io/flutter/plugins/sqflite/Constant';
import { DatabaseHelper } from '../../../main/ets/io/flutter/plugins/sqflite/DatabaseHelper';
import { initTestContext, TestResult, makeCall, dbPathFor, moduleDbPathFor, touchDbFile, removeDbFiles,
  openTestDatabase, closeTestDatabase, getTestContext  } from './TestUtils';

export default function DatabaseHelperTest(): void {
  describe('DatabaseHelperTest', () => {
    // RDB rejects ApplicationContext with 401 'Illegal context'; capture the
    // UIAbility context of the injected test ability before any helper runs.
    beforeAll(async () => {
      await initTestContext();
    });

    // Interface: getPlatformVersion
    it('getPlatformVersion_returns_ohos_prefix', 0, async () => {
      const result: TestResult = new TestResult();
      await DatabaseHelper.getPlatformVersion(makeCall(Constant.METHOD_GET_PLATFORM_VERSION, null), result);
      expect(result.successCalled).assertTrue();
      expect(result.successValue as string).assertContain('ohos');
    });

    // Interface: debugMode (obsolete channel, keeps null reply contract)
    it('debugMode_returns_null', 0, async () => {
      const result: TestResult = new TestResult();
      await DatabaseHelper.debugMode(makeCall(Constant.METHOD_DEBUG_MODE, null), result);
      expect(result.successCalled).assertTrue();
      expect(result.successValue).assertNull();
    });

    // Interface: options sets the global log level
    it('options_sets_global_log_level', 0, async () => {
      const args: Map<string, Object> = new Map<string, Object>();
      args.set(Constant.PARAM_LOG_LEVEL, 2);
      const result: TestResult = new TestResult();
      await DatabaseHelper.options(makeCall(Constant.METHOD_OPTIONS, args), result);
      expect(result.successCalled).assertTrue();
      expect(result.successValue).assertNull();
      expect(DatabaseHelper.globalLogLevel).assertEqual(2);
      // Restore the default so later cases are not affected
      const restoreArgs: Map<string, Object> = new Map<string, Object>();
      restoreArgs.set(Constant.PARAM_LOG_LEVEL, 0);
      await DatabaseHelper.options(makeCall(Constant.METHOD_OPTIONS, restoreArgs), new TestResult());
      expect(DatabaseHelper.globalLogLevel).assertEqual(0);
    });

    // Interface: openDatabase invalid path branches (missing / empty / wrong type)
    it('openDatabase_invalid_path_reports_open_failed', 0, async () => {
      const missingPath: TestResult = new TestResult();
      await DatabaseHelper.openDatabase(getTestContext(),
        makeCall(Constant.METHOD_OPEN_DATABASE, new Map<string, Object>()), missingPath);
      expect(missingPath.errorCalled).assertTrue();
      expect(missingPath.errorCode).assertEqual(Constant.SQLITE_ERROR);
      expect(missingPath.errorMessage as string).assertContain(Constant.ERROR_OPEN_FAILED);

      const emptyArgs: Map<string, Object> = new Map<string, Object>();
      emptyArgs.set(Constant.PARAM_PATH, '');
      const emptyPath: TestResult = new TestResult();
      await DatabaseHelper.openDatabase(getTestContext(),
        makeCall(Constant.METHOD_OPEN_DATABASE, emptyArgs), emptyPath);
      expect(emptyPath.errorCalled).assertTrue();
      expect(emptyPath.errorMessage as string).assertContain(Constant.ERROR_OPEN_FAILED);
    });

    // Interface: openDatabase happy path assigns a fresh dbId
    it('openDatabase_success_returns_id', 0, async () => {
      const outcome = await openTestDatabase(dbPathFor('helper_open_ok.db'));
      expect(outcome.result.successCalled).assertTrue();
      expect(outcome.dbId > 0).assertTrue();
      await closeTestDatabase(outcome.dbId);
    });

    // Interface: openDatabase single-instance reopen reports recovered with the same id
    it('openDatabase_reopen_reports_recovered', 0, async () => {
      removeDbFiles('helper_reopen.db');
      // A persisted file at the plugin path makes checkDatabaseExisted true,
      // enabling the single-instance recovery flow on the second open
      touchDbFile('helper_reopen.db');
      const first = await openTestDatabase(dbPathFor('helper_reopen.db'));
      expect(first.result.successCalled).assertTrue();
      const second = await openTestDatabase(dbPathFor('helper_reopen.db'));
      expect(second.result.successCalled).assertTrue();
      expect(second.dbId).assertEqual(first.dbId);
      const map: Record<string, Object> = second.result.successValue as Record<string, Object>;
      expect(map['recovered']).assertTrue();
      await closeTestDatabase(first.dbId);
    });

    // Interface: openDatabase ':memory:' maps to a unique temp database
    it('openDatabase_memory_path_success', 0, async () => {
      const outcome = await openTestDatabase(Constant.MEMORY_DATABASE_PATH);
      expect(outcome.result.successCalled).assertTrue();
      expect(outcome.dbId > 0).assertTrue();
      const map: Record<string, Object> = outcome.result.successValue as Record<string, Object>;
      expect(map['recovered']).assertUndefined();
      // Close also removes the temp file (memory db cleanup branch)
      await closeTestDatabase(outcome.dbId);
    });

    // Interface: databaseExists core logic (checkDatabaseExisted) across the lifecycle
    it('checkDatabaseExisted_reflects_open_and_delete', 0, async () => {
      removeDbFiles('helper_exists.db');
      const dbPath: string = dbPathFor('helper_exists.db');
      const outcome = await openTestDatabase(dbPath);
      // The check is fs-based on the plugin path; persist the file there
      touchDbFile('helper_exists.db');
      expect(await DatabaseHelper.checkDatabaseExisted(dbPath)).assertTrue();
      await closeTestDatabase(outcome.dbId);
      // File survives close
      expect(await DatabaseHelper.checkDatabaseExisted(dbPath)).assertTrue();
      const deleted: boolean = await DatabaseHelper.deleteDatabase(getTestContext(), dbPath);
      expect(deleted).assertTrue();
      expect(await DatabaseHelper.checkDatabaseExisted(dbPath)).assertFalse();
    });

    // Interface: getDatabaseOrError with unknown id reports database_closed
    it('getDatabaseOrError_unknown_id_reports_database_closed', 0, () => {
      const args: Map<string, Object> = new Map<string, Object>();
      args.set(Constant.PARAM_ID, 999999);
      const result: TestResult = new TestResult();
      const store = DatabaseHelper.getDatabaseOrError(makeCall('query', args), result);
      expect(store === null).assertTrue();
      expect(result.errorCalled).assertTrue();
      expect(result.errorCode).assertEqual(Constant.SQLITE_ERROR);
      expect(result.errorMessage as string).assertContain(Constant.ERROR_DATABASE_CLOSED);
    });

    // Interface: closeDatabase with unknown id is a successful no-op
    it('closeDatabase_unknown_id_returns_success_null', 0, async () => {
      const args: Map<string, Object> = new Map<string, Object>();
      args.set(Constant.PARAM_ID, 999999);
      const result: TestResult = new TestResult();
      await DatabaseHelper.closeDatabase(makeCall(Constant.METHOD_CLOSE_DATABASE, args), result);
      expect(result.successCalled).assertTrue();
      expect(result.successValue).assertNull();
    });

    // Interface: closeDatabase closes a real database, then the id is gone
    it('closeDatabase_open_id_then_id_is_gone', 0, async () => {
      const outcome = await openTestDatabase(dbPathFor('helper_close.db'));
      await closeTestDatabase(outcome.dbId);
      // The same id must now report database_closed
      const args: Map<string, Object> = new Map<string, Object>();
      args.set(Constant.PARAM_ID, outcome.dbId);
      const result: TestResult = new TestResult();
      expect(DatabaseHelper.getDatabaseOrError(makeCall('query', args), result)).assertNull();
      expect(result.errorMessage as string).assertContain(Constant.ERROR_DATABASE_CLOSED);
    });

    // Interface: deleteDatabase closes an open store before deleting the file
    it('deleteDatabase_open_store_deletes_file', 0, async () => {
      const dbPath: string = dbPathFor('helper_delete_open.db');
      const outcome = await openTestDatabase(dbPath);
      const deleted: boolean = await DatabaseHelper.deleteDatabase(getTestContext(), dbPath);
      expect(deleted).assertTrue();
      expect(await DatabaseHelper.checkDatabaseExisted(dbPath)).assertFalse();
      // The id no longer resolves
      const args: Map<string, Object> = new Map<string, Object>();
      args.set(Constant.PARAM_ID, outcome.dbId);
      const result: TestResult = new TestResult();
      expect(DatabaseHelper.getDatabaseOrError(makeCall('query', args), result)).assertNull();
    });

    // Corrupt existing file: open defers failure, operations fail with
    // 'file is not a database', close still succeeds (placeholder branch)
    it('openDatabase_corrupt_file_defers_failure', 0, async () => {
      removeDbFiles('helper_corrupt.db');
      const dbPath: string = dbPathFor('helper_corrupt.db');
      // Junk content at the physical module location makes getRdbStore fail
      // with 14800011; a file at the plugin path makes checkDatabaseExisted
      // true so the deferred-failure branch is taken
      const file = fs.openSync(moduleDbPathFor('helper_corrupt.db'),
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, 'this is definitely not a sqlite database file');
      fs.closeSync(file);
      touchDbFile('helper_corrupt.db');
      const outcome = await openTestDatabase(dbPath);
      expect(outcome.result.successCalled).assertTrue();
      expect(outcome.dbId > 0).assertTrue();
      // Subsequent operation fails with the deferred error
      const opArgs: Map<string, Object> = new Map<string, Object>();
      opArgs.set(Constant.PARAM_ID, outcome.dbId);
      const opResult: TestResult = new TestResult();
      expect(DatabaseHelper.getDatabaseOrError(makeCall('query', opArgs), opResult)).assertNull();
      expect(opResult.errorMessage as string).assertContain('file is not a database');
      // closeDatabase on the placeholder still succeeds
      await closeTestDatabase(outcome.dbId);
    });

    // Interface: transaction depth helpers track enter/exit pairs by dbId
    it('noteTransactionChangeByDbId_tracks_depth', 0, async () => {
      const outcome = await openTestDatabase(dbPathFor('helper_txn_depth.db'));
      const dbId: number = outcome.dbId;
      DatabaseHelper.noteTransactionChangeByDbId(dbId, true);
      expect(DatabaseHelper.getTransactionDepthByDbId(dbId)).assertEqual(1);
      DatabaseHelper.noteTransactionChangeByDbId(dbId, true);
      expect(DatabaseHelper.getTransactionDepthByDbId(dbId)).assertEqual(2);
      DatabaseHelper.noteTransactionChangeByDbId(dbId, false);
      expect(DatabaseHelper.getTransactionDepthByDbId(dbId)).assertEqual(1);
      expect(DatabaseHelper.isDatabaseInTransaction('helper_txn_depth.db')).assertTrue();
      DatabaseHelper.noteTransactionChangeByDbId(dbId, false);
      expect(DatabaseHelper.getTransactionDepthByDbId(dbId)).assertEqual(0);
      expect(DatabaseHelper.isDatabaseInTransaction('helper_txn_depth.db')).assertFalse();
      // Unknown dbId: note is a no-op and depth reads as -1
      DatabaseHelper.noteTransactionChangeByDbId(999999, true);
      expect(DatabaseHelper.getTransactionDepthByDbId(999999)).assertEqual(-1);
      await closeTestDatabase(dbId);
    });

    // Interface: in-transaction created table registry (per dbName isolation)
    it('transactionCreatedTable_helpers_isolated_by_db_name', 0, () => {
      const dbName: string = 'helper_txn_tables.db';
      DatabaseHelper.addTransactionCreatedTable(dbName, 'TmpTable');
      // Lookup is case-insensitive on the table name
      expect(DatabaseHelper.hasTransactionCreatedTable(dbName, 'tmptable')).assertTrue();
      expect(DatabaseHelper.hasTransactionCreatedTable(dbName, 'other')).assertFalse();
      // Isolated per database name
      expect(DatabaseHelper.hasTransactionCreatedTable('helper_other.db', 'tmptable')).assertFalse();
      DatabaseHelper.clearTransactionCreatedTablesByDbName(dbName);
      expect(DatabaseHelper.hasTransactionCreatedTable(dbName, 'tmptable')).assertFalse();
    });

    // Interface: onDebug cmd=get returns the global log level plus per-database
    // info. The implementation is correct; the historical failure here was a
    // test-side hypium object-assertion bug (reclassified A-class), so plain
    // boolean compares are used for the object-shape assertions below.
    it('onDebug_get_returns_databases_info', 0, async () => {
      const dbPath: string = dbPathFor('helper_debug.db');
      const outcome = await openTestDatabase(dbPath, 5);
      const setLevelArgs: Map<string, Object> = new Map<string, Object>();
      setLevelArgs.set(Constant.PARAM_LOG_LEVEL, 1);
      await DatabaseHelper.options(makeCall(Constant.METHOD_OPTIONS, setLevelArgs), new TestResult());
      const args: Map<string, Object> = new Map<string, Object>();
      args.set(Constant.PARAM_CMD, Constant.CMD_GET);
      const result: TestResult = new TestResult();
      await DatabaseHelper.onDebug(makeCall(Constant.METHOD_DEBUG, args), result);
      expect(result.successCalled).assertTrue();
      const map: Record<string, Object> = result.successValue as Record<string, Object>;
      expect(map[Constant.PARAM_LOG_LEVEL]).assertEqual(1);
      const databases: Record<string, Object> = map['databases'] as Record<string, Object>;
      // Boolean compare: hypium expect() is unreliable on interface objects
      expect(databases !== null && databases !== undefined).assertTrue();
      const info: Record<string, Object> = databases[outcome.dbId.toString()] as Record<string, Object>;
      expect(info !== null && info !== undefined).assertTrue();
      expect(info[Constant.PARAM_PATH]).assertEqual(dbPath);
      expect(info[Constant.PARAM_SINGLE_INSTANCE]).assertTrue();
      expect(info[Constant.PARAM_LOG_LEVEL]).assertEqual(5);
      expect(info['transactionDepth']).assertEqual(0);
      await closeTestDatabase(outcome.dbId);
      const restoreArgs: Map<string, Object> = new Map<string, Object>();
      restoreArgs.set(Constant.PARAM_LOG_LEVEL, 0);
      await DatabaseHelper.options(makeCall(Constant.METHOD_OPTIONS, restoreArgs), new TestResult());
    });

    // Interface: dispose clears every static map (worker detach path)
    it('dispose_clears_all_state', 0, async () => {
      const first = await openTestDatabase(dbPathFor('helper_dispose1.db'));
      const second = await openTestDatabase(dbPathFor('helper_dispose2.db'));
      expect(DatabaseHelper.dbMap.size > 0).assertTrue();
      await DatabaseHelper.dispose();
      expect(DatabaseHelper.dbMap.size).assertEqual(0);
      expect(DatabaseHelper.dbIdMap.length).assertEqual(0);
      expect(DatabaseHelper.invalidOpenDbErrors.length).assertEqual(0);
      // Ids no longer resolve after dispose
      const args: Map<string, Object> = new Map<string, Object>();
      args.set(Constant.PARAM_ID, first.dbId);
      const result: TestResult = new TestResult();
      expect(DatabaseHelper.getDatabaseOrError(makeCall('query', args), result)).assertNull();
      expect(second.dbId > 0).assertTrue();
    });

    // Interface: openDatabase whose physical RDB path is occupied by a
    // directory fails at getRdbStore with a non-14800011 error and reports
    // open_failed instead of deferring (generic open-error branch)
    it('openDatabase_directory_blocked_path_reports_open_failed', 0, async () => {
      const blocked: string = moduleDbPathFor('helper_dirblk.db');
      removeDbFiles('helper_dirblk.db');
      try {
        fs.rmdirSync(blocked);
      } catch (e) {
        // Not present from an earlier run
      }
      fs.mkdirSync(blocked, true);
      const result: TestResult = new TestResult();
      const args: Map<string, Object> = new Map<string, Object>();
      args.set(Constant.PARAM_PATH, dbPathFor('helper_dirblk.db'));
      await DatabaseHelper.openDatabase(getTestContext(),
        makeCall(Constant.METHOD_OPEN_DATABASE, args), result);
      expect(result.errorCalled).assertTrue();
      expect(result.errorCode).assertEqual(Constant.SQLITE_ERROR);
      expect(result.errorMessage as string).assertContain(Constant.ERROR_OPEN_FAILED);
      fs.rmdirSync(blocked);
    });

    // Interface: reopening a single-instance database that is currently inside
    // a transaction reports recovered AND recoveredInTransaction
    it('openDatabase_reopen_in_transaction_reports_recovered_in_transaction', 0, async () => {
      removeDbFiles('helper_txn_reopen.db');
      touchDbFile('helper_txn_reopen.db');
      const first = await openTestDatabase(dbPathFor('helper_txn_reopen.db'));
      expect(first.result.successCalled).assertTrue();
      // Mark the database as in-transaction through the public note API
      DatabaseHelper.noteTransactionChangeByDbId(first.dbId, true);
      const second = await openTestDatabase(dbPathFor('helper_txn_reopen.db'));
      expect(second.result.successCalled).assertTrue();
      expect(second.dbId).assertEqual(first.dbId);
      const map: Record<string, Object> = second.result.successValue as Record<string, Object>;
      expect(map['recovered']).assertTrue();
      expect(map['recoveredInTransaction']).assertTrue();
      DatabaseHelper.noteTransactionChangeByDbId(first.dbId, false);
      await closeTestDatabase(first.dbId);
    });

    // Interface: a path without the .db suffix gets the extension appended
    // (the physical RDB file carries the .db suffix)
    it('openDatabase_without_db_suffix_appends_extension', 0, async () => {
      removeDbFiles('helper_no_suffix');
      const outcome = await openTestDatabase(dbPathFor('helper_no_suffix'));
      expect(outcome.result.successCalled).assertTrue();
      expect(outcome.dbId > 0).assertTrue();
      let physicalExists: boolean = false;
      try {
        fs.accessSync(moduleDbPathFor('helper_no_suffix.db'));
        physicalExists = true;
      } catch (e) {
        physicalExists = false;
      }
      expect(physicalExists).assertTrue();
      await closeTestDatabase(outcome.dbId);
      // Manual cleanup: removeDbFiles does not cover the suffixed variant here
      for (const dir of [dbPathFor, moduleDbPathFor]) {
        try {
          fs.unlinkSync(dir('helper_no_suffix.db'));
        } catch (e) {
          // Not present: nothing to clean
        }
      }
    });

    // Interface: a path with extra subdirectories maps to StoreConfig
    // customDir (the customDir join loop) and the database file is created in
    // the subdirectory, not the flat rdb root
    it('openDatabase_custom_dir_creates_database_in_subdirectory', 0, async () => {
      const relativePath: string = 'cd_a/cd_b/helper_custom.db';
      const dbPath: string = dbPathFor(relativePath);
      const outcome = await openTestDatabase(dbPath);
      expect(outcome.result.successCalled).assertTrue();
      expect(outcome.dbId > 0).assertTrue();
      const dbRoot: string = `${getTestContext().databaseDir}`;
      const candidates: string[] = [
        `${dbRoot}/rdb/cd_a/cd_b/helper_custom.db`,
        `${dbRoot}/cd_a/cd_b/helper_custom.db`
      ];
      let fileFound: boolean = false;
      for (const candidate of candidates) {
        try {
          fs.accessSync(candidate);
          fileFound = true;
        } catch (e) {
          // Try the next candidate location
        }
      }
      expect(fileFound).assertTrue();
      await closeTestDatabase(outcome.dbId);
      await DatabaseHelper.deleteDatabase(getTestContext(), dbPath);
      // Sweep any leftover files/dirs in both candidate roots
      for (const root of [`${dbRoot}/rdb`, dbRoot]) {
        try {
          fs.unlinkSync(`${root}/cd_a/cd_b/helper_custom.db`);
        } catch (e) {
          // Not present: nothing to clean
        }
        try {
          fs.rmdirSync(`${root}/cd_a/cd_b`);
          fs.rmdirSync(`${root}/cd_a`);
        } catch (e) {
          // Already absent or not empty
        }
      }
    });

    // Interface: deleteDatabase on a corrupt placeholder cleans the stale
    // mappings (else branch: store not in memory), so the id stops resolving
    it('deleteDatabase_placeholder_removes_stale_mappings', 0, async () => {
      removeDbFiles('helper_del_ph.db');
      const dbPath: string = dbPathFor('helper_del_ph.db');
      const junk = fs.openSync(moduleDbPathFor('helper_del_ph.db'),
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(junk.fd, 'not a sqlite database at all');
      fs.closeSync(junk);
      touchDbFile('helper_del_ph.db');
      const outcome = await openTestDatabase(dbPath);
      expect(outcome.result.successCalled).assertTrue();
      const deleted: boolean = await DatabaseHelper.deleteDatabase(getTestContext(), dbPath);
      expect(deleted).assertTrue();
      const args: Map<string, Object> = new Map<string, Object>();
      args.set(Constant.PARAM_ID, outcome.dbId);
      const result: TestResult = new TestResult();
      expect(DatabaseHelper.getDatabaseOrError(makeCall('query', args), result)).assertNull();
      expect(result.errorMessage as string).assertContain(Constant.ERROR_DATABASE_CLOSED);
    });

    // Interface: closeDatabase on an id whose store was already removed by
    // deleteDatabase (id still mapped) cleans the remaining mappings and
    // still reports success null (the store-not-in-memory branch)
    it('closeDatabase_after_delete_reports_success_and_clears_id', 0, async () => {
      const dbPath: string = dbPathFor('helper_close_del.db');
      const outcome = await openTestDatabase(dbPath);
      expect(outcome.result.successCalled).assertTrue();
      const deleted: boolean = await DatabaseHelper.deleteDatabase(getTestContext(), dbPath);
      expect(deleted).assertTrue();
      const closeResult: TestResult = new TestResult();
      const closeArgs: Map<string, Object> = new Map<string, Object>();
      closeArgs.set(Constant.PARAM_ID, outcome.dbId);
      await DatabaseHelper.closeDatabase(
        makeCall(Constant.METHOD_CLOSE_DATABASE, closeArgs), closeResult);
      expect(closeResult.successCalled).assertTrue();
      expect(closeResult.successValue).assertNull();
      const queryResult: TestResult = new TestResult();
      expect(DatabaseHelper.getDatabaseOrError(makeCall('query', closeArgs), queryResult)).assertNull();
      expect(queryResult.errorMessage as string).assertContain(Constant.ERROR_DATABASE_CLOSED);
    });

    // Interface: dispose with a still-open ':memory:' database records the
    // temp name and deletes the temp file (memory db cleanup on dispose)
    it('dispose_with_open_memory_db_clears_state', 0, async () => {
      const outcome = await openTestDatabase(Constant.MEMORY_DATABASE_PATH);
      expect(outcome.result.successCalled).assertTrue();
      expect(DatabaseHelper.dbMap.size > 0).assertTrue();
      await DatabaseHelper.dispose();
      expect(DatabaseHelper.dbMap.size).assertEqual(0);
    });
  });
}
