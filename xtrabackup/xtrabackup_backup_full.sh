#!/usr/bin/env bash

#获取脚本所存放目录
cd $(dirname $0)
PWD_PATH=$(pwd)
#脚本名
ME=$(basename $0)

#设置要备份的innodb数据库，用空格格开，空为备份所有库
DATABASES=''

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

Save_Log "start $0"

#创建目录
[ ! -d "${BACK_TMP_DIR}" ] && mkdir -p ${BACK_TMP_DIR}
[ ! -d "${BACK_FILE_DIR}" ] && mkdir -p ${BACK_FILE_DIR}

function Full_Backup() {
	# 全量备份函数
	[ ! -z "$databases" ] && option="--DATABASES=\"$databases\""

	#备份失败操作
	function Backup_Failed_Operation() {
		Save_Log "full-backuped failed"
		Send_Mail "mysql full-backuped failed"
		rm -rf $BACK_FILE_DIR/base
		exit 1
	}
	##############################MYSQL全库备份#########################
	xtrabackup -u$BACKUP_USER -p"$PASSWD" --backup --target-dir=${BACK_FILE_DIR}/base \
		--datadir=${MYSQL_DATA_DIR}/ $option
	[ $? -eq 0 ] && Save_Log "full-backuped successed" || Backup_Failed_Operation
	###################################################################

	if [ ! -z "$databases" ]; then
		#备份表结构
		for database in ${databases[@]}; do
			rsync -avz ${MYSQL_DATA_DIR}/$database/*.frm ${BACK_FILE_DIR}/base/$database/
			[ $? -eq 0 ] && Save_Log "rsync $databse tables structure successed" ||
				Save_Log "rsync $databse tables structure  failed"
		done
	fi

	#压缩打包
	cd $BACK_FILE_DIR/
	tar -cvjf base.tar.bz2 base/

}

function Rsync_Backup_Files() {
	#传输到远程服务器备份, 需要配置免密ssh认证
	$SSH_COMMAND root@${BACK_SERVER} "mkdir -p ${BACK_SERVER_DIR}/${DATE}/"
	rsync -avz --bwlimit=500 -e "${SSH_COMMAND}" $BACK_FILE_DIR/base.tar.bz2 \
		root@${BACK_SERVER}:${BACK_SERVER_DIR}/${DATE}/
	[ $? -eq 0 ] && Save_Log "full-backuped rsync successed" ||
		{
			Save_Log "full-backuped rsync failed"
			Send_Mail "mysql full-backuped rsync failed"
		}
}

Full_Backup
Rsync_Backup_Files

Save_Log "finish $0\n"
