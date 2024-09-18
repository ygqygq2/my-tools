#!/usr/bin/env bash

#获取脚本所存放目录
cd $(dirname $0)
PWD_PATH=$(pwd)
#脚本名
ME=$(basename $0)

#定义变量
LOG=/var/log/mysql_backup.log                  # 备份过程日志
DATE=$(date +%F)                               # 备份根目录，其子目录：base为全量，inc1、inc2...为增量
MYSQL="mysql"                                  # mysql命令绝对路径或在PATH中
MYSQL_DATA_DIR="/var/lib/mysql"                # 数据库目录
MYSQLDUMP="${MYSQL}dump"                       # mysqldump命令绝对路径或在PATH中
MYSQLBINLOG="${MYSQL}binlog"                   # mysqlbinlog命令绝对路径或在PATH中
BACKUP_USER="xtrabackup"                       # 备份用户
PASSWD=$(cat /data/save/mysql_xtrabackup)      # 备份密码保存文件
BACK_TMP_DIR="/data/backups/database/tmp"      # 备份临时目录
BACK_FILE_DIR="/data/backups/database/${DATE}" # 备份频率目录，此目录变化频率为备份一周期
EMAIL=("")                                     # 邮件收件人
BACK_SERVER="127.0.0.1"                        # 远程备份服务器IP
BACK_SERVER_DIR="/home/backup"                 # 远程备份服务器目录
SSH_PORT="22"                                  # ssh端口
SSH_PARAMETERS="-o StrictHostKeyChecking=no -o ConnectTimeout=60"
SSH_COMMAND="ssh ${SSH_PARAMETERS} -p ${SSH_PORT}"
SCP_COMMAND="scp ${SSH_PARAMETERS} -P ${SSH_PORT}"

#定义保存日志函数
function Save_Log() {
	echo -e "[$(date +%F\ %T)]	$*" >>$LOG
}

#定义发送邮件函数
function Send_Mail() {
	echo "[$(date +%F\ %T)]	$*" | mail -s "[mysql]" ${EMAIL[@]}
}

#Save_Log "start $0"

#创建目录
[ ! -d "${BACK_TMP_DIR}" ] && mkdir -p ${BACK_TMP_DIR}
[ ! -d "${BACK_FILE_DIR}" ] && mkdir -p ${BACK_FILE_DIR}

#判断进行哪种备份
if [ ! -d $BACK_FILE_DIR/base ]; then
	/bin/bash ${PWD_PATH}/xtrabackup_backup_full.sh >>/tmp/xtrabackup_back_full_${DATE}.log 2>&1
else
	/bin/bash ${PWD_PATH}/xtrabackup_backup_incremental.sh >>/tmp/xtrabackup_back_incremental_${DATE}.log 2>&1
fi
