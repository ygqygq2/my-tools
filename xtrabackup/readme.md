## 1. 使用说明

此脚本基于 Percona XtraBackup 2.4、8.0

## 2. 备份用户权限

- 2.4 版本权限：
  在 mysql 的 root 用户下，创建用户并给予下列权限

```sql
GRANT SUPER, RELOAD, LOCK TABLES, PROCESS, REPLICATION CLIENT ON *.* TO 'xtrabackup'@'localhost' identified by '12345678';
```

> 没有 SUPER 权限，会在增量备份时报如下错误  
> Error: failed to execute query FLUSH NO_WRITE_TO_BINLOG CHANGED_PAGE_BITMAPS: Access denied; you need (at least one of) the SUPER privilege(s) for this operation

- 8.0 版本权限：
  在 mysql 的 root 用户下，创建用户并给予下列权限

```sql
CREATE USER 'xtrabackup'@'localhost' IDENTIFIED BY '12345678';
GRANT RELOAD, LOCK TABLES, PROCESS, REPLICATION CLIENT, BACKUP_ADMIN ON *.* TO 'xtrabackup'@'localhost';
```

将备份使用的密码写入到以下文件中，因为脚本为读取此文件中的密码。

```bash
mkdir -p /data/save/
echo '12345678' > /data/save/mysql_xtrabackup
```

## 3. 脚本使用说明

脚本使用场景为一天中备份多次。

xtrabackup_backup_mysql.sh # 脚本控制入口  
xtrabackup_backup_full.sh # 全量备份脚本  
xtrabackup_backup_incremental.sh # 增量备份脚本  
xtrabackup_backup_restore.sh # 备份恢复脚本

## 4. xtrabackup 关键参数说明

在`xtrabackup --prepare`时，如果不使用`--apply-log-only`以防止数据库回滚，那么你的增量备份将是无用的。因为事务回滚后,进一步的增量备份是不能被应用的。

`--apply-log-only`应该在合并除最后一次增量备份的所有增量备份时，这就是为什么恢复备份脚本中，最后一次增量备份`xtrabackup --prepare`不使用它的原因。即使`--apply-log-only`在最后一次增量备份时被使用，备份仍将是一致的，但在这种情况下，数据库会有执行回滚的阶段。
