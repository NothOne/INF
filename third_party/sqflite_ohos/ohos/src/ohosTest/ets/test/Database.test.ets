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
import relationalStore from '@ohos.data.relationalStore';
import { ValueType } from '@ohos.data.ValuesBucket';
import { Constant } from '../../../main/ets/io/flutter/plugins/sqflite/Constant';
import { Database } from '../../../main/ets/io/flutter/plugins/sqflite/Database';
import { DatabaseHelper } from
  '../../../main/ets/io/flutter/plugins/sqflite/DatabaseHelper';
import { MethodCallOperation } from
  '../../../main/ets/io/flutter/plugins/sqflite/operation/MethodCallOperation';
import { initTestContext, TestResult, makeCall, dbPathFor, moduleDbPathFor, removeDbFiles,
  openTestDatabase, closeTestDatabase, getTestContext  } from './TestUtils';

class FreshDb {
  public dbId: number = -1;
  public store: relationalStore.RdbStore | null = null;
}

// Open a fresh database and resolve its RdbStore through the public interface.
async function openFreshDb(name: string): Promise<FreshDb> {
  // Drop leftovers from earlier runs so schema-creating cases stay idempotent
  removeDbFiles(name);
  const outcome = await openTestDatabase(dbPathFor(name));
  expect(outcome.result.successCalled).assertTrue();
  const args: Map<string, Object> = new Map<string, Object>();
  args.set(Constant.PARAM_ID, outcome.dbId);
  const store: relationalStore.RdbStore | null =
    DatabaseHelper.getDatabaseOrError(makeCall('execute', args), new TestResult());
  expect(store !== null).assertTrue();
  const fresh: FreshDb = new FreshDb();
  fresh.dbId = outcome.dbId;
  fresh.store = store;
  return fresh;
}

// Run one channel operation through the Database public entry points.
async function runDbCall(db: FreshDb, method: string, sql: string | null,
  sqlArguments?: ValueType[] | null, extra?: Map<string, Object | null> | null): Promise<TestResult> {
  const args: Map<string, Object | null> = extra ?? new Map<string, Object | null>();
  args.set(Constant.PARAM_ID, db.dbId);
  if (sql !== null) {
    args.set(Constant.PARAM_SQL, sql);
  }
  if (sqlArguments !== undefined && sqlArguments !== null) {
    args.set(Constant.PARAM_SQL_ARGUMENTS, sqlArguments);
  }
  const result: TestResult = new TestResult();
  const operation: MethodCallOperation = new MethodCallOperation(makeCall(method, args), result);
  if (method === Constant.METHOD_EXECUTE) {
    await Database.execute(operation, db.store as relationalStore.RdbStore);
  } else if (method === Constant.METHOD_INSERT) {
    await Database.insert(operation, db.store as relationalStore.RdbStore);
  } else if (method === Constant.METHOD_UPDATE) {
    await Database.update(operation, db.store as relationalStore.RdbStore);
  } else if (method === Constant.METHOD_QUERY) {
    await Database.query(operation, db.store as relationalStore.RdbStore);
  } else if (method === Constant.METHOD_QUERY_CURSOR_NEXT) {
    await Database.queryCursorNext(operation);
  }
  return result;
}

// Build one batch operation map.
function makeOp(method: string, sql: string | null, sqlArguments?: ValueType[] | null): Map<string, Object> {
  const op: Map<string, Object> = new Map<string, Object>();
  op.set(Constant.PARAM_METHOD, method);
  if (sql !== null) {
    op.set(Constant.PARAM_SQL, sql);
  }
  if (sqlArguments !== undefined && sqlArguments !== null) {
    op.set(Constant.PARAM_SQL_ARGUMENTS, sqlArguments);
  }
  return op;
}

// Run a batch call with the given main-level flags.
async function runBatch(db: FreshDb, operations: Object, noResult: boolean | null,
  continueOnError: boolean | null): Promise<TestResult> {
  const args: Map<string, Object | null> = new Map<string, Object | null>();
  args.set(Constant.PARAM_ID, db.dbId);
  args.set(Constant.PARAM_OPERATIONS, operations);
  if (noResult !== null) {
    args.set(Constant.PARAM_NO_RESULT, noResult);
  }
  if (continueOnError !== null) {
    args.set(Constant.PARAM_CONTINUE_OR_ERROR, continueOnError);
  }
  const result: TestResult = new TestResult();
  await Database.batch(makeCall(Constant.METHOD_BATCH, args), result,
    db.store as relationalStore.RdbStore);
  return result;
}

export default function DatabaseTest(): void {
  describe('DatabaseTest', () => {
    // RDB rejects ApplicationContext with 401 'Illegal context'; capture the
    // UIAbility context of the injected test ability before any helper runs.
    beforeAll(async () => {
      await initTestContext();
    });

    // Interface: execute with DDL
    it('execute_ddl_create_table_success', 0, async () => {
      const db = await openFreshDb('db_exec_ddl.db');
      const result = await runDbCall(db, Constant.METHOD_EXECUTE,
        'CREATE TABLE t_exec (id INTEGER PRIMARY KEY, name TEXT)');
      expect(result.successCalled).assertTrue();
      expect(result.successValue).assertNull();
      await closeTestDatabase(db.dbId);
    });

    // Interface: execute with DML + bind arguments
    it('execute_dml_with_arguments_success', 0, async () => {
      const db = await openFreshDb('db_exec_dml.db');
      await runDbCall(db, Constant.METHOD_EXECUTE,
        'CREATE TABLE t_exec (id INTEGER PRIMARY KEY, name TEXT)');
      const result = await runDbCall(db, Constant.METHOD_EXECUTE,
        'INSERT INTO t_exec (id, name) VALUES (?, ?)', [1, 'a']);
      expect(result.successCalled).assertTrue();
      await closeTestDatabase(db.dbId);
    });

    // Interface: execute BEGIN IMMEDIATE enters a transaction and returns an id
    it('execute_begin_immediate_returns_transaction_id', 0, async () => {
      const db = await openFreshDb('db_begin.db');
      const extra: Map<string, Object | null> = new Map<string, Object | null>();
      extra.set(Constant.PARAM_IN_TRANSACTION_CHANGE, true);
      extra.set(Constant.PARAM_TRANSACTION_ID, null);
      const begin = await runDbCall(db, Constant.METHOD_EXECUTE,
        Constant.SQL_BEGIN_IMMEDIATE, undefined, extra);
      expect(begin.successCalled).assertTrue();
      const beginMap: Map<string, Object> = begin.successValue as Map<string, Object>;
      expect(beginMap.get(Constant.PARAM_TRANSACTION_ID)).assertEqual(1);
      expect(DatabaseHelper.getTransactionDepthByDbId(db.dbId)).assertEqual(1);
      const extraLeave: Map<string, Object | null> = new Map<string, Object | null>();
      extraLeave.set(Constant.PARAM_IN_TRANSACTION_CHANGE, false);
      const commit = await runDbCall(db, Constant.METHOD_EXECUTE,
        Constant.SQL_COMMIT, undefined, extraLeave);
      expect(commit.successCalled).assertTrue();
      expect(commit.successValue).assertNull();
      expect(DatabaseHelper.getTransactionDepthByDbId(db.dbId)).assertEqual(0);
      await closeTestDatabase(db.dbId);
    });

    // 'BEGIN IMMEDIATE TRANSACTION' wording matches the same handler
    it('execute_begin_immediate_transaction_wording_matches', 0, async () => {
      const db = await openFreshDb('db_begin2.db');
      const extra: Map<string, Object | null> = new Map<string, Object | null>();
      extra.set(Constant.PARAM_IN_TRANSACTION_CHANGE, true);
      extra.set(Constant.PARAM_TRANSACTION_ID, null);
      const begin = await runDbCall(db, Constant.METHOD_EXECUTE,
        Constant.SQL_BEGIN_IMMEDIATE + ' TRANSACTION', undefined, extra);
      expect(begin.successCalled).assertTrue();
      const extraLeave: Map<string, Object | null> = new Map<string, Object | null>();
      extraLeave.set(Constant.PARAM_IN_TRANSACTION_CHANGE, false);
      await runDbCall(db, Constant.METHOD_EXECUTE, Constant.SQL_ROLLBACK, undefined, extraLeave);
      await closeTestDatabase(db.dbId);
    });

    // BEGIN EXCLUSIVE is a no-op success on OHOS, both wordings
    it('execute_begin_exclusive_noop_success', 0, async () => {
      const db = await openFreshDb('db_exclusive.db');
      const first = await runDbCall(db, Constant.METHOD_EXECUTE, Constant.SQL_BEGIN_EXCLUSIVE);
      expect(first.successCalled).assertTrue();
      expect(first.successValue).assertNull();
      const second = await runDbCall(db, Constant.METHOD_EXECUTE,
        Constant.SQL_BEGIN_EXCLUSIVE + ' TRANSACTION');
      expect(second.successCalled).assertTrue();
      await closeTestDatabase(db.dbId);
    });

    // Interface: execute ROLLBACK discards the transaction's writes
    it('execute_rollback_discards_writes', 0, async () => {
      const db = await openFreshDb('db_rollback.db');
      await runDbCall(db, Constant.METHOD_EXECUTE,
        'CREATE TABLE t_rb (id INTEGER PRIMARY KEY, name TEXT)');
      const extraEnter: Map<string, Object | null> = new Map<string, Object | null>();
      extraEnter.set(Constant.PARAM_IN_TRANSACTION_CHANGE, true);
      extraEnter.set(Constant.PARAM_TRANSACTION_ID, null);
      await runDbCall(db, Constant.METHOD_EXECUTE,
        Constant.SQL_BEGIN_IMMEDIATE, undefined, extraEnter);
      await runDbCall(db, Constant.METHOD_EXECUTE,
        'INSERT INTO t_rb (id, name) VALUES (1, ?)', ['kept']);
      const extraLeave: Map<string, Object | null> = new Map<string, Object | null>();
      extraLeave.set(Constant.PARAM_IN_TRANSACTION_CHANGE, false);
      await runDbCall(db, Constant.METHOD_EXECUTE, Constant.SQL_ROLLBACK, undefined, extraLeave);
      const query = await runDbCall(db, Constant.METHOD_QUERY, 'SELECT id FROM t_rb');
      const queryMap: Map<string, Object> = query.successValue as Map<string, Object>;
      expect((queryMap.get(Constant.PARAM_ROWS) as Object[]).length).assertEqual(0);
      await closeTestDatabase(db.dbId);
    });

    // Table created inside a transaction: the OHOS RDB query interface does
    // not expose columns for a table created in the same open transaction
    // (columns arrive empty until the DDL is committed), so verify both the
    // in-transaction contract and the post-commit visibility
    it('execute_ddl_in_transaction_visible', 0, async () => {
      const db = await openFreshDb('db_txn_ddl.db');
      const extraEnter: Map<string, Object | null> = new Map<string, Object | null>();
      extraEnter.set(Constant.PARAM_IN_TRANSACTION_CHANGE, true);
      extraEnter.set(Constant.PARAM_TRANSACTION_ID, null);
      await runDbCall(db, Constant.METHOD_EXECUTE,
        Constant.SQL_BEGIN_IMMEDIATE, undefined, extraEnter);
      await runDbCall(db, Constant.METHOD_EXECUTE, 'CREATE TABLE t_txn (v TEXT)');
      const inside = await runDbCall(db, Constant.METHOD_QUERY, 'SELECT v FROM t_txn');
      expect(inside.successCalled).assertTrue();
      const insideMap: Map<string, Object> = inside.successValue as Map<string, Object>;
      // Platform behavior: the query succeeds but column metadata for the
      // just-created table is not reported until the transaction commits
      expect((insideMap.get(Constant.PARAM_COLUMNS) as string[]).length).assertEqual(0);
      expect((insideMap.get(Constant.PARAM_ROWS) as Object[]).length).assertEqual(0);
      const extraLeave: Map<string, Object | null> = new Map<string, Object | null>();
      extraLeave.set(Constant.PARAM_IN_TRANSACTION_CHANGE, false);
      await runDbCall(db, Constant.METHOD_EXECUTE, Constant.SQL_COMMIT, undefined, extraLeave);
      // After COMMIT the table is fully visible with its column layout
      const after = await runDbCall(db, Constant.METHOD_QUERY, 'SELECT v FROM t_txn');
      expect(after.successCalled).assertTrue();
      const afterMap: Map<string, Object> = after.successValue as Map<string, Object>;
      expect((afterMap.get(Constant.PARAM_COLUMNS) as string[]).length).assertEqual(1);
      expect((afterMap.get(Constant.PARAM_ROWS) as Object[]).length).assertEqual(0);
      await closeTestDatabase(db.dbId);
    });

    // Interface: execute ATTACH/DETACH with literal path and schema
    it('execute_attach_detach_literal_success', 0, async () => {
      // Materialize the source database file with real content first; RDB
      // attach only accepts an existing file at the physical module path
      const src = await openFreshDb('db_attach_src.db');
      await runDbCall(src, Constant.METHOD_EXECUTE, 'CREATE TABLE IF NOT EXISTS t_src (v TEXT)');
      await closeTestDatabase(src.dbId);
      const db = await openFreshDb('db_attach_main.db');
      const attach = await runDbCall(db, Constant.METHOD_EXECUTE,
        'ATTACH DATABASE \'' + moduleDbPathFor('db_attach_src.db') + '\' AS aux1');
      expect(attach.successCalled).assertTrue();
      expect(attach.successValue).assertNull();
      const detach = await runDbCall(db, Constant.METHOD_EXECUTE, 'DETACH DATABASE aux1');
      expect(detach.successCalled).assertTrue();
      await closeTestDatabase(db.dbId);
    });

    // Interface: execute ATTACH/DETACH with '?' placeholders fed from arguments
    it('execute_attach_detach_placeholder_args_success', 0, async () => {
      const src = await openFreshDb('db_attach_src2.db');
      await runDbCall(src, Constant.METHOD_EXECUTE, 'CREATE TABLE IF NOT EXISTS t_src (v TEXT)');
      await closeTestDatabase(src.dbId);
      const db = await openFreshDb('db_attach_ph.db');
      const attach = await runDbCall(db, Constant.METHOD_EXECUTE,
        'ATTACH DATABASE ? AS ?', [moduleDbPathFor('db_attach_src2.db'), 'aux2']);
      expect(attach.successCalled).assertTrue();
      const detach = await runDbCall(db, Constant.METHOD_EXECUTE,
        'DETACH DATABASE ?', ['aux2']);
      expect(detach.successCalled).assertTrue();
      await closeTestDatabase(db.dbId);
    });

    // ATTACH/DETACH missing sql arguments report a precise error
    it('execute_attach_detach_missing_arguments_error', 0, async () => {
      const db = await openFreshDb('db_attach_missing.db');
      const attach = await runDbCall(db, Constant.METHOD_EXECUTE, 'ATTACH DATABASE ? AS ?');
      expect(attach.errorCalled).assertTrue();
      expect(attach.errorCode).assertEqual(Constant.SQLITE_ERROR);
      expect(attach.errorMessage as string).assertContain('attach: missing sql arguments');
      const detach = await runDbCall(db, Constant.METHOD_EXECUTE, 'DETACH DATABASE ?');
      expect(detach.errorCalled).assertTrue();
      expect(detach.errorMessage as string).assertContain('detach: missing sql arguments');
      await closeTestDatabase(db.dbId);
    });

    // Interface: execute VACUUM reports an explicit not-supported error
    it('execute_vacuum_executes_or_reports_not_supported', 0, async () => {
      const db = await openFreshDb('db_vacuum.db');
      const result = await runDbCall(db, Constant.METHOD_EXECUTE, Constant.SQL_VACUUM);
      // The handler first attempts a real VACUUM via executeSql; this engine
      // accepts it, so the call succeeds. Engines that reject it fall back to
      // the explicit "not supported" error (see query-side case below).
      expect(result.successCalled).assertTrue();
      await closeTestDatabase(db.dbId);
    });

    // Interface: execute against a missing table reports an error
    it('execute_missing_table_reports_error', 0, async () => {
      const db = await openFreshDb('db_missing_table.db');
      const result = await runDbCall(db, Constant.METHOD_EXECUTE,
        'INSERT INTO missing_table (v) VALUES (?)', [1]);
      expect(result.errorCalled).assertTrue();
      expect(result.errorCode).assertEqual(Constant.SQLITE_ERROR);
      await closeTestDatabase(db.dbId);
    });

    // CREATE TABLE twice reports already exists
    it('execute_create_existing_table_reports_already_exists', 0, async () => {
      const db = await openFreshDb('db_create_twice.db');
      const ddl = 'CREATE TABLE t_twice (v TEXT)';
      await runDbCall(db, Constant.METHOD_EXECUTE, ddl);
      const second = await runDbCall(db, Constant.METHOD_EXECUTE, ddl);
      expect(second.errorCalled).assertTrue();
      expect(second.errorMessage as string).assertContain('exists');
      await closeTestDatabase(db.dbId);
    });

    // Interface: insert returns the generated row id
    it('insert_returns_row_id', 0, async () => {
      const db = await openFreshDb('db_insert.db');
      await runDbCall(db, Constant.METHOD_EXECUTE,
        'CREATE TABLE t_ins (id INTEGER PRIMARY KEY, name TEXT)');
      const result = await runDbCall(db, Constant.METHOD_INSERT,
        'INSERT INTO t_ins (name) VALUES (?)', ['a']);
      expect(result.successCalled).assertTrue();
      expect(result.successValue).assertEqual(1);
      await closeTestDatabase(db.dbId);
    });

    // insert honors noResult
    it('insert_no_result_returns_null', 0, async () => {
      const db = await openFreshDb('db_insert_nores.db');
      await runDbCall(db, Constant.METHOD_EXECUTE,
        'CREATE TABLE t_ins2 (id INTEGER PRIMARY KEY, name TEXT)');
      const extra: Map<string, Object | null> = new Map<string, Object | null>();
      extra.set(Constant.PARAM_NO_RESULT, true);
      const result = await runDbCall(db, Constant.METHOD_INSERT,
        'INSERT INTO t_ins2 (name) VALUES (?)', ['a'], extra);
      expect(result.successCalled).assertTrue();
      expect(result.successValue).assertNull();
      await closeTestDatabase(db.dbId);
    });

    // INSERT OR IGNORE on conflict returns null (rowId 0 contract)
    it('insert_or_ignore_returns_null_on_conflict', 0, async () => {
      const db = await openFreshDb('db_insert_ignore.db');
      await runDbCall(db, Constant.METHOD_EXECUTE,
        'CREATE TABLE t_ign (id INTEGER PRIMARY KEY, name TEXT UNIQUE)');
      await runDbCall(db, Constant.METHOD_INSERT, 'INSERT INTO t_ign (name) VALUES (?)', ['a']);
      const result = await runDbCall(db, Constant.METHOD_INSERT,
        'INSERT OR IGNORE INTO t_ign (name) VALUES (?)', ['a']);
      expect(result.successCalled).assertTrue();
      expect(result.successValue).assertNull();
      await closeTestDatabase(db.dbId);
    });

    // insert unique constraint violation maps to code 2067
    it('insert_unique_constraint_maps_to_2067', 0, async () => {
      const db = await openFreshDb('db_const_unique.db');
      await runDbCall(db, Constant.METHOD_EXECUTE,
        'CREATE TABLE t_u (v TEXT UNIQUE)');
      await runDbCall(db, Constant.METHOD_INSERT, 'INSERT INTO t_u (v) VALUES (?)', ['a']);
      const result = await runDbCall(db, Constant.METHOD_INSERT, 'INSERT INTO t_u (v) VALUES (?)', ['a']);
      expect(result.errorCalled).assertTrue();
      expect(result.errorCode).assertEqual(Constant.SQLITE_ERROR);
      expect(result.errorMessage as string).assertContain('(code 2067)');
      await closeTestDatabase(db.dbId);
    });

    // insert with a multi-column INSERT list violating the primary key maps to
    // code 1555 (SQLITE_CONSTRAINT_PRIMARYKEY), matching the Android plugin
    // (fixed: the constraint regex now captures the full column list)
    it('insert_primary_key_constraint_maps_to_1555', 0, async () => {
      const db = await openFreshDb('db_const_pk.db');
      await runDbCall(db, Constant.METHOD_EXECUTE,
        'CREATE TABLE t_p (id INTEGER PRIMARY KEY, v TEXT)');
      await runDbCall(db, Constant.METHOD_INSERT,
        'INSERT INTO t_p (id, v) VALUES (?, ?)', [1, 'a']);
      const result = await runDbCall(db, Constant.METHOD_INSERT,
        'INSERT INTO t_p (id, v) VALUES (?, ?)', [1, 'a']);
      expect(result.errorCalled).assertTrue();
      expect(result.errorCode).assertEqual(Constant.SQLITE_ERROR);
      expect(result.errorMessage as string).assertContain('(code 1555)');
      await closeTestDatabase(db.dbId);
    });

    // composite primary key violation also maps to 1555: PRAGMA table_info
    // reports pk ordinals (1, 2) for composite keys, all pk columns covered by
    // the INSERT means a primary-key conflict (fixed alongside defect #3)
    it('insert_composite_primary_key_constraint_maps_to_1555', 0, async () => {
      const db = await openFreshDb('db_const_pk_composite.db');
      await runDbCall(db, Constant.METHOD_EXECUTE,
        'CREATE TABLE t_pc (a INTEGER, b INTEGER, PRIMARY KEY (a, b))');
      await runDbCall(db, Constant.METHOD_INSERT,
        'INSERT INTO t_pc (a, b) VALUES (?, ?)', [1, 2]);
      const result = await runDbCall(db, Constant.METHOD_INSERT,
        'INSERT INTO t_pc (a, b) VALUES (?, ?)', [1, 2]);
      expect(result.errorCalled).assertTrue();
      expect(result.errorCode).assertEqual(Constant.SQLITE_ERROR);
      expect(result.errorMessage as string).assertContain('(code 1555)');
      await closeTestDatabase(db.dbId);
    });

    // insert single-column primary key violation maps to code 1555: the
    // inserted column covers the single pk column of the table
    it('insert_primary_key_constraint_single_column_maps_to_1555', 0, async () => {
      const db = await openFreshDb('db_const_pk_single.db');
      await runDbCall(db, Constant.METHOD_EXECUTE,
        'CREATE TABLE t_p_single (id INTEGER PRIMARY KEY)');
      await runDbCall(db, Constant.METHOD_INSERT,
        'INSERT INTO t_p_single (id) VALUES (?)', [1]);
      const result = await runDbCall(db, Constant.METHOD_INSERT,
        'INSERT INTO t_p_single (id) VALUES (?)', [1]);
      expect(result.errorCalled).assertTrue();
      expect(result.errorCode).assertEqual(Constant.SQLITE_ERROR);
      expect(result.errorMessage as string).assertContain('(code 1555)');
      await closeTestDatabase(db.dbId);
    });

    // Interface: update returns affected row count, 0 when nothing matched
    it('update_returns_affected_rows', 0, async () => {
      const db = await openFreshDb('db_update.db');
      await runDbCall(db, Constant.METHOD_EXECUTE,
        'CREATE TABLE t_upd (id INTEGER PRIMARY KEY, name TEXT)');
      await runDbCall(db, Constant.METHOD_INSERT,
        'INSERT INTO t_upd (id, name) VALUES (?, ?)', [1, 'a']);
      const matched = await runDbCall(db, Constant.METHOD_UPDATE,
        'UPDATE t_upd SET name = ? WHERE id = ?', ['x', 1]);
      expect(matched.successCalled).assertTrue();
      expect(matched.successValue).assertEqual(1);
      const unmatched = await runDbCall(db, Constant.METHOD_UPDATE,
        'UPDATE t_upd SET name = ? WHERE id = ?', ['y', 99]);
      expect(unmatched.successValue).assertEqual(0);
      await closeTestDatabase(db.dbId);
    });

    // Interface: query returns columns and typed rows
    it('query_returns_columns_and_rows', 0, async () => {
      const db = await openFreshDb('db_query.db');
      await runDbCall(db, Constant.METHOD_EXECUTE,
        'CREATE TABLE t_q (id INTEGER PRIMARY KEY, name TEXT)');
      await runDbCall(db, Constant.METHOD_INSERT, 'INSERT INTO t_q (name) VALUES (?)', ['a']);
      await runDbCall(db, Constant.METHOD_INSERT, 'INSERT INTO t_q (name) VALUES (?)', ['b']);
      const result = await runDbCall(db, Constant.METHOD_QUERY,
        'SELECT id, name FROM t_q ORDER BY id');
      expect(result.successCalled).assertTrue();
      const map: Map<string, Object> = result.successValue as Map<string, Object>;
      const columns: string[] = map.get(Constant.PARAM_COLUMNS) as string[];
      expect(columns.length).assertEqual(2);
      expect(columns[0]).assertEqual('id');
      const rows: Object[][] = map.get(Constant.PARAM_ROWS) as Object[][];
      expect(rows.length).assertEqual(2);
      expect(rows[0][0]).assertEqual(1);
      expect(rows[0][1]).assertEqual('a');
      await closeTestDatabase(db.dbId);
    });

    // Zero-row queries still carry columns and rows (platform contract fix)
    it('query_zero_rows_keeps_columns_and_rows_keys', 0, async () => {
      const db = await openFreshDb('db_query_zero.db');
      await runDbCall(db, Constant.METHOD_EXECUTE,
        'CREATE TABLE t_z (id INTEGER PRIMARY KEY, name TEXT)');
      const result = await runDbCall(db, Constant.METHOD_QUERY,
        'SELECT id, name FROM t_z WHERE 1 = 0');
      expect(result.successCalled).assertTrue();
      const map: Map<string, Object> = result.successValue as Map<string, Object>;
      expect(map.has(Constant.PARAM_COLUMNS)).assertTrue();
      expect(map.has(Constant.PARAM_ROWS)).assertTrue();
      expect((map.get(Constant.PARAM_COLUMNS) as string[]).length).assertEqual(2);
      expect((map.get(Constant.PARAM_ROWS) as Object[]).length).assertEqual(0);
      await closeTestDatabase(db.dbId);
    });

    // PRAGMA user_version special-case returns the rdb version
    it('query_user_version_pragma', 0, async () => {
      const db = await openFreshDb('db_version.db');
      const result = await runDbCall(db, Constant.METHOD_QUERY, Constant.SQL_PRAGMA_USER_VERSION);
      expect(result.successCalled).assertTrue();
      const map: Map<string, Object> = result.successValue as Map<string, Object>;
      const columns: string[] = map.get(Constant.PARAM_COLUMNS) as string[];
      expect(columns.length).assertEqual(1);
      expect(columns[0]).assertEqual('user_version');
      const rows: Object[][] = map.get(Constant.PARAM_ROWS) as Object[][];
      expect(rows.length).assertEqual(1);
      expect(rows[0][0]).assertEqual(0);
      await closeTestDatabase(db.dbId);
    });

    // Query on a missing table reports a normalized no-such-table error
    it('query_missing_table_reports_error', 0, async () => {
      const db = await openFreshDb('db_query_missing.db');
      const result = await runDbCall(db, Constant.METHOD_QUERY, 'SELECT * FROM no_such_table');
      expect(result.errorCalled).assertTrue();
      expect(result.errorCode).assertEqual(Constant.SQLITE_ERROR);
      expect(result.errorMessage as string).assertContain('no such table: no_such_table');
      await closeTestDatabase(db.dbId);
    });

    // Reserved word table name maps to a syntax error
    it('query_reserved_table_name_reports_syntax_error', 0, async () => {
      const db = await openFreshDb('db_query_reserved.db');
      const result = await runDbCall(db, Constant.METHOD_QUERY, 'SELECT * FROM order');
      expect(result.errorCalled).assertTrue();
      expect(result.errorCode).assertEqual(Constant.SQLITE_ERROR);
      expect(result.errorMessage as string).assertContain('syntax');
      await closeTestDatabase(db.dbId);
    });

    // Query path VACUUM returns the explicit not-supported error
    it('query_vacuum_reports_not_supported', 0, async () => {
      const db = await openFreshDb('db_query_vacuum.db');
      const result = await runDbCall(db, Constant.METHOD_QUERY, Constant.SQL_VACUUM);
      expect(result.errorCalled).assertTrue();
      expect(result.errorMessage as string).assertContain('not supported');
      await closeTestDatabase(db.dbId);
    });

    // Interface: paged query returns a cursor id, queryCursorNext walks pages
    it('queryCursorNext_walks_pages_to_end', 0, async () => {
      const db = await openFreshDb('db_cursor.db');
      await runDbCall(db, Constant.METHOD_EXECUTE,
        'CREATE TABLE t_c (id INTEGER PRIMARY KEY, v TEXT)');
      for (let i = 1; i <= 5; i++) {
        await runDbCall(db, Constant.METHOD_INSERT,
          'INSERT INTO t_c (id, v) VALUES (?, ?)', [i, 'v' + i]);
      }
      const extra: Map<string, Object | null> = new Map<string, Object | null>();
      extra.set(Constant.PARAM_CURSOR_PAGE_SIZE, 2);
      const first = await runDbCall(db, Constant.METHOD_QUERY,
        'SELECT id FROM t_c ORDER BY id', undefined, extra);
      expect(first.successCalled).assertTrue();
      const firstMap: Map<string, Object> = first.successValue as Map<string, Object>;
      expect((firstMap.get(Constant.PARAM_ROWS) as Object[]).length).assertEqual(2);
      expect(firstMap.has(Constant.PARAM_CURSOR_ID)).assertTrue();
      const cursorId: number = firstMap.get(Constant.PARAM_CURSOR_ID) as number;

      const nextArgs: Map<string, Object> = new Map<string, Object>();
      nextArgs.set(Constant.PARAM_CURSOR_ID, cursorId);
      nextArgs.set(Constant.PARAM_CURSOR_PAGE_SIZE, 2);
      const second = await runDbCall(db, Constant.METHOD_QUERY_CURSOR_NEXT,
        null, undefined, nextArgs);
      expect(second.successCalled).assertTrue();
      const secondMap: Map<string, Object> = second.successValue as Map<string, Object>;
      expect((secondMap.get(Constant.PARAM_ROWS) as Object[][])[0][0]).assertEqual(3);
      expect(secondMap.has(Constant.PARAM_CURSOR_ID)).assertTrue();

      const last = await runDbCall(db, Constant.METHOD_QUERY_CURSOR_NEXT,
        null, undefined, nextArgs);
      const lastMap: Map<string, Object> = last.successValue as Map<string, Object>;
      // Last partial page returns the remaining row 5
      expect((lastMap.get(Constant.PARAM_ROWS) as Object[][]).length).assertEqual(1);
      expect(((lastMap.get(Constant.PARAM_ROWS) as Object[][])[0][0])).assertEqual(5);
      // A partial final page means the cursor is exhausted: no cursorId in
      // the reply and the handle is closed (upstream pagination contract)
      expect(lastMap.has(Constant.PARAM_CURSOR_ID)).assertFalse();
      await closeTestDatabase(db.dbId);
    });

    // First page that cannot be filled (0 rows, or fewer rows than the page
    // size) means the cursor is exhausted after the first read: the reply must
    // not carry a cursorId and no ResultSet may be kept (upstream contract;
    // Android decides with !(isLast() || isAfterLast()))
    it('query_first_page_not_full_returns_no_cursor_id', 0, async () => {
      const db = await openFreshDb('db_cursor_first_partial.db');
      await runDbCall(db, Constant.METHOD_EXECUTE,
        'CREATE TABLE t_cfp (id INTEGER PRIMARY KEY, v TEXT)');
      const extra: Map<string, Object | null> = new Map<string, Object | null>();
      extra.set(Constant.PARAM_CURSOR_PAGE_SIZE, 10);

      // Empty first page: no rows at all
      const empty = await runDbCall(db, Constant.METHOD_QUERY,
        'SELECT id FROM t_cfp ORDER BY id', undefined, extra);
      expect(empty.successCalled).assertTrue();
      const emptyMap: Map<string, Object> = empty.successValue as Map<string, Object>;
      expect((emptyMap.get(Constant.PARAM_ROWS) as Object[]).length).assertEqual(0);
      expect(emptyMap.has(Constant.PARAM_CURSOR_ID)).assertFalse();

      // Partial first page: 3 rows for a page size of 10
      for (let i = 1; i <= 3; i++) {
        await runDbCall(db, Constant.METHOD_INSERT,
          'INSERT INTO t_cfp (id, v) VALUES (?, ?)', [i, 'v' + i]);
      }
      const partial = await runDbCall(db, Constant.METHOD_QUERY,
        'SELECT id FROM t_cfp ORDER BY id', undefined, extra);
      expect(partial.successCalled).assertTrue();
      const partialMap: Map<string, Object> = partial.successValue as Map<string, Object>;
      expect((partialMap.get(Constant.PARAM_ROWS) as Object[]).length).assertEqual(3);
      expect(partialMap.has(Constant.PARAM_CURSOR_ID)).assertFalse();
      await closeTestDatabase(db.dbId);
    });

    // A first page filled exactly to the page size while sitting on the last
    // row is exhausted too: the cursor stops on the last row with nothing
    // left to move to, matching Android's immediate close on exact multiples
    it('query_first_page_exact_multiple_returns_no_cursor_id', 0, async () => {
      const db = await openFreshDb('db_cursor_first_exact.db');
      await runDbCall(db, Constant.METHOD_EXECUTE,
        'CREATE TABLE t_cfe (id INTEGER PRIMARY KEY, v TEXT)');
      for (let i = 1; i <= 2; i++) {
        await runDbCall(db, Constant.METHOD_INSERT,
          'INSERT INTO t_cfe (id, v) VALUES (?, ?)', [i, 'v' + i]);
      }
      const extra: Map<string, Object | null> = new Map<string, Object | null>();
      extra.set(Constant.PARAM_CURSOR_PAGE_SIZE, 2);
      const first = await runDbCall(db, Constant.METHOD_QUERY,
        'SELECT id FROM t_cfe ORDER BY id', undefined, extra);
      expect(first.successCalled).assertTrue();
      const firstMap: Map<string, Object> = first.successValue as Map<string, Object>;
      expect((firstMap.get(Constant.PARAM_ROWS) as Object[]).length).assertEqual(2);
      expect(firstMap.has(Constant.PARAM_CURSOR_ID)).assertFalse();
      await closeTestDatabase(db.dbId);
    });

    // queryCursorNext cancel closes the cursor; later use reports not found
    it('queryCursorNext_cancel_closes_cursor', 0, async () => {
      const db = await openFreshDb('db_cursor_cancel.db');
      await runDbCall(db, Constant.METHOD_EXECUTE,
        'CREATE TABLE t_cc (id INTEGER PRIMARY KEY, v TEXT)');
      for (let i = 1; i <= 4; i++) {
        await runDbCall(db, Constant.METHOD_INSERT,
          'INSERT INTO t_cc (id, v) VALUES (?, ?)', [i, 'v' + i]);
      }
      const extra: Map<string, Object | null> = new Map<string, Object | null>();
      extra.set(Constant.PARAM_CURSOR_PAGE_SIZE, 2);
      const first = await runDbCall(db, Constant.METHOD_QUERY,
        'SELECT id FROM t_cc ORDER BY id', undefined, extra);
      const cursorId: number =
        (first.successValue as Map<string, Object>).get(Constant.PARAM_CURSOR_ID) as number;

      const cancelArgs: Map<string, Object> = new Map<string, Object>();
      cancelArgs.set(Constant.PARAM_CURSOR_ID, cursorId);
      cancelArgs.set(Constant.PARAM_CANCEL, true);
      const cancel = await runDbCall(db, Constant.METHOD_QUERY_CURSOR_NEXT,
        null, undefined, cancelArgs);
      expect(cancel.successCalled).assertTrue();
      expect(cancel.successValue).assertNull();

      // The cancelled cursor is gone: a plain next (no cancel flag) reports not found
      const unknownArgs: Map<string, Object> = new Map<string, Object>();
      unknownArgs.set(Constant.PARAM_CURSOR_ID, cursorId);
      unknownArgs.set(Constant.PARAM_CURSOR_PAGE_SIZE, 2);
      const unknown = await runDbCall(db, Constant.METHOD_QUERY_CURSOR_NEXT,
        null, undefined, unknownArgs);
      expect(unknown.errorCalled).assertTrue();
      expect(unknown.errorMessage as string).assertContain('Cursor not found');
      await closeTestDatabase(db.dbId);
    });

    // Interface: Database keeps the constructor metadata fields (public
    // constructor of the data holder class)
    it('databaseConstructor_keeps_fields', 0, async () => {
      const database: Database = new Database(getTestContext(), 'ctor_path.db', 7, false, 3);
      expect(database.path).assertEqual('ctor_path.db');
      expect(database.id).assertEqual(7);
      expect(database.singleInstance).assertFalse();
      expect(database.logLevel).assertEqual(3);
    });

    // A query for an INTEGER beyond Number.MAX_SAFE_INTEGER returns the raw
    // bigint value (cursorValue big-integer branch)
    it('query_big_integer_returns_bigint', 0, async () => {
      const db = await openFreshDb('db_query_bigint.db');
      await runDbCall(db, Constant.METHOD_EXECUTE, 'CREATE TABLE t_big (v INTEGER)');
      await runDbCall(db, Constant.METHOD_EXECUTE, 'INSERT INTO t_big (v) VALUES (9007199254740993)');
      const result = await runDbCall(db, Constant.METHOD_QUERY, 'SELECT v FROM t_big');
      expect(result.successCalled).assertTrue();
      const map: Map<string, Object> = result.successValue as Map<string, Object>;
      const rows: Object[][] = map.get(Constant.PARAM_ROWS) as Object[][];
      expect(rows.length).assertEqual(1);
      expect(`${rows[0][0]}`).assertEqual('9007199254740993');
      await closeTestDatabase(db.dbId);
    });

    // An empty sql string makes querySql throw; doQuery reports the error via
    // the exception path instead of an empty result set
    it('query_empty_sql_reports_error', 0, async () => {
      const db = await openFreshDb('db_query_empty.db');
      const result = await runDbCall(db, Constant.METHOD_QUERY, '');
      expect(result.errorCalled).assertTrue();
      expect(result.errorCode).assertEqual(Constant.SQLITE_ERROR);
      await closeTestDatabase(db.dbId);
    });

    // A read-only store rejects writes; the error surfaces as sqlite_error
    // with a readonly hint (801 readonly mapping or the generic branch)
    it('execute_on_readonly_database_reports_error', 0, async () => {
      removeDbFiles('db_readonly.db');
      // Create the database writable first: a read-only getRdbStore cannot
      // create a missing file, so the read-only open needs an existing file
      const writable: FreshDb = await openFreshDb('db_readonly.db');
      await runDbCall(writable, Constant.METHOD_EXECUTE, 'CREATE TABLE t_ro (v TEXT)');
      await closeTestDatabase(writable.dbId);
      const args: Map<string, Object> = new Map<string, Object>();
      args.set(Constant.PARAM_PATH, dbPathFor('db_readonly.db'));
      args.set(Constant.PARAM_READ_ONLY, true);
      const openResult: TestResult = new TestResult();
      await DatabaseHelper.openDatabase(getTestContext(),
        makeCall(Constant.METHOD_OPEN_DATABASE, args), openResult);
      expect(openResult.successCalled).assertTrue();
      const openMap: Record<string, Object> = openResult.successValue as Record<string, Object>;
      const dbId: number = openMap['id'] as number;
      const db: FreshDb = new FreshDb();
      db.dbId = dbId;
      const storeArgs: Map<string, Object> = new Map<string, Object>();
      storeArgs.set(Constant.PARAM_ID, dbId);
      db.store = DatabaseHelper.getDatabaseOrError(makeCall('execute', storeArgs), new TestResult());
      expect(db.store !== null).assertTrue();
      const result = await runDbCall(db, Constant.METHOD_EXECUTE,
        'CREATE TABLE t_ro_blocked (v TEXT)');
      expect(result.errorCalled).assertTrue();
      expect(result.errorCode).assertEqual(Constant.SQLITE_ERROR);
      expect(result.errorMessage !== null && result.errorMessage !== undefined).assertTrue();
      await closeTestDatabase(dbId);
      removeDbFiles('db_readonly.db');
    });

    // Interface: batch runs mixed operations and returns per-op results
    it('batch_mixed_operations_success', 0, async () => {
      const db = await openFreshDb('db_batch.db');
      const operations: Map<string, Object>[] = [
        makeOp(Constant.METHOD_EXECUTE, 'CREATE TABLE t_b (id INTEGER PRIMARY KEY, v TEXT)'),
        makeOp(Constant.METHOD_INSERT, 'INSERT INTO t_b (v) VALUES (?)', ['a']),
        makeOp(Constant.METHOD_QUERY, 'SELECT COUNT(*) AS c FROM t_b'),
        makeOp(Constant.METHOD_UPDATE, 'UPDATE t_b SET v = ? WHERE id = ?', ['z', 1])
      ];
      const result = await runBatch(db, operations, false, false);
      expect(result.successCalled).assertTrue();
      const results: Object[] = result.successValue as Object[];
      expect(results.length).assertEqual(4);
      const insertEntry: Map<string, Object> = results[1] as Map<string, Object>;
      expect(insertEntry.get(Constant.PARAM_RESULT)).assertEqual(1);
      const queryEntry: Map<string, Object> = results[2] as Map<string, Object>;
      const queryResult: Map<string, Object> = queryEntry.get(Constant.PARAM_RESULT) as Map<string, Object>;
      expect(queryResult.has(Constant.PARAM_COLUMNS)).assertTrue();
      const updateEntry: Map<string, Object> = results[3] as Map<string, Object>;
      expect(updateEntry.get(Constant.PARAM_RESULT)).assertEqual(1);
      await closeTestDatabase(db.dbId);
    });

    // batch stops at the first failing operation without continueOnError
    it('batch_error_without_continue_stops', 0, async () => {
      const db = await openFreshDb('db_batch_err.db');
      await runDbCall(db, Constant.METHOD_EXECUTE, 'CREATE TABLE t_be (v TEXT)');
      const operations: Map<string, Object>[] = [
        makeOp(Constant.METHOD_INSERT, 'INSERT INTO t_be (v) VALUES (?)', ['a']),
        makeOp(Constant.METHOD_INSERT, 'INSERT INTO missing_bt (v) VALUES (?)', ['b'])
      ];
      const result = await runBatch(db, operations, false, false);
      expect(result.errorCalled).assertTrue();
      expect(result.errorCode).assertEqual(Constant.SQLITE_ERROR);
      await closeTestDatabase(db.dbId);
    });

    // batch with continueOnError collects per-op error entries
    it('batch_error_with_continue_collects_errors', 0, async () => {
      const db = await openFreshDb('db_batch_cont.db');
      await runDbCall(db, Constant.METHOD_EXECUTE, 'CREATE TABLE t_bc (v TEXT)');
      const operations: Map<string, Object>[] = [
        makeOp(Constant.METHOD_INSERT, 'INSERT INTO missing_bt2 (v) VALUES (?)', ['b']),
        makeOp(Constant.METHOD_INSERT, 'INSERT INTO t_bc (v) VALUES (?)', ['a'])
      ];
      const result = await runBatch(db, operations, false, true);
      expect(result.successCalled).assertTrue();
      const results: Object[] = result.successValue as Object[];
      expect(results.length).assertEqual(2);
      const errorEntry: Map<string, Object> = results[0] as Map<string, Object>;
      const errorDetail: Map<string, Object> = errorEntry.get(Constant.PARAM_ERROR) as Map<string, Object>;
      expect(errorDetail.get(Constant.PARAM_ERROR_CODE)).assertEqual(Constant.SQLITE_ERROR);
      const okEntry: Map<string, Object> = results[1] as Map<string, Object>;
      expect(okEntry.get(Constant.PARAM_RESULT)).assertEqual(1);
      await closeTestDatabase(db.dbId);
    });

    // batch with an unknown operation method reports bad_param
    it('batch_unknown_method_reports_bad_param', 0, async () => {
      const db = await openFreshDb('db_batch_bad.db');
      const operations: Map<string, Object>[] = [makeOp('bogus', 'SELECT 1')];
      const result = await runBatch(db, operations, false, false);
      expect(result.errorCalled).assertTrue();
      expect(result.errorCode).assertEqual(Constant.ERROR_BAD_PARAM);
      expect(result.errorMessage as string).assertContain('Batch method');
      await closeTestDatabase(db.dbId);
    });

    // batch with a non-list operations value reports bad_param
    it('batch_operations_not_list_reports_bad_param', 0, async () => {
      const db = await openFreshDb('db_batch_notlist.db');
      const result = await runBatch(db, 'not-a-list', false, false);
      expect(result.errorCalled).assertTrue();
      expect(result.errorCode).assertEqual(Constant.ERROR_BAD_PARAM);
      expect(result.errorMessage as string).assertContain('must be a list');
      await closeTestDatabase(db.dbId);
    });

    // batch honors noResult (single null reply)
    it('batch_no_result_returns_null', 0, async () => {
      const db = await openFreshDb('db_batch_nores.db');
      const operations: Map<string, Object>[] = [
        makeOp(Constant.METHOD_EXECUTE, 'CREATE TABLE t_bn (v TEXT)'),
        makeOp(Constant.METHOD_INSERT, 'INSERT INTO t_bn (v) VALUES (?)', ['a'])
      ];
      const result = await runBatch(db, operations, true, false);
      expect(result.successCalled).assertTrue();
      expect(result.successValue).assertNull();
      await closeTestDatabase(db.dbId);
    });

    // batch operation without a sql field reports the precise missing-sql error
    it('batch_missing_sql_reports_missing_field', 0, async () => {
      const db = await openFreshDb('db_batch_nosql.db');
      const operations: Map<string, Object>[] = [makeOp(Constant.METHOD_EXECUTE, null)];
      const result = await runBatch(db, operations, false, false);
      expect(result.errorCalled).assertTrue();
      expect(result.errorCode).assertEqual(Constant.SQLITE_ERROR);
      expect(result.errorMessage as string).assertContain('missing sql field');
      await closeTestDatabase(db.dbId);
    });

    // A second BEGIN IMMEDIATE inside an active transaction is a silent no-op
    // success on this RDB engine (beginTransaction nests internally); the
    // handler catch is only reachable through fault injection
    it('execute_nested_begin_immediate_succeeds_as_noop', 0, async () => {
      const db = await openFreshDb('db_begin_nested.db');
      const extra: Map<string, Object | null> = new Map<string, Object | null>();
      extra.set(Constant.PARAM_IN_TRANSACTION_CHANGE, true);
      extra.set(Constant.PARAM_TRANSACTION_ID, null);
      const first = await runDbCall(db, Constant.METHOD_EXECUTE,
        Constant.SQL_BEGIN_IMMEDIATE, undefined, extra);
      expect(first.successCalled).assertTrue();
      const second = await runDbCall(db, Constant.METHOD_EXECUTE,
        Constant.SQL_BEGIN_IMMEDIATE, undefined, extra);
      expect(second.successCalled).assertTrue();
      // Each entering BEGIN returns a fresh transaction id map, even when the
      // engine silently nests the second begin
      const firstMap: Map<string, Object> = first.successValue as Map<string, Object>;
      const secondMap: Map<string, Object> = second.successValue as Map<string, Object>;
      const firstTxnId: number = firstMap.get(Constant.PARAM_TRANSACTION_ID) as number;
      const secondTxnId: number = secondMap.get(Constant.PARAM_TRANSACTION_ID) as number;
      expect(secondTxnId).assertEqual(firstTxnId + 1);
      // Leave the transaction(s) so cleanup stays balanced; results are not
      // asserted (the second rollback may fail once the stack is unwound)
      const extraLeave: Map<string, Object | null> = new Map<string, Object | null>();
      extraLeave.set(Constant.PARAM_IN_TRANSACTION_CHANGE, false);
      await runDbCall(db, Constant.METHOD_EXECUTE, Constant.SQL_ROLLBACK, undefined, extraLeave);
      await runDbCall(db, Constant.METHOD_EXECUTE, Constant.SQL_ROLLBACK, undefined, extraLeave);
      await closeTestDatabase(db.dbId);
    });

    // COMMIT without an open transaction is a silent no-op success on this
    // RDB engine; the handler catch is only reachable through fault injection
    it('execute_commit_without_transaction_succeeds_as_noop', 0, async () => {
      const db = await openFreshDb('db_commit_bare.db');
      const result = await runDbCall(db, Constant.METHOD_EXECUTE, Constant.SQL_COMMIT);
      expect(result.successCalled).assertTrue();
      expect(result.successValue).assertNull();
      await closeTestDatabase(db.dbId);
    });

    // ROLLBACK without an open transaction makes db.rollBack() throw; the
    // handler reports 'rollback failed' instead of masking the failure
    it('execute_rollback_without_transaction_reports_error', 0, async () => {
      const db = await openFreshDb('db_rollback_bare.db');
      const result = await runDbCall(db, Constant.METHOD_EXECUTE, Constant.SQL_ROLLBACK);
      expect(result.errorCalled).assertTrue();
      expect(result.errorCode).assertEqual(Constant.SQLITE_ERROR);
      expect(result.errorMessage as string).assertContain('rollback failed');
      await closeTestDatabase(db.dbId);
    });

    // VACUUM inside an open transaction is rejected by the engine; the vacuum
    // handler must surface an error (either the explicit not-supported message
    // or the raw engine error), never a silent success
    it('execute_vacuum_in_transaction_reports_error', 0, async () => {
      const db = await openFreshDb('db_vacuum_txn.db');
      const extra: Map<string, Object | null> = new Map<string, Object | null>();
      extra.set(Constant.PARAM_IN_TRANSACTION_CHANGE, true);
      extra.set(Constant.PARAM_TRANSACTION_ID, null);
      await runDbCall(db, Constant.METHOD_EXECUTE,
        Constant.SQL_BEGIN_IMMEDIATE, undefined, extra);
      const result = await runDbCall(db, Constant.METHOD_EXECUTE, Constant.SQL_VACUUM);
      expect(result.errorCalled).assertTrue();
      expect(result.errorCode).assertEqual(Constant.SQLITE_ERROR);
      expect(result.errorMessage as string).assertContain('VACUUM');
      const extraLeave: Map<string, Object | null> = new Map<string, Object | null>();
      extraLeave.set(Constant.PARAM_IN_TRANSACTION_CHANGE, false);
      await runDbCall(db, Constant.METHOD_EXECUTE, Constant.SQL_ROLLBACK, undefined, extraLeave);
      await closeTestDatabase(db.dbId);
    });

    // ATTACH with a literal path but a '?' schema placeholder and no
    // arguments reports the precise missing-arguments error (schema side)
    it('execute_attach_schema_placeholder_missing_arguments_error', 0, async () => {
      const db = await openFreshDb('db_attach_schema_ph.db');
      const attach = await runDbCall(db, Constant.METHOD_EXECUTE,
        'ATTACH DATABASE \'' + moduleDbPathFor('db_attach_unused.db') + '\' AS ?');
      expect(attach.errorCalled).assertTrue();
      expect(attach.errorCode).assertEqual(Constant.SQLITE_ERROR);
      expect(attach.errorMessage as string).assertContain('attach: missing sql arguments');
      await closeTestDatabase(db.dbId);
    });

    // ATTACH of a non-sqlite file fails inside db.attach; the handler reports
    // 'attach failed' with the engine error instead of crashing
    it('execute_attach_invalid_file_reports_error', 0, async () => {
      removeDbFiles('db_attach_junk.db');
      const junk = fs.openSync(moduleDbPathFor('db_attach_junk.db'),
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
      fs.writeSync(junk.fd, 'definitely not a sqlite database');
      fs.closeSync(junk);
      const db = await openFreshDb('db_attach_bad.db');
      const attach = await runDbCall(db, Constant.METHOD_EXECUTE,
        'ATTACH DATABASE \'' + moduleDbPathFor('db_attach_junk.db') + '\' AS junk_schema');
      expect(attach.errorCalled).assertTrue();
      expect(attach.errorCode).assertEqual(Constant.SQLITE_ERROR);
      expect(attach.errorMessage as string).assertContain('attach failed');
      removeDbFiles('db_attach_junk.db');
      await closeTestDatabase(db.dbId);
    });

    // DETACH of a schema that was never attached is a silent no-op success on
    // this RDB engine; the handler catch is only reachable through fault
    // injection
    it('execute_detach_unknown_schema_succeeds_as_noop', 0, async () => {
      const db = await openFreshDb('db_detach_unknown.db');
      const detach = await runDbCall(db, Constant.METHOD_EXECUTE,
        'DETACH DATABASE schema_never_attached');
      expect(detach.successCalled).assertTrue();
      expect(detach.successValue).assertNull();
      await closeTestDatabase(db.dbId);
    });

    // execute with a DML statement without bind arguments uses the
    // no-arguments execute path (db.execute(sql))
    it('execute_dml_without_arguments_success', 0, async () => {
      const db = await openFreshDb('db_exec_noargs.db');
      await runDbCall(db, Constant.METHOD_EXECUTE,
        'CREATE TABLE t_noargs (id INTEGER PRIMARY KEY, name TEXT)');
      await runDbCall(db, Constant.METHOD_INSERT,
        'INSERT INTO t_noargs (name) VALUES (?)', ['a']);
      const result = await runDbCall(db, Constant.METHOD_EXECUTE,
        'UPDATE t_noargs SET name = \'bulk\'');
      expect(result.successCalled).assertTrue();
      expect(result.successValue).assertNull();
      const query = await runDbCall(db, Constant.METHOD_QUERY,
        'SELECT name FROM t_noargs WHERE id = 1');
      const queryMap: Map<string, Object> = query.successValue as Map<string, Object>;
      expect(((queryMap.get(Constant.PARAM_ROWS) as Object[][])[0][0])).assertEqual('bulk');
      await closeTestDatabase(db.dbId);
    });

    // update against a missing table reports the engine error (doUpdate
    // failure path), not a silent success
    it('update_missing_table_reports_error', 0, async () => {
      const db = await openFreshDb('db_update_missing.db');
      const result = await runDbCall(db, Constant.METHOD_UPDATE,
        'UPDATE missing_upd SET v = ?', [1]);
      expect(result.errorCalled).assertTrue();
      expect(result.errorCode).assertEqual(Constant.SQLITE_ERROR);
      await closeTestDatabase(db.dbId);
    });

    // update honors noResult: the final reply is null even though rows were
    // affected (the intermediate row count is overwritten)
    it('update_no_result_returns_null', 0, async () => {
      const db = await openFreshDb('db_update_nores.db');
      await runDbCall(db, Constant.METHOD_EXECUTE,
        'CREATE TABLE t_unr (id INTEGER PRIMARY KEY, name TEXT)');
      await runDbCall(db, Constant.METHOD_INSERT,
        'INSERT INTO t_unr (name) VALUES (?)', ['a']);
      const extra: Map<string, Object | null> = new Map<string, Object | null>();
      extra.set(Constant.PARAM_NO_RESULT, true);
      const result = await runDbCall(db, Constant.METHOD_UPDATE,
        'UPDATE t_unr SET name = ? WHERE id = ?', ['x', 1], extra);
      expect(result.successCalled).assertTrue();
      expect(result.successValue).assertNull();
      await closeTestDatabase(db.dbId);
    });

    // query without bind arguments uses the no-arguments querySql path
    it('query_without_arguments_success', 0, async () => {
      const db = await openFreshDb('db_query_noargs.db');
      await runDbCall(db, Constant.METHOD_EXECUTE,
        'CREATE TABLE t_qna (id INTEGER PRIMARY KEY, name TEXT)');
      await runDbCall(db, Constant.METHOD_INSERT,
        'INSERT INTO t_qna (name) VALUES (?)', ['a']);
      const result = await runDbCall(db, Constant.METHOD_QUERY,
        'SELECT id, name FROM t_qna ORDER BY id');
      expect(result.successCalled).assertTrue();
      const map: Map<string, Object> = result.successValue as Map<string, Object>;
      expect((map.get(Constant.PARAM_ROWS) as Object[]).length).assertEqual(1);
      await closeTestDatabase(db.dbId);
    });

    // A PRAGMA query that RDB rejects with an empty result set and that has no
    // FROM clause is classified as a syntax error by the empty-result handler
    it('query_pragma_without_from_reports_syntax_error', 0, async () => {
      const db = await openFreshDb('db_query_pragma.db');
      const result = await runDbCall(db, Constant.METHOD_QUERY, 'PRAGMA journal_mode');
      expect(result.errorCalled).assertTrue();
      expect(result.errorCode).assertEqual(Constant.SQLITE_ERROR);
      expect(result.errorMessage as string).assertContain('syntax error');
      await closeTestDatabase(db.dbId);
    });

    // Reaching MAX_OPEN_CURSORS (64) evicts the oldest cursor: the very first
    // cursor id is closed by the eviction and later use reports not found,
    // while the newest call still succeeds
    it('queryCursorMany_evicts_oldest_cursor_at_capacity', 0, async () => {
      const db = await openFreshDb('db_cursor_evict.db');
      await runDbCall(db, Constant.METHOD_EXECUTE,
        'CREATE TABLE t_ev (id INTEGER PRIMARY KEY, v TEXT)');
      for (let i = 1; i <= 3; i++) {
        await runDbCall(db, Constant.METHOD_INSERT,
          'INSERT INTO t_ev (id, v) VALUES (?, ?)', [i, 'v' + i]);
      }
      const extra: Map<string, Object | null> = new Map<string, Object | null>();
      extra.set(Constant.PARAM_CURSOR_PAGE_SIZE, 1);
      let firstCursorId: number = -1;
      let lastOk: TestResult = new TestResult();
      for (let round = 0; round < 65; round++) {
        lastOk = await runDbCall(db, Constant.METHOD_QUERY,
          'SELECT id FROM t_ev ORDER BY id', undefined, extra);
        if (round === 0) {
          firstCursorId =
            (lastOk.successValue as Map<string, Object>).get(Constant.PARAM_CURSOR_ID) as number;
        }
      }
      // The 65th query still succeeds past the 64-cursor capacity
      expect(lastOk.successCalled).assertTrue();
      // The oldest cursor was evicted: using it reports not found
      const evictedArgs: Map<string, Object> = new Map<string, Object>();
      evictedArgs.set(Constant.PARAM_CURSOR_ID, firstCursorId);
      evictedArgs.set(Constant.PARAM_CURSOR_PAGE_SIZE, 1);
      const evicted = await runDbCall(db, Constant.METHOD_QUERY_CURSOR_NEXT,
        null, undefined, evictedArgs);
      expect(evicted.errorCalled).assertTrue();
      expect(evicted.errorMessage as string).assertContain('Cursor not found');
      await closeTestDatabase(db.dbId);
    });

    // Closing a database recycles its unconsumed paging cursors: a cursor
    // left open is gone right after closeDatabase
    it('close_database_recycles_open_cursors', 0, async () => {
      const db = await openFreshDb('db_cursor_close.db');
      await runDbCall(db, Constant.METHOD_EXECUTE,
        'CREATE TABLE t_cl (id INTEGER PRIMARY KEY, v TEXT)');
      for (let i = 1; i <= 3; i++) {
        await runDbCall(db, Constant.METHOD_INSERT,
          'INSERT INTO t_cl (id, v) VALUES (?, ?)', [i, 'v' + i]);
      }
      const extra: Map<string, Object | null> = new Map<string, Object | null>();
      extra.set(Constant.PARAM_CURSOR_PAGE_SIZE, 1);
      const first = await runDbCall(db, Constant.METHOD_QUERY,
        'SELECT id FROM t_cl ORDER BY id', undefined, extra);
      const cursorId: number =
        (first.successValue as Map<string, Object>).get(Constant.PARAM_CURSOR_ID) as number;
      await closeTestDatabase(db.dbId);
      const nextArgs: Map<string, Object> = new Map<string, Object>();
      nextArgs.set(Constant.PARAM_CURSOR_ID, cursorId);
      nextArgs.set(Constant.PARAM_CURSOR_PAGE_SIZE, 1);
      const afterClose = await runDbCall(db, Constant.METHOD_QUERY_CURSOR_NEXT,
        null, undefined, nextArgs);
      expect(afterClose.errorCalled).assertTrue();
      expect(afterClose.errorMessage as string).assertContain('Cursor not found');
    });

    // batch: a failing execute operation without continueOnError stops the
    // batch with the engine error
    it('batch_execute_error_without_continue_stops', 0, async () => {
      const db = await openFreshDb('db_batch_exec_err.db');
      const operations: Map<string, Object>[] =
        [makeOp(Constant.METHOD_EXECUTE, 'INSERT INTO missing_bt_e (v) VALUES (1)')];
      const result = await runBatch(db, operations, false, false);
      expect(result.errorCalled).assertTrue();
      expect(result.errorCode).assertEqual(Constant.SQLITE_ERROR);
      await closeTestDatabase(db.dbId);
    });

    // batch: a failing query operation without continueOnError stops the batch
    it('batch_query_error_without_continue_stops', 0, async () => {
      const db = await openFreshDb('db_batch_query_err.db');
      const operations: Map<string, Object>[] =
        [makeOp(Constant.METHOD_QUERY, 'SELECT * FROM missing_bt_q')];
      const result = await runBatch(db, operations, false, false);
      expect(result.errorCalled).assertTrue();
      expect(result.errorMessage as string).assertContain('missing_bt_q');
      await closeTestDatabase(db.dbId);
    });

    // batch: a failing update operation without continueOnError stops the batch
    it('batch_update_error_without_continue_stops', 0, async () => {
      const db = await openFreshDb('db_batch_update_err.db');
      const operations: Map<string, Object>[] =
        [makeOp(Constant.METHOD_UPDATE, 'UPDATE missing_bt_u SET v = 1')];
      const result = await runBatch(db, operations, false, false);
      expect(result.errorCalled).assertTrue();
      expect(result.errorCode).assertEqual(Constant.SQLITE_ERROR);
      await closeTestDatabase(db.dbId);
    });

    // batch with continueOnError collects an error entry for every failing
    // method kind (execute / query / update) in one pass
    it('batch_method_errors_with_continue_collect_all', 0, async () => {
      const db = await openFreshDb('db_batch_all_err.db');
      const operations: Map<string, Object>[] = [
        makeOp(Constant.METHOD_EXECUTE, 'INSERT INTO missing_bt3 (v) VALUES (1)'),
        makeOp(Constant.METHOD_QUERY, 'SELECT * FROM missing_bt3'),
        makeOp(Constant.METHOD_UPDATE, 'UPDATE missing_bt3 SET v = 1')
      ];
      const result = await runBatch(db, operations, false, true);
      expect(result.successCalled).assertTrue();
      const results: Object[] = result.successValue as Object[];
      expect(results.length).assertEqual(3);
      for (const entry of results) {
        const entryMap: Map<string, Object> = entry as Map<string, Object>;
        expect(entryMap.has(Constant.PARAM_ERROR)).assertTrue();
      }
      await closeTestDatabase(db.dbId);
    });

    // batch with noResult=true omits every per-op row (handleSuccess and
    // handleErrorContinue both skip the push) and replies with a bare null
    it('batch_no_result_ops_omit_rows', 0, async () => {
      const db = await openFreshDb('db_batch_noresult.db');
      await runDbCall(db, Constant.METHOD_EXECUTE, 'CREATE TABLE t_bn (v TEXT)');
      const operations: Map<string, Object>[] = [
        makeOp(Constant.METHOD_INSERT, 'INSERT INTO t_bn (v) VALUES (?)', ['kept']),
        makeOp(Constant.METHOD_INSERT, 'INSERT INTO missing_bn (v) VALUES (1)')
      ];
      const result = await runBatch(db, operations, true, true);
      expect(result.successCalled).assertTrue();
      expect(result.successValue).assertNull();
      await closeTestDatabase(db.dbId);
    });

    // dispose with a paging cursor left open recycles it via closeAllCursors
    // and clears every static map (kept last: dispose wipes all databases)
    it('dispose_recycles_open_cursors', 0, async () => {
      const db = await openFreshDb('db_cursor_dispose.db');
      await runDbCall(db, Constant.METHOD_EXECUTE,
        'CREATE TABLE t_cd (id INTEGER PRIMARY KEY, v TEXT)');
      for (let i = 1; i <= 3; i++) {
        await runDbCall(db, Constant.METHOD_INSERT,
          'INSERT INTO t_cd (id, v) VALUES (?, ?)', [i, 'v' + i]);
      }
      const extra: Map<string, Object | null> = new Map<string, Object | null>();
      extra.set(Constant.PARAM_CURSOR_PAGE_SIZE, 1);
      const first = await runDbCall(db, Constant.METHOD_QUERY,
        'SELECT id FROM t_cd ORDER BY id', undefined, extra);
      const cursorId: number =
        (first.successValue as Map<string, Object>).get(Constant.PARAM_CURSOR_ID) as number;
      await DatabaseHelper.dispose();
      expect(DatabaseHelper.dbMap.size).assertEqual(0);
      const nextArgs: Map<string, Object> = new Map<string, Object>();
      nextArgs.set(Constant.PARAM_CURSOR_ID, cursorId);
      nextArgs.set(Constant.PARAM_CURSOR_PAGE_SIZE, 1);
      const afterDispose = await runDbCall(db, Constant.METHOD_QUERY_CURSOR_NEXT,
        null, undefined, nextArgs);
      expect(afterDispose.errorCalled).assertTrue();
      expect(afterDispose.errorMessage as string).assertContain('Cursor not found');
    });
  });
}
