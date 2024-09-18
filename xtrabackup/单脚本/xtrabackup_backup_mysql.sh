#!/usr/bin/env bash

#获取脚本所存放目录
cd $(dirname $0)
PWD_PATH=$(pwd)
#脚本名
ME=$(basename $0)

# 定义备份的数据库
# DATABASES="zabbix,mysql"
DATABASES=""

#定义变量
LOG=/data/backup/${HOSTNAME}.log              # 备份开始结束日志
DATE=week$(date +%V)                          # 备份根目录，其子目录：base为全量，inc1、inc2...为增量
MYSQL="mysql"                                 # mysql命令绝对路径或在PATH中
MYSQL_DATA_DIR="/usr/local/mysql/data"        # 数据库目录
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

Save_Log "start backup mysql"

#创建目录
[ ! -d "${BACK_TMP_DIR}" ] && mkdir -p ${BACK_TMP_DIR}
[ ! -d "${BACK_FILE_DIR}" ] && mkdir -p ${BACK_FILE_DIR}

function Full_Backup() {
    # 全量备份函数
    [ ! -z "$databases" ] && option="--DATABASES=\"$databases\""

    #备份失败操作
    function Backup_Failed_Operation() {
        Save_Log "failed backup mysql"
        rm -rf $BACK_FILE_DIR/base
        exit 1
    }
    ##############################MYSQL全库备份#########################
    xtrabackup -u$BACKUP_USER -p"$PASSWD" --backup --target-dir=${BACK_FILE_DIR}/base \
        --datadir=${MYSQL_DATA_DIR}/ $option
    [ $? -eq 0 ] && Save_Log "success mysql" || Backup_Failed_Operation
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
    # tar -cvjf base.tar.bz2 base/
    Save_Log "begin tar base"
    7za a base.7z base/
    if [ $? -eq 0 ]; then
        Save_Log $(du -sh base.7z)
        Save_Log "finish tar base"
    else
        Save_Log "failed tar base"
    fi

    return 0
}

function Incremental_Backup() {
    [ ! -z "$databases" ] && option="--DATABASES=\"$databases\""

    #备份失败操作
    function Backup_Failed_Operation() {
        Save_Log "failed mysql"
        rm -rf $BACK_FILE_DIR/inc$N
        exit 1
    }

    #第N次增量备份
    cd $BACK_FILE_DIR
    # 判断是否存在第一次增量备份目录inc1
    # 存在则获取最后一次增量备份目录incN，然后基于最后一次增量备份，做增量备份
    # 不存在则基于全量备份目录base做增量备份
    if [ -d "inc1" ]; then
        N_=$(ls -l | grep '^d' | egrep 'inc*' | sort -n -k 9 | sed -n '$p' | awk '{print $NF}' | sed -e 's#inc\(.*\)#\1#')
        N=$(($N_+1))
        #增量备份
        xtrabackup -u$BACKUP_USER -p"$PASSWD" --backup --target-dir=$BACK_FILE_DIR/inc$N \
            --incremental-basedir=$BACK_FILE_DIR/inc$N_ --datadir=$MYSQL_DATA_DIR $option
        [ $? -eq 0 ] && Save_Log "success mysql" || Backup_Failed_Operation
    else
        N="1"
        #增量备份
        xtrabackup -u$BACKUP_USER -p"$PASSWD" --backup --target-dir=$BACK_FILE_DIR/inc$N \
            --incremental-basedir=$BACK_FILE_DIR/base --datadir=$MYSQL_DATA_DIR $option
        [ $? -eq 0 ] && Save_Log "success mysql" || Backup_Failed_Operation
    fi

    #压缩打包
    cd $BACK_FILE_DIR/
    #tar -cvjf inc$N.tar.bz2 inc$N/
    Save_Log "begin tar inc${N}"
    7za a inc${N}.7z inc$N/
    if [ $? -eq 0 ]; then
        Save_Log $(du -sh inc${N}.7z)
        Save_Log "finish tar inc${N}"
    else
        Save_Log "failed tar inc${N}"
    fi

    return 0
}

function Rsync_Backup_Files() {
    # 传输日志文件
    rsync_log_file_cmd="rsync -avz -e '${SSH_COMMAND}' $LOG root@${BACK_SERVER}:$BACK_SERVER_LOG_DIR/"
    #传输到远程服务器备份, 需要配置免密ssh认证
    $SSH_COMMAND root@${BACK_SERVER} "mkdir -p ${BACK_SERVER_DIR}/${DATE}/"
    rsync -avz --bwlimit=5000 -e "${SSH_COMMAND}" $BACK_FILE_DIR/*.7z \
        root@${BACK_SERVER}:${BACK_SERVER_DIR}/${DATE}/
    [ $? -eq 0 ] && { Save_Log "success rsync_mysql" && eval $rsync_log_file_cmd; } ||
        Save_Log "failed rsync_mysql"
}

#判断进行哪种备份
if [ ! -d $BACK_FILE_DIR/base ]; then
    Full_Backup >>/tmp/xtrabackup_back_full_${DATE}.log 2>&1
else
    Incremental_Backup >>/tmp/xtrabackup_back_incremental_${DATE}.log 2>&1
fi

Rsync_Backup_Files
Save_Log "finish $0\n"
