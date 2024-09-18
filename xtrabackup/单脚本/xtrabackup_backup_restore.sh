#!/usr/bin/env bash
#
# * @file            xtrabackup/单脚本/xtrabackup_backup_restore.sh
# * @description     xtrabackup备份恢复脚本
# * @author          ygqygq2 <ygqygq2@qq.com>
# * @createTime      2024-09-14 18:17:28
# * @lastModified    2024-09-14 18:33:32
# * Copyright ©ygqygq2 All rights reserved
#

#获取脚本所存放目录
cd $(dirname $0)
PWD_PATH=$(pwd)
#脚本名
ME=$(basename $0)

#定义变量
LOG=/data/backup/${HOSTNAME}.log              # 备份开始结束日志
DATE=week$(date +%V)                          # 备份根目录，其子目录：base为全量，inc1、inc2...为增量
MYSQL="mysql"                                 # mysql命令绝对路径或在PATH中
MYSQL_DATA_DIR="//usr/local/mysql/data"       # 数据库目录
MYSQLDUMP="${MYSQL}dump"                      # mysqldump命令绝对路径或在PATH中
MYSQLBINLOG="${MYSQL}binlog"                  # mysqlbinlog命令绝对路径或在PATH中
BACKUP_USER="xtrabackup"                      # 备份用户
PASSWD=$(cat /data/save/mysql_xtrabackup)     # 备份密码保存文件
BACK_TMP_DIR="/data/backup/database/tmp"      # 备份临时目录
BACK_FILE_DIR="/data/backup/database/${DATE}" # 备份频率目录，此目录变化频率为备份一周期
EMAIL=("")                                    # 邮件收件人
BACK_SERVER="172.30.47.201"                   # 远程备份服务器IP
BACK_SERVER_BASE_DIR="/data/backup"
BACK_SERVER_DIR="$BACK_SERVER_BASE_DIR/mysql/${HOSTNAME}" # 远程备份服务器目录
BACK_SERVER_LOG_DIR="$BACK_SERVER_BASE_DIR/mysql/logs"
SSH_PORT="22" # ssh端口
SSH_PARAMETERS="-o StrictHostKeyChecking=no -o ConnectTimeout=60"
SSH_COMMAND="ssh ${SSH_PARAMETERS} -p ${SSH_PORT}"
SCP_COMMAND="scp ${SSH_PARAMETERS} -P ${SSH_PORT}"

#定义保存日志函数
function Save_Log() {
	echo -e "$(date +%F\ %T) $*" >>$LOG
}

#定义输出颜色函数
function Red_Echo() {
	#用法:  Red_Echo "内容"
	local what="$*"
	echo -e "$(date +%F-%T) \e[1;31m ${what} \e[0m"
}

function Green_Echo() {
	#用法:  Green_Echo "内容"
	local what="$*"
	echo -e "$(date +%F-%T) \e[1;32m ${what} \e[0m"
}

function Yellow_Echo() {
	#用法:  Yellow_Echo "内容"
	local what="$*"
	echo -e "$(date +%F-%T) \e[1;33m ${what} \e[0m"
}

function Blue_Echo() {
	#用法:  Blue_Echo "内容"
	local what="$*"
	echo -e "$(date +%F-%T) \e[1;34m ${what} \e[0m"
}

function Twinkle_Echo() {
	#用法:  Twinkle_Echo $(Red_Echo "内容")  ,此处例子为红色闪烁输出
	local twinkle='\e[05m'
	local what="${twinkle} $*"
	echo -e "$(date +%F-%T) ${what}"
}

function Return_Echo() {
	if [ $? -eq 0 ]; then
		echo -n "$* " && Green_Echo "成功"
		return 0
	else
		echo -n "$* " && Red_Echo "失败"
		return 1
	fi
}

function Return_Error_Exit() {
	[ $? -eq 0 ] && local REVAL="0"
	local what=$*
	if [ "$REVAL" = "0" ]; then
		[ ! -z "$what" ] && { echo -n "$* " && Green_Echo "成功"; }
	else
		Red_Echo "$* 失败，脚本退出"
		exit 1
	fi
}

# 定义确认函数
function User_Verify() {
	while true; do
		echo ""
		read -p "是否确认?[Y/N]:" Y
		case $Y in
		[yY] | [yY][eE][sS])
			echo -e "answer:  \\033[20G [ \e[1;32m是\e[0m ] \033[0m"
			break
			;;
		[nN] | [nN][oO])
			echo -e "answer:  \\033[20G [ \e[1;32m否\e[0m ] \033[0m"
			exit 1
			;;
		*)
			continue
			;;
		esac
	done
}

# 定义跳过函数
function User_Pass() {
	while true; do
		echo ""
		read -p "是否确认?[Y/N]:" Y
		case $Y in
		[yY] | [yY][eE][sS])
			echo -e "answer:  \\033[20G [ \e[1;32m是\e[0m ] \033[0m"
			break
			;;
		[nN] | [nN][oO])
			echo -e "answer:  \\033[20G [ \e[1;32m否\e[0m ] \033[0m"
			return 1
			;;
		*)
			continue
			;;
		esac
	done
}

#定义数据库恢复函数
function restore_backup() {
	#确认还原文件或者目录
	Twinkle_Echo $(Yellow_Echo "请确认是否此脚本目录中已有需要已还原的准备文件或者目录")
	User_Verify

	#确认是否需要解压
	cd $PWD_PATH
	Twinkle_Echo $(Yellow_Echo "请确认是否需要解压")
	User_Pass
	if [ $? -eq 0 ]; then
		find ./ -maxdepth 1 -name "*.tar.bz2" | xargs -i tar xvjf {}
	fi

	#xtrabackup准备还原
	if [ -d "base" ]; then
		#判断是否增量还原
		if [ -d "inc1" ]; then
			N_=$(ls -l | grep '^d' | egrep 'inc*' | sort -n -k 9 | sed -n '$p' | awk '{print $NF}' | sed -e 's#inc\(.*\)#\1#')
			N=$(ls -l | grep '^d' | egrep 'inc*' | wc -l)
			if [ "$N_" = "$N" ]; then
				#文件夹检查成功
				Return_Error_Exit "The prepare folder check complete"
				#进行增量备份还原准备
				xtrabackup --prepare --apply-log-only --target-dir=${PWD_PATH}/base
				Return_Error_Exit "xtrabackup prepare folder base"
				for ((i = 1; i <= $N_; i++)); do
					if [ "$i" = "$N_" ]; then
						#最后一个文件夹不加--apply-log-only参数
						xtrabackup --prepare --target-dir=${PWD_PATH}/base \
							--incremental-dir=${PWD_PATH}/inc$i
						Return_Error_Exit "xtrabackup prepare folder inc$i"
					else
						xtrabackup --prepare --apply-log-only --target-dir=${PWD_PATH}/base \
							--incremental-dir=${PWD_PATH}/inc$i
						Return_Error_Exit "xtrabackup prepare folder inc$i"
					fi
				done
			else
				#文件夹缺失
				Return_Error_Exit "The prepare folder check complete"
			fi
		else
			#进行完全备份还原准备
			xtrabackup --prepare --target-dir=${PWD_PATH}/base
			Return_Error_Exit "xtrabackup prepare folder base"
		fi
	else
		#文件夹缺失
		Return_Error_Exit "The prepare folder check complete"
	fi

	#停数据库
	Yellow_Echo "停数据库..."
	service mysql stop
	Return_Error_Exit "stop mysql"

	#先备份要覆盖的文件，防止恢复失败数据库文件损坏千万数据丢失
	_back_dir=$(date +%F-%T)
	mkdir -p /tmp/${_back_dir}
	cd ${PWD_PATH}/base/
	_files=($(ls | grep -v xtrabackup_))
	cd $MYSQL_DATA_DIR/
	mv ${_files[@]} /tmp/${_back_dir}
	Return_Error_Exit "backup files before restore"

	#恢复数据文件
	rsync -avz ${PWD_PATH}/base/* --exclude='xtrabackup_*' $MYSQL_DATA_DIR/
	Return_Error_Exit "rsync data"

	#修改权限
	chown -R mysql:mysql $MYSQL_DATA_DIR/

	#启动数据库
	service mysql start
	Return_Error_Exit "start mysql"

}

Save_Log "start $0"

restore_backup

Save_Log "finish $0"
