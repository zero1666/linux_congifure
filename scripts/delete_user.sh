#!/bin/bash
#============================================================
# TencentOS 删除用户账号脚本
# 支持: TS3.x / TS4 (基于 RHEL 系列)
# 功能: 删除用户、清理主目录、备份数据、终止进程
#============================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查 root 权限
if [[ $EUID -ne 0 ]]; then
    log_error "此脚本需要 root 权限运行，请使用 sudo 执行"
    exit 1
fi

# 显示用法
usage() {
    cat <<EOF
用法: $0 [选项]

选项:
  -u, --username <用户名>      要删除的用户名 (必填)
  -r, --remove-home            同时删除用户主目录和邮件
  -b, --backup                 删除前备份用户主目录
  -B, --backup-dir <目录>      备份存放目录 (默认: /tmp/user_backups)
  -k, --kill                   自动终止该用户的所有运行中进程
  -n, --no-interactive         非交互模式 (跳过确认提示)
  -h, --help                   显示帮助信息

示例:
  $0 -u testuser                        # 交互式删除用户，保留主目录
  $0 -u testuser -r                     # 交互式删除用户并清除主目录
  $0 -u testuser -r -b -k               # 备份主目录后删除用户，并终止其进程
  $0 -u testuser -r -n                  # 非交互模式，删除用户及主目录
  $0 -u testuser -r -b -B /data/backup  # 指定备份目录
EOF
    exit 0
}

# 系统保护用户列表
PROTECTED_USERS="root nobody daemon bin sys sync games man lp mail news uucp proxy www-data sshd systemd-network systemd-resolve polkitd tss ntp chrony dbus"

# 默认值
USERNAME=""
REMOVE_HOME=false
BACKUP=false
BACKUP_DIR="/tmp/user_backups"
KILL_PROCS=false
INTERACTIVE=true

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--username)       USERNAME="$2";    shift 2 ;;
        -r|--remove-home)    REMOVE_HOME=true; shift ;;
        -b|--backup)         BACKUP=true;      shift ;;
        -B|--backup-dir)     BACKUP_DIR="$2";  shift 2 ;;
        -k|--kill)           KILL_PROCS=true;  shift ;;
        -n|--no-interactive) INTERACTIVE=false; shift ;;
        -h|--help)           usage ;;
        *) log_error "未知参数: $1"; usage ;;
    esac
done

# 交互式输入
if [[ -z "$USERNAME" ]]; then
    if [[ "$INTERACTIVE" == false ]]; then
        log_error "非交互模式下必须指定用户名 (-u)"
        exit 1
    fi
    read -rp "请输入要删除的用户名: " USERNAME
fi

# 校验用户名非空
if [[ -z "$USERNAME" ]]; then
    log_error "用户名不能为空"
    exit 1
fi

# 检查用户是否存在
if ! id "$USERNAME" &>/dev/null; then
    log_error "用户 '$USERNAME' 不存在"
    exit 1
fi

# 检查是否为系统保护用户
for pu in $PROTECTED_USERS; do
    if [[ "$USERNAME" == "$pu" ]]; then
        log_error "用户 '$USERNAME' 是系统关键用户，禁止删除！"
        exit 1
    fi
done

# 获取用户信息
USER_HOME=$(getent passwd "$USERNAME" | cut -d: -f6)
USER_UID=$(id -u "$USERNAME")
USER_GID=$(id -g "$USERNAME")
USER_GROUPS=$(id -Gn "$USERNAME" | tr ' ' ', ')
USER_SHELL=$(getent passwd "$USERNAME" | cut -d: -f7)
USER_COMMENT=$(getent passwd "$USERNAME" | cut -d: -f5)
PROC_COUNT=$(pgrep -cu "$USERNAME" 2>/dev/null || echo "0")

# 获取主目录大小
if [[ -d "$USER_HOME" ]]; then
    HOME_SIZE=$(du -sh "$USER_HOME" 2>/dev/null | awk '{print $1}')
else
    HOME_SIZE="(主目录不存在)"
fi

# 获取 crontab 条数
CRON_COUNT=0
if crontab -l -u "$USERNAME" &>/dev/null; then
    CRON_COUNT=$(crontab -l -u "$USERNAME" 2>/dev/null | grep -cv '^#\|^$' || echo "0")
fi

# 交互式获取更多选项
if [[ "$INTERACTIVE" == true ]]; then
    if [[ "$REMOVE_HOME" == false ]]; then
        read -rp "是否同时删除主目录 '$USER_HOME'? [y/N]: " rm_input
        [[ "$rm_input" =~ ^[Yy]$ ]] && REMOVE_HOME=true
    fi

    if [[ "$REMOVE_HOME" == true && "$BACKUP" == false ]]; then
        read -rp "是否在删除前备份主目录? [Y/n]: " bk_input
        [[ ! "$bk_input" =~ ^[Nn]$ ]] && BACKUP=true
    fi

    if [[ "$PROC_COUNT" -gt 0 && "$KILL_PROCS" == false ]]; then
        read -rp "用户有 $PROC_COUNT 个运行中的进程，是否自动终止? [y/N]: " kill_input
        [[ "$kill_input" =~ ^[Yy]$ ]] && KILL_PROCS=true
    fi
fi

#============================================================
# 显示删除摘要
#============================================================
echo ""
log_info "====== 删除用户摘要 ======"
echo "  用户名:     $USERNAME"
echo "  UID/GID:    $USER_UID / $USER_GID"
echo "  所属组:     $USER_GROUPS"
echo "  主目录:     $USER_HOME ($HOME_SIZE)"
echo "  Shell:      $USER_SHELL"
echo "  备注:       ${USER_COMMENT:-无}"
echo "  运行进程:   $PROC_COUNT 个"
echo "  定时任务:   $CRON_COUNT 条"
echo "  ---"
echo "  删除主目录: $REMOVE_HOME"
echo "  备份主目录: $BACKUP"
echo "  终止进程:   $KILL_PROCS"
echo ""

if [[ "$INTERACTIVE" == true ]]; then
    read -rp "确认删除? [y/N]: " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { log_warn "已取消"; exit 0; }
fi

#============================================================
# 开始删除用户
#============================================================

# 1. 终止用户进程
if [[ "$PROC_COUNT" -gt 0 ]]; then
    if [[ "$KILL_PROCS" == true ]]; then
        log_info "正在终止用户 '$USERNAME' 的所有进程..."
        # 先 SIGTERM 优雅终止
        pkill -u "$USERNAME" 2>/dev/null || true
        sleep 2
        # 残留进程强制 SIGKILL
        if pgrep -u "$USERNAME" &>/dev/null; then
            pkill -9 -u "$USERNAME" 2>/dev/null || true
            sleep 1
        fi
        log_info "用户进程已全部终止"
    else
        log_error "用户仍有 $PROC_COUNT 个运行中的进程，请使用 -k 选项自动终止，或手动处理:"
        log_error "  查看进程: ps -u $USERNAME"
        log_error "  终止进程: pkill -u $USERNAME"
        exit 1
    fi
fi

# 2. 备份主目录
if [[ "$BACKUP" == true ]]; then
    if [[ -d "$USER_HOME" ]]; then
        mkdir -p "$BACKUP_DIR"
        BACKUP_FILE="${BACKUP_DIR}/${USERNAME}_$(date +%Y%m%d_%H%M%S).tar.gz"
        log_info "正在备份主目录 '$USER_HOME' -> '$BACKUP_FILE' ..."
        if tar -czf "$BACKUP_FILE" -C "$(dirname "$USER_HOME")" "$(basename "$USER_HOME")" 2>/dev/null; then
            BACKUP_SIZE=$(du -sh "$BACKUP_FILE" | awk '{print $1}')
            log_info "备份完成 ($BACKUP_SIZE): $BACKUP_FILE"
        else
            log_error "备份失败！中止操作"
            exit 1
        fi
    else
        log_warn "主目录 '$USER_HOME' 不存在，跳过备份"
    fi
fi

# 3. 清理用户 crontab
if crontab -l -u "$USERNAME" &>/dev/null; then
    log_info "清理用户 crontab..."
    crontab -r -u "$USERNAME" 2>/dev/null || true
fi

# 4. 删除用户
CMD="userdel"
[[ "$REMOVE_HOME" == true ]] && CMD="$CMD -r"
CMD="$CMD $USERNAME"

log_info "执行: $CMD"
if eval "$CMD" 2>&1; then
    log_info "用户 '$USERNAME' 已成功删除"
else
    log_error "删除用户失败"
    exit 1
fi

# 5. 清理残留文件 (userdel -r 可能不会清理的)
if [[ "$REMOVE_HOME" == true ]]; then
    # 清理邮件
    if [[ -f "/var/spool/mail/$USERNAME" ]]; then
        rm -f "/var/spool/mail/$USERNAME"
        log_info "已清理邮件: /var/spool/mail/$USERNAME"
    fi
    # 清理 at 任务
    if [[ -d /var/spool/at ]]; then
        find /var/spool/at -name "$USERNAME" -delete 2>/dev/null || true
    fi
    # 清理 /tmp 中该用户的临时文件
    find /tmp -maxdepth 1 -user "$USER_UID" -exec rm -rf {} + 2>/dev/null || true
fi

# 6. 检查是否还有残留文件归属于该 UID
echo ""
log_info "====== 删除完成 ======"
log_info "正在检查系统中是否存在该用户 (UID=$USER_UID) 的残留文件..."
ORPHAN_FILES=$(find / -maxdepth 4 -user "$USER_UID" -not -path "/proc/*" -not -path "/sys/*" 2>/dev/null | head -20)
if [[ -n "$ORPHAN_FILES" ]]; then
    log_warn "发现以下残留文件 (属主 UID=$USER_UID):"
    echo "$ORPHAN_FILES"
    echo ""
    log_warn "可使用以下命令查找并处理:"
    echo "  find / -user $USER_UID -ls"
    echo "  find / -user $USER_UID -exec chown <新用户> {} +"
else
    log_info "未发现残留文件"
fi

echo ""
log_info "用户 '$USERNAME' 删除操作全部完成"
