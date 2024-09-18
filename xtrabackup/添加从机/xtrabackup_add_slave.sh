#!/usr/bin/env bash
#
# * @file            xtrabackup/添加从机/xtrabackup_add_slave.sh
# * @description     一键创建从库，需要确保本机能ssh免密码登录到从库机器。需要确保二者机器的时间同步。
# * @author          ygqygq2 <ygqygq2@qq.com>
# * @createTime      2024-09-14 18:17:28
# * @lastModified    2024-09-14 18:34:53
# * Copyright ©ygqygq2 All rights reserved
#

# 待配置的从库IP
SLAVE_HOST='S_IP'

# 本机MySQL配置信息
MYSQL_USER='xtrabackup'
MYSQL_PASSWD='xtrabackup'
MYSQL_DATA_DIR="/usr/local/mysql/data"
MYSQL_SOCKET='/tmp/mysql.sock'
TMP_MYSQL_DIR="/tmp/mysql_slave_tmp"
SSH_PORT="22"
SSH_PARAMETERS="-o StrictHostKeyChecking=no -o ConnectTimeout=60"
SSH_COMMAND="ssh ${SSH_PARAMETERS} -p ${SSH_PORT}"
SCP_COMMAND="scp ${SSH_PARAMETERS} -P ${SSH_PORT}"

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

function Check_Tool() {
    Yellow_Echo "Check xtrabackup"
    which xtrabackup
    [ $? -ne 0 ] && Return_Error_Exit "Not install percona-xtrabackup"
    Yellow_Echo "Check $SLAVE_HOST xtrabackup"
    $SSH_COMMAND root@$SLAVE_HOST "which xtrabackup"
    [ $? -ne 0 ] && Return_Error_Exit "$SLAVE_HOST not install percona-xtrabackup"
}
function Init_Remote() {
    mkdir -p $TMP_MYSQL_DIR
    $SSH_COMMAND root@$SLAVE_HOST "mkdir -p $TMP_MYSQL_DIR"
}

function Copy_To_Remote() {
    xtrabackup -u$MYSQL_USER -p$MYSQL_PASSWD --parallel=4 --MYSQL_SOCKET=$MYSQL_SOCKET \
        --no-timestamp --backup --target-dir=$TMP_MYSQL_DIR
    Return_Error_Exit "xtrabackup"
    $SSH_COMMAND root@$SLAVE_HOST "/etc/init.d/mysql stop"
    $SSH_COMMAND root@$SLAVE_HOST "rm -fr $MYSQL_DATA_DIR"
    rsync -avzP -e "${SSH_COMMAND}" $TMP_MYSQL_DIR/ root@$SLAVE_HOST:$MYSQL_DATA_DIR/
    Return_Error_Exit "rsync"
}

function Apply_To_Remote() {
    $SSH_COMMAND root@$SLAVE_HOST "xtrabackup --prepare --target-dir=$MYSQL_DATA_DIR"
    $SSH_COMMAND root@$SLAVE_HOST "chown mysql.mysql -R $MYSQL_DATA_DIR"
    $SSH_COMMAND root@$SLAVE_HOST "/etc/init.d/mysql start"
}

echo "
######################################################################################
请确保从库的server-id与本机不相同，且其他涉及到日志类的参数尽量与本机一致。
这里我们默认已经在主库上执行过创建同步的账户的SQL了,且主库能SSH秘钥方式登录到从库机器
######################################################################################
"

User_Verify # 用户确认
Check_Tool
Init_Remote
Copy_To_Remote
Apply_To_Remote

echo "
###############################################################################
然后登录从数据库执行：
RESET MASTER;
再执行CHANGE MASTER TO的指令，指定具体position或者gtid，然后start slave;即可。
 
格式如下：
CHANGE MASTER TO
  MASTER_HOST='M_IP',
  MASTER_USER='repl',
  MASTER_PASSWORD='ReplPwd',
  MASTER_PORT=3306,
  MASTER_LOG_FILE='mysql-bin.0000XX',
  MASTER_LOG_POS=XXX,
###############################################################################
"
