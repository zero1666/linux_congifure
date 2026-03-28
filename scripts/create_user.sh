#!/bin/bash
#============================================================
# TencentOS 创建新用户账号脚本
# 支持: TS3.x / TS4 (基于 RHEL 系列)
# 功能: 创建用户、设置密码、配置用户组、可选 sudo 权限
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
  -u, --username <用户名>      新用户的用户名 (必填)
  -s, --shell <shell路径>      指定默认 shell (默认: /bin/bash)
  -g, --group <附加组>         附加用户组，逗号分隔 (可选)
  -d, --home <家目录>          指定家目录路径 (默认: /home/<用户名>)
  -S, --sudo                   授予 sudo 权限 (加入 wheel 组)
  -n, --no-interactive         非交互模式 (需配合 -p 使用)
  -p, --password <密码>        设置密码 (仅非交互模式)
  -e, --expire <天数>          密码过期天数 (可选)
  -c, --comment <备注>         用户备注信息 (可选)
  -h, --help                   显示帮助信息

示例:
  $0 -u newuser -S                          # 交互式创建用户并授予sudo权限
  $0 -u newuser -s /bin/zsh -g dev,docker   # 指定shell和附加组
  $0 -u newuser -n -p 'MyPass123!'          # 非交互模式
EOF
    exit 0
}

# 默认值
USERNAME=""
SHELL_PATH="/bin/bash"
EXTRA_GROUPS=""
HOME_DIR=""
GRANT_SUDO=false
INTERACTIVE=true
PASSWORD=""
EXPIRE_DAYS=""
COMMENT=""

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -u|--username)   USERNAME="$2";    shift 2 ;;
        -s|--shell)      SHELL_PATH="$2";  shift 2 ;;
        -g|--group)      EXTRA_GROUPS="$2"; shift 2 ;;
        -d|--home)       HOME_DIR="$2";    shift 2 ;;
        -S|--sudo)       GRANT_SUDO=true;  shift ;;
        -n|--no-interactive) INTERACTIVE=false; shift ;;
        -p|--password)   PASSWORD="$2";    shift 2 ;;
        -e|--expire)     EXPIRE_DAYS="$2"; shift 2 ;;
        -c|--comment)    COMMENT="$2";     shift 2 ;;
        -h|--help)       usage ;;
        *) log_error "未知参数: $1"; usage ;;
    esac
done

# 交互式输入
if [[ -z "$USERNAME" ]]; then
    if [[ "$INTERACTIVE" == false ]]; then
        log_error "非交互模式下必须指定用户名 (-u)"
        exit 1
    fi
    read -rp "请输入新用户名: " USERNAME
fi

# 校验用户名
if [[ ! "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    log_error "用户名不合法: 只能包含小写字母、数字、下划线和连字符，且以字母或下划线开头"
    exit 1
fi

# 检查用户是否已存在
if id "$USERNAME" &>/dev/null; then
    log_error "用户 '$USERNAME' 已存在"
    exit 1
fi

# 交互式获取更多信息
if [[ "$INTERACTIVE" == true ]]; then
    # 备注
    if [[ -z "$COMMENT" ]]; then
        read -rp "用户备注 (可选，直接回车跳过): " COMMENT
    fi

    # Shell
    read -rp "默认 Shell [$SHELL_PATH]: " input_shell
    [[ -n "$input_shell" ]] && SHELL_PATH="$input_shell"

    # 家目录
    default_home="/home/$USERNAME"
    read -rp "家目录 [$default_home]: " input_home
    HOME_DIR="${input_home:-$default_home}"

    # 附加组
    if [[ -z "$EXTRA_GROUPS" ]]; then
        read -rp "附加用户组 (逗号分隔，可选): " EXTRA_GROUPS
    fi

    # sudo 权限
    if [[ "$GRANT_SUDO" == false ]]; then
        read -rp "是否授予 sudo 权限? [y/N]: " grant_input
        [[ "$grant_input" =~ ^[Yy]$ ]] && GRANT_SUDO=true
    fi

    # 密码过期
    if [[ -z "$EXPIRE_DAYS" ]]; then
        read -rp "密码过期天数 (可选，直接回车跳过): " EXPIRE_DAYS
    fi
fi

# 设置默认家目录
[[ -z "$HOME_DIR" ]] && HOME_DIR="/home/$USERNAME"

# 校验 Shell 是否存在
if [[ ! -x "$SHELL_PATH" ]]; then
    log_warn "Shell '$SHELL_PATH' 不存在或不可执行，将使用 /bin/bash"
    SHELL_PATH="/bin/bash"
fi

#============================================================
# 开始创建用户
#============================================================
echo ""
log_info "====== 创建用户摘要 ======"
echo "  用户名:     $USERNAME"
echo "  家目录:     $HOME_DIR"
echo "  Shell:      $SHELL_PATH"
echo "  附加组:     ${EXTRA_GROUPS:-无}"
echo "  sudo 权限:  $GRANT_SUDO"
echo "  备注:       ${COMMENT:-无}"
echo "  密码过期:   ${EXPIRE_DAYS:-不限制}"
echo ""

if [[ "$INTERACTIVE" == true ]]; then
    read -rp "确认创建? [Y/n]: " confirm
    [[ "$confirm" =~ ^[Nn]$ ]] && { log_warn "已取消"; exit 0; }
fi

# 1. 创建附加组（如果不存在）
if [[ -n "$EXTRA_GROUPS" ]]; then
    IFS=',' read -ra GROUP_ARRAY <<< "$EXTRA_GROUPS"
    for grp in "${GROUP_ARRAY[@]}"; do
        grp=$(echo "$grp" | xargs)  # 去空格
        if ! getent group "$grp" &>/dev/null; then
            log_info "创建用户组: $grp"
            groupadd "$grp"
        fi
    done
fi

# 2. 构建 useradd 命令
CMD="useradd -m -s $SHELL_PATH -d $HOME_DIR"
[[ -n "$COMMENT" ]]      && CMD="$CMD -c \"$COMMENT\""
[[ -n "$EXTRA_GROUPS" ]]  && CMD="$CMD -G $EXTRA_GROUPS"

log_info "执行: $CMD $USERNAME"
eval "$CMD $USERNAME"

# 3. 设置密码
if [[ "$INTERACTIVE" == true ]]; then
    log_info "请为用户 '$USERNAME' 设置密码:"
    passwd "$USERNAME"
else
    if [[ -n "$PASSWORD" ]]; then
        echo "$USERNAME:$PASSWORD" | chpasswd
        log_info "密码已设置"
    else
        log_warn "未设置密码，用户将无法通过密码登录"
    fi
fi

# 4. 授予 sudo 权限 (加入 wheel 组)
if [[ "$GRANT_SUDO" == true ]]; then
    # 确保 wheel 组存在
    if ! getent group wheel &>/dev/null; then
        groupadd wheel
    fi

    # 确保 sudoers 中已启用 wheel 组
    if grep -q "^#.*%wheel.*ALL=(ALL).*ALL" /etc/sudoers 2>/dev/null; then
        log_warn "正在启用 /etc/sudoers 中的 wheel 组权限..."
        sed -i 's/^#\s*\(%wheel\s\+ALL=(ALL)\s\+ALL\)/\1/' /etc/sudoers
    fi

    usermod -aG wheel "$USERNAME"
    log_info "已将 '$USERNAME' 加入 wheel 组，已授予 sudo 权限"
fi

# 5. 设置密码过期策略
if [[ -n "$EXPIRE_DAYS" ]]; then
    chage -M "$EXPIRE_DAYS" "$USERNAME"
    log_info "密码有效期设置为 $EXPIRE_DAYS 天"
fi

# 6. 验证用户创建结果
echo ""
log_info "====== 用户创建成功 ======"
echo "  用户信息:"
id "$USERNAME"
echo "  家目录:"
ls -ld "$HOME_DIR"
echo ""

# 7. 显示可用的后续操作提示
cat <<EOF
后续操作提示:
  切换到新用户:          su - $USERNAME
  修改用户密码:          passwd $USERNAME
  锁定用户账号:          passwd -l $USERNAME
  解锁用户账号:          passwd -u $USERNAME
  删除用户(保留家目录):  userdel $USERNAME
  删除用户(含家目录):    userdel -r $USERNAME
EOF
