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

import { Operation } from './operation/Operation';
import { relationalStore } from '@kit.ArkData';
import { Tools } from './Tools';
import { BusinessError } from '@kit.BasicServicesKit';
import { Constant } from './Constant';
import { SqlErrorInfo } from './operation/SqlErrorInfo';

/**
 * 每个 Handler 都要实现 match + execute
 */
export interface ISqlHandler {
  /**
   * 如果能处理此 SQL，就返回 true
   * @param sql SQL 语句
   * @returns true 表示能处理此 SQL，false 表示不能处理
   */
  match(sql: string): boolean;

  /**
   * 执行逻辑，返回是否执行成功
   * @param sql SQL 语句
   * @param operation 操作对象
   * @param db 数据库实例
   * @returns 执行成功返回 true，失败返回 false
   */
  execute( sql: string, operation: Operation, db: relationalStore.RdbStore): Promise<boolean> | boolean;

  /**
   * 默认 false，表示不走后处理；某些 Handler 可以覆盖为 true
   * @returns 是否需要后处理
   */
  get needsPostProcess(): boolean;
}

/**
 * 抽象 Handler，提供默认 no-op 实现
 */
abstract class BaseSqlHandler implements ISqlHandler {
  match(sql: string): boolean {
    return false;
  }

  execute(sql: string, operation: Operation, db: relationalStore.RdbStore): Promise<boolean> | boolean {
    return false;
  }

  get needsPostProcess(): boolean {
    return false;
  }
}

/**
 * 事务开始
 */
export class BeginImmediateHandler extends BaseSqlHandler {
  match(sql: string) {
    const upperSql = sql.toUpperCase();
    return upperSql === Constant.SQL_BEGIN_IMMEDIATE || 
           upperSql === Constant.SQL_BEGIN_IMMEDIATE + ' TRANSACTION';
  }

  execute(_sql: string, operation: Operation, db: relationalStore.RdbStore): boolean {
    try {
      db.beginTransaction();
      return true;
    } catch (err) {
      // 开启事务失败如实上报 sqlite_error，避免沿 worker 顶层兜底退化为通用 'error' 信封
      const error = err as BusinessError;
      operation.error(Constant.SQLITE_ERROR,
        `begin immediate failed, error code: ${error.code}. message is ${error.message}`,
        SqlErrorInfo.getMap(operation));
      return false;
    }
  }

  get needsPostProcess(): boolean {
    return true;
  }
}

/**
 * 提交事务
 */
export class CommitHandler extends BaseSqlHandler {
  match(sql: string) {
    return sql.toUpperCase() === Constant.SQL_COMMIT;
  }

  execute(sql: string, operation: Operation, db: relationalStore.RdbStore) {
    try {
      db.commit();
      return true;
    } catch (err) {
      // 提交失败如实上报 sqlite_error（与 RollbackHandler 防护标准一致）
      const error = err as BusinessError;
      operation.error(Constant.SQLITE_ERROR,
        `commit failed, error code: ${error.code}. message is ${error.message}`,
        SqlErrorInfo.getMap(operation));
      return false;
    }
  }

  get needsPostProcess(): boolean {
    return true;
  }
}

/**
 * 回滚事务
 */
export class RollbackHandler extends BaseSqlHandler {
  match(sql: string) {
    return sql.toUpperCase() === Constant.SQL_ROLLBACK;
  }

  execute(sql: string, operation: Operation, db: relationalStore.RdbStore) {
    try {
      db.rollBack();
      return true;
    } catch (err) {
      // 回滚失败上报错误而非静默成功，避免掩盖真实失败（与 attach/detach 错误格式一致）
      const error = err as BusinessError;
      operation.error(Constant.SQLITE_ERROR,
        `rollback failed, error code: ${error.code}. message is ${error.message}`,
        SqlErrorInfo.getMap(operation));
      return false;
    }
  }

  get needsPostProcess(): boolean {
    return true;
  }
}

/**
 * BEGIN EXCLUSIVE
 */
export class BeginExclusiveHandler extends BaseSqlHandler {
  match(sql: string) {
    const upperSql = sql.toUpperCase();
    return upperSql === Constant.SQL_BEGIN_EXCLUSIVE ||
           upperSql === Constant.SQL_BEGIN_EXCLUSIVE + ' TRANSACTION';
  }
  execute(_sql: string, operation: Operation, _db: relationalStore.RdbStore) {
    return true;
  }
  get needsPostProcess(): boolean {
    return true;
  }
}

/// ATTACH
export class AttachHandler extends BaseSqlHandler {
  match(sql: string) {
    return Tools.startsWithIgnoreCase(sql, Constant.SQL_ATTACH);
  }
  execute(sql: string, operation: Operation, db: relationalStore.RdbStore) {
    return this.handleAttach(db, sql, operation);
  }

  private async handleAttach(db: relationalStore.RdbStore, sql: string, operation: Operation): Promise<boolean> {
    const sqlArguments: string[] | undefined = operation.getArgument(Constant.PARAM_SQL_ARGUMENTS);
    // 参数校验：语句含 '?' 占位符时必须提供参数数组，避免非空断言抛 TypeError
    const missingArguments: boolean = sqlArguments === undefined || sqlArguments.length === 0;

    const exprPattern = /attach\s+(?:database\s+)?([^\s;]+?)(?:\s+as\s+)/i;
    const exprMatch = sql.match(exprPattern);
    let fullPath: string = '';
    if (exprMatch) {
      if (exprMatch[1].trim() == '?' && missingArguments) {
        operation.error(Constant.SQLITE_ERROR, 'attach: missing sql arguments', '');
        return false;
      }
      fullPath = ((exprMatch[1].trim() == '?') ? sqlArguments![0] : exprMatch[1].trim());
      // 移除路径两边的引号 (单引号或双引号)
      fullPath = fullPath.replace(/^['"]|['"]$/g, '');
    }

    const schemaPattern = /\s+as\s+([^\s;]+)/i;
    const schemaMatch = sql.match(schemaPattern);
    let attachName: string = '';
    if (schemaMatch) {
      if (schemaMatch[1].trim() == '?' && missingArguments) {
        operation.error(Constant.SQLITE_ERROR, 'attach: missing sql arguments', '');
        return false;
      }
      attachName = ((schemaMatch[1].trim() == '?') ? (sqlArguments![sqlArguments!.length - 1]) : schemaMatch[1].trim());
      // 移除 schema 名称两边的引号
      attachName = attachName.replace(/^['"]|['"]$/g, '');
    }

    try {
      await db.attach(fullPath, attachName);
      operation.success(null);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      operation.error(Constant.SQLITE_ERROR,
        `attach failed, error code: ${error.code}. message is ${error.message}`,
        SqlErrorInfo.getMap(operation));
      return false;
    }
  }
}

/// DETACH
export class DetachHandler extends BaseSqlHandler {
  match(sql: string) {
    return Tools.startsWithIgnoreCase(sql, Constant.SQL_DETACH);
  }
  execute(sql: string, operation: Operation, db: relationalStore.RdbStore) {
    return this.handleDetach(db, sql, operation);
  }

  private async handleDetach(db: relationalStore.RdbStore, sql: string, operation: Operation): Promise<boolean> {
    const sqlArguments: string[] | undefined = operation.getArgument(Constant.PARAM_SQL_ARGUMENTS);
    // 参数校验：语句含 '?' 占位符时必须提供参数数组，避免非空断言抛 TypeError
    const missingArguments: boolean = sqlArguments === undefined || sqlArguments.length === 0;

    const schemaPattern = /detach\s+(?:database\s+)?([^\s;]+)/i;
    const schemaMatch = sql.match(schemaPattern);
    let attachName: string = '';
    if (schemaMatch) {
      if (schemaMatch[1].trim() == '?' && missingArguments) {
        operation.error(Constant.SQLITE_ERROR, 'detach: missing sql arguments', '');
        return false;
      }
      attachName = ((schemaMatch[1].trim() == '?') ? (sqlArguments![0]) : schemaMatch[1].trim());
    }

    try {
      await db.detach(attachName);
      operation.success(null);
      return true;
    } catch (err) {
      const error = err as BusinessError;
      operation.error(Constant.SQLITE_ERROR,
        `detach failed, error code: ${error.code}. message is ${error.message}`,
        SqlErrorInfo.getMap(operation));
      return false;
    }
  }
}

/// VACUUM：OHOS RDB 引擎不支持，直接返回明确错误，避免落入通用 14800021 映射而误报 syntax error。
/// 命中即拦截，Dart 侧收到 "VACUUM is not supported on this platform (OpenHarmony RDB)"。
export function isVacuumStatement(sql: string): boolean {
  if (!sql) {
    return false;
  }
  return Tools.startsWithIgnoreCase(sql.trim(), Constant.SQL_VACUUM);
}

/**
 * 报告 VACUUM 不支持错误
 * @param operation 操作对象
 * @returns false，表示执行失败
 */
export function reportVacuumNotSupported(operation: Operation): boolean {
  operation.error(Constant.SQLITE_ERROR, Constant.MSG_VACUUM_NOT_SUPPORTED, SqlErrorInfo.getMap(operation));
  return false;
}

/**
 * 尝试在 OHOS RDB 上真正执行 VACUUM。
 * VACUUM 非 DDL，插件按 DML/通用语句走 execute() 被 OHOS RDB 拒绝（曾误报 syntax error）；
 * 但 DDL 路径 executeSql() 是否接受 VACUUM 取决于 RDB 引擎，因此先尝试真正执行，
 * 引擎同样拒绝（14800021 / not supported）时才降级为明确的 not supported。
 * @param sql VACUUM 语句
 * @param operation 操作对象
 * @param db RdbStore 实例
 * @returns true 表示执行成功或已处理，false 表示失败
 */
export async function tryVacuumOrReportNotSupported(sql: string, operation: Operation,
  db: relationalStore.RdbStore): Promise<boolean> {
  try {
    await db.executeSql(sql);
    operation.success(null);
    return true;
  } catch (err) {
    const businessErr = err as BusinessError;
    // RDB 引擎拒绝该语句（generic/not supported）→ 返回明确错误；其他错误按原样上报
    if (businessErr.code === Constant.RDB_ERROR_CODE_14800021 ||
      (businessErr.message && businessErr.message.toLowerCase().includes('not supported'))) {
      return reportVacuumNotSupported(operation);
    }
    operation.error(Constant.SQLITE_ERROR, `error code: ${businessErr.code}。${businessErr.message}`, '');
    return false;
  }
}

export class VacuumHandler extends BaseSqlHandler {
  match(sql: string) {
    return isVacuumStatement(sql);
  }

  execute(sql: string, operation: Operation, db: relationalStore.RdbStore): Promise<boolean> {
    return tryVacuumOrReportNotSupported(sql, operation, db);
  }

  get needsPostProcess(): boolean {
    return false;
  }
}