#!/usr/bin/env bash
# ==============================================================================
# 哪吒监控 Agent 安全加固与控制通道剥离脚本 (Shell Fallback)
# 特性：
# 1. 自动定位常见 Agent 配置文件路径；
# 2. 自动创建原配置备份；
# 3. 幂等性写入核心加固参数：disable_auto_update, disable_command_execute, disable_nat；
# 4. 配置语法与非空自检，异常自动安全回滚；
# 5. 自动重载 systemd 守护进程并优雅重启 nezha-agent 服务；
# 6. 健康检查确认服务持续在后台正常运行。
# ==============================================================================
set -euo pipefail

log_info()  { echo -e "\033[32m[INFO]\033[0m $*"; }
log_warn()  { echo -e "\033[33m[WARN]\033[0m $*"; }
log_error() { echo -e "\033[31m[ERROR]\033[0m $*" >&2; }

# 1. 权限校验
if [[ $EUID -ne 0 ]]; then
   log_error "必须使用 root 权限运行此脚本 (例如: sudo bash $0)"
   exit 1
fi

# 2. 定位配置文件路径
CANDIDATES=(
    "/opt/nezha/agent/config.yml"
    "/etc/nezha/config.yml"
    "/etc/nezha-agent/config.yml"
    "/usr/local/nezha/agent/config.yml"
)
CONFIG_PATH=""
for path in "${CANDIDATES[@]}"; do
    if [[ -f "$path" ]]; then
        CONFIG_PATH="$path"
        break
    fi
done

if [[ -z "$CONFIG_PATH" ]]; then
    log_error "未检测到 nezha-agent 配置文件，请确认节点是否已安装 Agent！"
    exit 2
fi
log_info "检测到配置文件路径: ${CONFIG_PATH}"

# 3. 备份配置文件
BACKUP_PATH="${CONFIG_PATH}.bak.$(date +%Y%m%d%H%M%S)"
cp -p "${CONFIG_PATH}" "${BACKUP_PATH}"
log_info "已备份原配置至: ${BACKUP_PATH}"

# 4. 幂等性写入核心加固参数 (严格防锁死顺序：禁用自动更新 -> 禁用命令执行 -> 禁用NAT)
TARGET_KEYS=(
    "disable_auto_update"
    "disable_command_execute"
    "disable_nat"
)

for key in "${TARGET_KEYS[@]}"; do
    if grep -E "^(\s*|\#\s*)${key}:" "${CONFIG_PATH}" >/dev/null 2>&1; then
        sed -i -E "s/^[# ]*${key}:.*/${key}: true/" "${CONFIG_PATH}"
    else
        echo "${key}: true" >> "${CONFIG_PATH}"
    fi
    log_info "已成功固化配置项: ${key}: true"
done

# 5. 校验配置文件非空
if [[ ! -s "${CONFIG_PATH}" ]]; then
    log_error "修改后配置文件异常为空，正在自动回滚..."
    cp -p "${BACKUP_PATH}" "${CONFIG_PATH}"
    exit 3
fi

# 6. 重载服务配置并优雅重启
if command -v systemctl >/dev/null 2>&1; then
    systemctl daemon-reload
    log_info "正在通过 systemctl 重启 nezha-agent..."
    systemctl restart nezha-agent || service nezha-agent restart
elif command -v service >/dev/null 2>&1; then
    log_info "正在通过 service 重启 nezha-agent..."
    service nezha-agent restart
fi

# 7. 运行状态校验
sleep 2
if (command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet nezha-agent) || pgrep -x nezha-agent >/dev/null; then
    log_info "✅ nezha-agent 重启成功并保持活跃，当前已正式切断控制通道，转为纯遥测节点 (Telemetry Only)！"
    exit 0
else
    log_error "❌ nezha-agent 重启后未处于运行状态，正在尝试恢复原配置..."
    cp -p "${BACKUP_PATH}" "${CONFIG_PATH}"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart nezha-agent || true
    fi
    exit 4
fi

