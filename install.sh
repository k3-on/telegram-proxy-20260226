#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Telegram MTProto proxy one-click (interactive, i18n)
# - Ubuntu 22.04
# - EE (FakeTLS) via mtg
# - DD (padding) via telegrammessenger/proxy
# - User chooses ports, domains, language
# ============================================================

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root: sudo bash $0"
  exit 1
fi

# Pinned image references for reproducible deployment.
# You can override them with environment variables, for example:
#   MTG_IMAGE='nineseconds/mtg@sha256:<digest>' DD_IMAGE='telegrammessenger/proxy@sha256:<digest>' sudo -E bash install.sh
MTG_IMAGE="${MTG_IMAGE:-nineseconds/mtg@sha256:f0e90be754c59e729bc4e219eeb210a602f7ad4e39167833166a176cd6fa0461}"
DD_IMAGE="${DD_IMAGE:-telegrammessenger/proxy@sha256:73210d43c8f8e4c888ba4e30d6daf7742528e9134252a1cd538caabf5e24a597}"
DEPLOY_EE=0
DEPLOY_DD=0
CONFIG_DIR="/etc/telegram-proxy"
EE_ENV_FILE="${CONFIG_DIR}/ee.env"
DD_ENV_FILE="${CONFIG_DIR}/dd.env"
EE_SERVICE_NAME="telegram-proxy-ee.service"
DD_SERVICE_NAME="telegram-proxy-dd.service"
EE_CONTAINER_NAME="mtg-ee"
DD_CONTAINER_NAME="mtproto-dd"
BACKUP_DIR="/var/backups/telegram-proxy"
LOCK_FILE="/var/lock/telegram-proxy-install.lock"

# ---------- i18n ----------
UI_LANG="en"

select_language() {
  echo "Select language / 选择语言 / 언어 선택 / 言語を選択:"
  echo "1) English"
  echo "2) 中文"
  echo "3) 한국어"
  echo "4) 日本語"
  read -rp "> " choice
  case "${choice:-1}" in
    1) UI_LANG="en" ;;
    2) UI_LANG="zh" ;;
    3) UI_LANG="ko" ;;
    4) UI_LANG="ja" ;;
    *) UI_LANG="en" ;;
  esac
}

t() {
  local key="$1"
  case "$UI_LANG" in
    en)
      case "$key" in
        title) echo "Telegram proxy installer (EE+DD) — interactive" ;;
        need_dns) echo "Before you start: make sure your domains have A-records pointing to this VPS (DNS only, no CDN proxy)." ;;
        step_update) echo "Step: Updating system & installing basic tools (curl, openssl, ufw, dnsutils...)." ;;
        step_docker) echo "Step: Installing and enabling Docker (to run proxy services in containers)." ;;
        step_bbr_q) echo "Step: Optional network tuning (BBR + fq). This improves TCP throughput/latency on many links." ;;
        step_firewall) echo "Step: Configuring firewall (UFW) safely (allow SSH and chosen ports before enable)." ;;
        step_pull) echo "Step: Pulling Docker images for mtg (EE) and MTProxy (DD)." ;;
        step_front_test) echo "Step: Testing TLS handshake to your chosen fronting domain (FakeTLS needs a real HTTPS site)." ;;
        step_gen_ee) echo "Step: Generating EE (FakeTLS) secret and writing mtg config." ;;
        step_run_ee) echo "Step: Starting mtg (EE) on your chosen port." ;;
        step_gen_dd) echo "Step: Generating DD secret (padding mode)." ;;
        step_run_dd) echo "Step: Starting MTProxy (DD) on your chosen port." ;;
        step_dns_check) echo "Step: Checking entry domains DNS resolution." ;;
        step_summary) echo "Done. Below are the settings and one-click import links." ;;
        ask_mode) echo "Choose deployment mode:" ;;
        mode_ee_only) echo "EE only (FakeTLS via mtg)" ;;
        mode_dd_only) echo "DD only (padding via MTProxy)" ;;
        mode_both) echo "EE + DD (recommended dual-line)" ;;
        ask_ee_domain) echo "Enter entry domain for EE (example: ee.example.com): " ;;
        ask_dd_domain) echo "Enter entry domain for DD (example: dd.example.com): " ;;
        ask_front_domain) echo "Enter fronting domain for EE (default: www.cloudflare.com): " ;;
        ask_fronting_mode) echo "Choose fronting domain input mode:" ;;
        ask_ee_port) echo "Choose port for EE (recommended: 443). Enter a number: " ;;
        ask_dd_port) echo "Choose port for DD (recommended: 8443). Enter a number: " ;;
        ask_port_menu) echo "Choose a port option:" ;;
        opt_manual_input) echo "Manual input" ;;
        opt_recommended) echo "recommended" ;;
        ask_enable_bbr) echo "Enable BBR+fq (recommended) [Y/n]: " ;;
        ask_strict_ufw) echo "Enable strict UFW rules bound to selected IP(s) [y/N]: " ;;
        ask_continue_anyway) echo "Continue anyway? [y/N]: " ;;
        err_port_num) echo "Port must be a number between 1 and 65535." ;;
        err_port_conflict) echo "EE port and DD port cannot be the same on a single IP. Choose different ports." ;;
        err_port_in_use) echo "Port is already in use on this server. Choose another one." ;;
        warn_443_busy) echo "Selected port is already in use." ;;
        note_port_holders) echo "Current listeners on this port:" ;;
        ask_cleanup_proxy_443) echo "Try to stop old proxy containers and re-check this port? [y/N]: " ;;
        note_cleanup_done) echo "Cleanup attempted. Re-checking the selected port..." ;;
        warn_cleanup_unavailable) echo "Docker not found, cannot auto-clean old proxy containers." ;;
        warn_443_still_busy) echo "Selected port is still occupied after cleanup attempt." ;;
        err_empty) echo "This value cannot be empty." ;;
        err_choice_invalid) echo "Invalid choice. Please enter one of the listed numbers." ;;
        err_mode_invalid) echo "Invalid mode. Choose 1, 2, or 3." ;;
        err_domain_invalid) echo "Invalid domain format. Example: sub.example.com" ;;
        warn_dns_unresolved) echo "Warning: domain has no A record yet." ;;
        warn_dns_mismatch) echo "Warning: domain A records do not include this server IPv4." ;;
        warn_bbr_unsupported) echo "Warning: kernel does not advertise BBR support. Skipping BBR tuning." ;;
        warn_bbr_apply_fail) echo "Warning: failed to apply sysctl settings. Continuing without BBR changes." ;;
        tls_ok) echo "TLS handshake OK." ;;
        tls_fail) echo "TLS handshake FAILED or timed out. FakeTLS may be unstable with this fronting domain." ;;
        tls_abort) echo "Aborted because TLS check failed and user did not confirm continuation." ;;
        warn_front_fallback) echo "No fronting candidate passed TLS check. Falling back to the first candidate:" ;;
        note_secret) echo "Do NOT share secrets publicly. Anyone with the secret can use your proxy." ;;
        note_no_cdn) echo "Important: DNS should be 'DNS only' (no CDN proxy). MTProto is not standard HTTPS." ;;
        err_image_ref_invalid) echo "Image reference must be digest format: name@sha256:64hex. Please set MTG_IMAGE/DD_IMAGE." ;;
        menu_title) echo "Main Menu" ;;
        menu_install) echo "install" ;;
        menu_healthcheck) echo "healthcheck" ;;
        menu_self_heal) echo "self-heal" ;;
        menu_upgrade) echo "upgrade" ;;
        menu_self_update) echo "self-update" ;;
        menu_rotate_secret) echo "rotate-secret" ;;
        menu_uninstall) echo "uninstall" ;;
        menu_help) echo "help" ;;
        menu_exit) echo "exit" ;;
        ask_oper_mode) echo "Select mode:" ;;
        ask_rotate_mode) echo "Select rotate mode:" ;;
        ask_new_mtg_image) echo "Enter new MTG image digest (blank=keep current): " ;;
        ask_new_dd_image) echo "Enter new DD image digest (blank=keep current): " ;;
        ask_new_secret) echo "Enter new secret (blank=auto for EE): " ;;
        ask_front_for_auto_secret) echo "Enter front-domain for EE auto secret (blank=keep current): " ;;
        ask_bind_ip_mode) echo "Choose bind IP:" ;;
        opt_all_interfaces) echo "all interfaces, recommended" ;;
        opt_primary_ipv4) echo "primary IPv4" ;;
        opt_unavailable) echo "unavailable" ;;
        ask_bind_ipv4) echo "Enter bind IPv4 (or 0.0.0.0): " ;;
        err_primary_ipv4_unavailable) echo "Primary IPv4 unavailable." ;;
        err_ipv4_invalid) echo "Invalid IPv4 format." ;;
        err_bind_ip_not_found) echo "IP not found on this host." ;;
        step_self_update) echo "Step: Updating script repository (git pull --ff-only)." ;;
        err_self_update_not_git) echo "Self-update requires a git clone directory containing .git." ;;
        note_self_update_done) echo "Self-update completed." ;;
        note_self_update_rerun) echo "Run the installer again to apply new logic:" ;;
        menu_migrate) echo "migrate legacy" ;;
        menu_rollback) echo "rollback" ;;
        step_migrate) echo "Step: Migrating legacy running containers into script-managed systemd services." ;;
        step_backup) echo "Step: Creating backup before change." ;;
        step_rollback) echo "Step: Rolling back from backup." ;;
        ask_backup_id) echo "Enter backup ID (blank = latest): " ;;
        note_backup_saved) echo "Backup saved:" ;;
        note_backup_latest) echo "Using latest backup:" ;;
        note_backup_none) echo "No backups found." ;;
        note_rollback_done) echo "Rollback completed." ;;
        err_backup_not_found) echo "Backup ID not found." ;;
        err_lock_busy) echo "Another install.sh process is running. Try again later." ;;
        err_lock_unavailable) echo "flock is unavailable; cannot enforce single-run lock." ;;
        err_migrate_no_legacy) echo "No legacy proxy containers found to migrate." ;;
        err_legacy_container_missing) echo "Required legacy container is missing." ;;
        note_migrate_done) echo "Migration completed and services are now managed by systemd." ;;
        ask_existing_ee_secret) echo "Enter existing EE secret (ee...hex): " ;;
        err_ee_secret_required) echo "EE secret is required for migration." ;;
        warn_image_not_digest) echo "Current image is not digest-pinned. Falling back to default pinned digest." ;;
        note_using_digest) echo "Using digest image:" ;;
        note_recent_logs) echo "Recent container logs:" ;;
        warn_service_restarts) echo "Service restart count is high:" ;;
        warn_container_restarts) echo "Container restart count is high:" ;;
        err_port_binding_mismatch) echo "Container port binding does not match configured bind IP/port." ;;
        err_unknown_arg) echo "Unknown argument:" ;;
        err_unknown_cmd) echo "Unknown command:" ;;
        err_rotate_mode_required) echo "rotate-secret requires --mode ee|dd" ;;
        err_mode_value_invalid) echo "Invalid mode value:" ;;
        err_not_installed_ee) echo "EE is not installed." ;;
        err_not_installed_dd) echo "DD is not installed." ;;
        err_invalid_mtg_image) echo "Invalid MTG image digest:" ;;
        err_invalid_dd_image) echo "Invalid DD image digest:" ;;
        err_invalid_ee_secret) echo "Invalid EE secret format (expected ee... hex)." ;;
        err_invalid_dd_secret) echo "Invalid DD secret format." ;;
        err_migrate_port_missing) echo "Cannot detect host port binding from legacy container." ;;
        note_legacy_detected) echo "legacy deployment detected: container is running, but env is missing" ;;
        note_legacy_migrate) echo "run migrate/install to bring this instance under script management" ;;
        ask_new_ee_secret_cli) echo "Enter new EE secret (hex). Leave empty to auto-generate: " ;;
        ask_new_dd_secret_cli) echo "Enter new DD secret (32-hex or dd+32-hex): " ;;
        note_attempt_restart_ee) echo "[ee] attempting restart..." ;;
        note_attempt_restart_dd) echo "[dd] attempting restart..." ;;
        hc_not_installed) echo "not installed (env missing)" ;;
        hc_service_not_active) echo "service not active" ;;
        hc_container_not_running) echo "container not running" ;;
        hc_port_not_listening) echo "port not listening" ;;
        hc_image_mismatch) echo "image mismatch" ;;
        hc_healthy) echo "healthy" ;;
        critical_need_systemctl) echo "Critical: systemctl is required." ;;
        critical_need_apt) echo "Critical: apt-get is required." ;;
        preflight_warnings) echo "Preflight warnings:" ;;
        aborted_by_user) echo "Aborted by user." ;;
      esac
      ;;
    zh)
      case "$key" in
        title) echo "Telegram 代理一键部署（EE+DD）— 交互式" ;;
        need_dns) echo "开始前提示：请确保域名 A 记录已指向本 VPS（DNS only/灰云，不要走 CDN 代理）。" ;;
        step_update) echo "步骤：更新系统并安装基础工具（curl、openssl、ufw、dnsutils 等）。" ;;
        step_docker) echo "步骤：安装并启用 Docker（用容器方式运行代理服务，隔离且易维护）。" ;;
        step_bbr_q) echo "步骤：可选网络优化（BBR + fq）。常见情况下可提升 TCP 吞吐与稳定性。" ;;
        step_firewall) echo "步骤：安全配置防火墙（UFW）：先放行 SSH 和代理端口，再启用。" ;;
        step_pull) echo "步骤：拉取 Docker 镜像（mtg 用于 EE，MTProxy 用于 DD）。" ;;
        step_front_test) echo "步骤：测试 fronting 域名的 TLS 握手（FakeTLS 需要一个真正可用的 HTTPS 站点）。" ;;
        step_gen_ee) echo "步骤：生成 EE（FakeTLS）密钥并写入 mtg 配置。" ;;
        step_run_ee) echo "步骤：启动 mtg（EE）并监听你选择的端口。" ;;
        step_gen_dd) echo "步骤：生成 DD（padding）密钥（用于兜底线路）。" ;;
        step_run_dd) echo "步骤：启动 MTProxy（DD）并监听你选择的端口。" ;;
        step_dns_check) echo "步骤：检查入口域名 DNS 解析情况。" ;;
        step_summary) echo "完成。下面输出配置与一键导入链接。" ;;
        ask_mode) echo "请选择部署模式：" ;;
        mode_ee_only) echo "仅 EE（FakeTLS / mtg）" ;;
        mode_dd_only) echo "仅 DD（padding / MTProxy）" ;;
        mode_both) echo "EE + DD（双线路，推荐）" ;;
        ask_ee_domain) echo "请输入 EE 入口域名（例如：ee.example.com）： " ;;
        ask_dd_domain) echo "请输入 DD 入口域名（例如：dd.example.com）： " ;;
        ask_front_domain) echo "请输入 EE 的 fronting 域名（默认：www.cloudflare.com）： " ;;
        ask_fronting_mode) echo "请选择 fronting 域名输入方式：" ;;
        ask_ee_port) echo "请选择 EE 端口（推荐 443）。请输入端口号： " ;;
        ask_dd_port) echo "请选择 DD 端口（推荐 8443）。请输入端口号： " ;;
        ask_port_menu) echo "请选择端口选项：" ;;
        opt_manual_input) echo "手动输入" ;;
        opt_recommended) echo "推荐" ;;
        ask_enable_bbr) echo "是否启用 BBR+fq（推荐）[Y/n]： " ;;
        ask_strict_ufw) echo "是否启用严格 UFW 规则（按所选 IP 放行）[y/N]： " ;;
        ask_continue_anyway) echo "是否仍继续？[y/N]： " ;;
        err_port_num) echo "端口必须是 1~65535 的数字。" ;;
        err_port_conflict) echo "同一台机器的同一个 IP 上，EE 和 DD 不能使用同一个端口。请选不同端口。" ;;
        err_port_in_use) echo "该端口在本机已被占用。请换一个端口。" ;;
        warn_443_busy) echo "所选端口已被占用。" ;;
        note_port_holders) echo "当前占用该端口的监听项：" ;;
        ask_cleanup_proxy_443) echo "是否尝试停止旧代理容器并重新检测该端口？[y/N]： " ;;
        note_cleanup_done) echo "已尝试清理，正在重新检测所选端口..." ;;
        warn_cleanup_unavailable) echo "未检测到 Docker，无法自动清理旧代理容器。" ;;
        warn_443_still_busy) echo "清理后该端口仍被占用。" ;;
        err_empty) echo "该项不能为空。" ;;
        err_choice_invalid) echo "选项无效，请输入列表中的数字。" ;;
        err_mode_invalid) echo "模式输入无效，请输入 1、2 或 3。" ;;
        err_domain_invalid) echo "域名格式不合法，例如：sub.example.com" ;;
        warn_dns_unresolved) echo "警告：该域名当前没有 A 记录。" ;;
        warn_dns_mismatch) echo "警告：该域名的 A 记录未包含本机 IPv4。" ;;
        warn_bbr_unsupported) echo "警告：当前内核未显示支持 BBR，跳过 BBR 配置。" ;;
        warn_bbr_apply_fail) echo "警告：sysctl 配置应用失败，将继续但不保证 BBR 生效。" ;;
        tls_ok) echo "TLS 握手正常。" ;;
        tls_fail) echo "TLS 握手失败或超时。FakeTLS 可能不稳定，建议更换 fronting 域名。" ;;
        tls_abort) echo "由于 TLS 检测失败且未确认继续，脚本已中止。" ;;
        warn_front_fallback) echo "所有候选 fronting 域名 TLS 检测都失败，将回退到第一个候选：" ;;
        note_secret) echo "不要公开分享 secret。任何拿到 secret 的人都能使用你的代理。" ;;
        note_no_cdn) echo "重要：DNS 必须是 DNS only/灰云（不要 CDN 代理）。MTProto 不是标准 HTTPS。" ;;
        err_image_ref_invalid) echo "镜像引用必须是 digest 格式：name@sha256:64位十六进制。请设置 MTG_IMAGE/DD_IMAGE。" ;;
        menu_title) echo "主菜单" ;;
        menu_install) echo "安装" ;;
        menu_healthcheck) echo "健康检查" ;;
        menu_self_heal) echo "自愈" ;;
        menu_upgrade) echo "升级" ;;
        menu_self_update) echo "脚本自更新" ;;
        menu_rotate_secret) echo "轮换密钥" ;;
        menu_uninstall) echo "卸载" ;;
        menu_help) echo "帮助" ;;
        menu_exit) echo "退出" ;;
        ask_oper_mode) echo "请选择模式：" ;;
        ask_rotate_mode) echo "请选择轮换模式：" ;;
        ask_new_mtg_image) echo "请输入新的 MTG 镜像 digest（留空=保持当前）： " ;;
        ask_new_dd_image) echo "请输入新的 DD 镜像 digest（留空=保持当前）： " ;;
        ask_new_secret) echo "请输入新 secret（留空=EE 自动生成）： " ;;
        ask_front_for_auto_secret) echo "请输入 EE 自动生成 secret 的 front-domain（留空=保持当前）： " ;;
        ask_bind_ip_mode) echo "请选择绑定 IP：" ;;
        opt_all_interfaces) echo "全部网卡，推荐" ;;
        opt_primary_ipv4) echo "主 IPv4" ;;
        opt_unavailable) echo "不可用" ;;
        ask_bind_ipv4) echo "请输入绑定 IPv4（或 0.0.0.0）： " ;;
        err_primary_ipv4_unavailable) echo "主 IPv4 不可用。" ;;
        err_ipv4_invalid) echo "IPv4 格式无效。" ;;
        err_bind_ip_not_found) echo "该 IP 不在本机网卡上。" ;;
        step_self_update) echo "步骤：更新脚本仓库（git pull --ff-only）。" ;;
        err_self_update_not_git) echo "脚本自更新需要在包含 .git 的仓库目录中执行。" ;;
        note_self_update_done) echo "脚本自更新完成。" ;;
        note_self_update_rerun) echo "请重新执行安装脚本以应用新逻辑：" ;;
        menu_migrate) echo "迁移旧部署" ;;
        menu_rollback) echo "回滚" ;;
        step_migrate) echo "步骤：将正在运行的旧容器迁移为脚本托管的 systemd 服务。" ;;
        step_backup) echo "步骤：变更前创建备份。" ;;
        step_rollback) echo "步骤：从备份执行回滚。" ;;
        ask_backup_id) echo "请输入备份 ID（留空=最新）： " ;;
        note_backup_saved) echo "备份已保存：" ;;
        note_backup_latest) echo "使用最新备份：" ;;
        note_backup_none) echo "未找到备份。" ;;
        note_rollback_done) echo "回滚完成。" ;;
        err_backup_not_found) echo "未找到该备份 ID。" ;;
        err_lock_busy) echo "已有另一个 install.sh 正在运行，请稍后重试。" ;;
        err_lock_unavailable) echo "系统缺少 flock，无法启用单实例运行锁。" ;;
        err_migrate_no_legacy) echo "未发现可迁移的旧代理容器。" ;;
        err_legacy_container_missing) echo "缺少需要迁移的旧容器。" ;;
        note_migrate_done) echo "迁移完成，服务已纳入 systemd 托管。" ;;
        ask_existing_ee_secret) echo "请输入现有 EE secret（ee...hex）： " ;;
        err_ee_secret_required) echo "迁移需要 EE secret，不能为空。" ;;
        warn_image_not_digest) echo "当前镜像不是 digest 固定形式，将回退到脚本默认 digest。" ;;
        note_using_digest) echo "使用镜像 digest：" ;;
        note_recent_logs) echo "最近容器日志：" ;;
        warn_service_restarts) echo "服务重启次数偏高：" ;;
        warn_container_restarts) echo "容器重启次数偏高：" ;;
        err_port_binding_mismatch) echo "容器端口绑定与配置的绑定 IP/端口不一致。" ;;
        err_unknown_arg) echo "未知参数：" ;;
        err_unknown_cmd) echo "未知命令：" ;;
        err_rotate_mode_required) echo "rotate-secret 必须指定 --mode ee|dd" ;;
        err_mode_value_invalid) echo "模式值无效：" ;;
        err_not_installed_ee) echo "EE 尚未安装。" ;;
        err_not_installed_dd) echo "DD 尚未安装。" ;;
        err_invalid_mtg_image) echo "MTG 镜像 digest 无效：" ;;
        err_invalid_dd_image) echo "DD 镜像 digest 无效：" ;;
        err_invalid_ee_secret) echo "EE secret 格式无效（应为 ee... 十六进制）。" ;;
        err_invalid_dd_secret) echo "DD secret 格式无效。" ;;
        err_migrate_port_missing) echo "无法从旧容器识别主机端口绑定。" ;;
        note_legacy_detected) echo "发现旧部署：容器在运行，但 env 文件缺失" ;;
        note_legacy_migrate) echo "请运行 migrate/install 将该实例纳入脚本托管" ;;
        ask_new_ee_secret_cli) echo "请输入新的 EE secret（hex，留空=自动生成）： " ;;
        ask_new_dd_secret_cli) echo "请输入新的 DD secret（32hex 或 dd+32hex）： " ;;
        note_attempt_restart_ee) echo "[ee] 正在尝试重启..." ;;
        note_attempt_restart_dd) echo "[dd] 正在尝试重启..." ;;
        hc_not_installed) echo "未安装（缺少 env 文件）" ;;
        hc_service_not_active) echo "服务未运行" ;;
        hc_container_not_running) echo "容器未运行" ;;
        hc_port_not_listening) echo "端口未监听" ;;
        hc_image_mismatch) echo "镜像不匹配" ;;
        hc_healthy) echo "健康" ;;
        critical_need_systemctl) echo "关键错误：需要 systemctl。" ;;
        critical_need_apt) echo "关键错误：需要 apt-get。" ;;
        preflight_warnings) echo "前置检查警告：" ;;
        aborted_by_user) echo "用户已中止。" ;;
      esac
      ;;
    ko)
      case "$key" in
        title) echo "Telegram 프록시 설치(EE+DD) — 대화형" ;;
        need_dns) echo "시작 전: 도메인 A 레코드가 이 VPS를 가리키는지 확인하세요(DNS only, CDN 프록시 사용 금지)." ;;
        step_update) echo "단계: 시스템 업데이트 및 기본 도구 설치(curl, openssl, ufw, dnsutils...)." ;;
        step_docker) echo "단계: Docker 설치 및 활성화(컨테이너로 프록시 실행)." ;;
        step_bbr_q) echo "단계: (선택) 네트워크 튜닝(BBR + fq)." ;;
        step_firewall) echo "단계: 안전한 방화벽(UFW) 설정(먼저 SSH/프록시 포트 허용 후 활성화)." ;;
        step_pull) echo "단계: Docker 이미지 다운로드(mtg=EE, MTProxy=DD)." ;;
        step_front_test) echo "단계: 프론팅 도메인의 TLS 핸드셰이크 테스트." ;;
        step_gen_ee) echo "단계: EE(FakeTLS) 시크릿 생성 및 mtg 설정 작성." ;;
        step_run_ee) echo "단계: mtg(EE) 실행." ;;
        step_gen_dd) echo "단계: DD(padding) 시크릿 생성." ;;
        step_run_dd) echo "단계: MTProxy(DD) 실행." ;;
        step_dns_check) echo "단계: 접속 도메인 DNS 확인." ;;
        step_summary) echo "완료. 아래에 설정과 가져오기 링크를 출력합니다." ;;
        ask_mode) echo "배포 모드를 선택하세요:" ;;
        mode_ee_only) echo "EE만 (FakeTLS / mtg)" ;;
        mode_dd_only) echo "DD만 (padding / MTProxy)" ;;
        mode_both) echo "EE + DD (이중 라인, 권장)" ;;
        ask_ee_domain) echo "EE 접속 도메인 입력(예: ee.example.com): " ;;
        ask_dd_domain) echo "DD 접속 도메인 입력(예: dd.example.com): " ;;
        ask_front_domain) echo "EE 프론팅 도메인 입력(기본: www.cloudflare.com): " ;;
        ask_fronting_mode) echo "프론팅 도메인 입력 방식을 선택하세요:" ;;
        ask_ee_port) echo "EE 포트 선택(권장: 443). 포트 번호 입력: " ;;
        ask_dd_port) echo "DD 포트 선택(권장: 8443). 포트 번호 입력: " ;;
        ask_port_menu) echo "포트 옵션을 선택하세요:" ;;
        opt_manual_input) echo "수동 입력" ;;
        opt_recommended) echo "권장" ;;
        ask_enable_bbr) echo "BBR+fq 활성화(권장) [Y/n]: " ;;
        ask_strict_ufw) echo "선택한 IP에만 적용되는 엄격한 UFW 규칙을 사용할까요? [y/N]: " ;;
        ask_continue_anyway) echo "계속 진행할까요? [y/N]: " ;;
        err_port_num) echo "포트는 1~65535 사이의 숫자여야 합니다." ;;
        err_port_conflict) echo "같은 IP에서 EE와 DD는 동일 포트를 사용할 수 없습니다." ;;
        err_port_in_use) echo "해당 포트가 이미 사용 중입니다." ;;
        warn_443_busy) echo "선택한 포트가 이미 사용 중입니다." ;;
        note_port_holders) echo "현재 이 포트를 점유 중인 리스너:" ;;
        ask_cleanup_proxy_443) echo "기존 프록시 컨테이너를 중지하고 이 포트를 다시 확인할까요? [y/N]: " ;;
        note_cleanup_done) echo "정리 시도 완료. 선택한 포트를 다시 확인합니다..." ;;
        warn_cleanup_unavailable) echo "Docker가 없어 기존 프록시 컨테이너 자동 정리를 할 수 없습니다." ;;
        warn_443_still_busy) echo "정리 후에도 선택한 포트가 여전히 점유 중입니다." ;;
        err_empty) echo "빈 값은 허용되지 않습니다." ;;
        err_choice_invalid) echo "선택이 잘못되었습니다. 목록의 번호를 입력하세요." ;;
        err_mode_invalid) echo "모드 입력이 잘못되었습니다. 1, 2, 3 중에서 선택하세요." ;;
        err_domain_invalid) echo "도메인 형식이 올바르지 않습니다. 예: sub.example.com" ;;
        warn_dns_unresolved) echo "경고: 도메인에 A 레코드가 없습니다." ;;
        warn_dns_mismatch) echo "경고: 도메인 A 레코드에 서버 IPv4가 없습니다." ;;
        warn_bbr_unsupported) echo "경고: 커널에서 BBR 지원이 확인되지 않아 건너뜁니다." ;;
        warn_bbr_apply_fail) echo "경고: sysctl 적용 실패. BBR 없이 계속 진행합니다." ;;
        tls_ok) echo "TLS 핸드셰이크 OK." ;;
        tls_fail) echo "TLS 핸드셰이크 실패/타임아웃." ;;
        tls_abort) echo "TLS 검사 실패 후 계속 확인이 없어 중단합니다." ;;
        warn_front_fallback) echo "모든 프론팅 후보의 TLS 검사에 실패했습니다. 첫 번째 후보로 진행합니다:" ;;
        note_secret) echo "시크릿을 공개 공유하지 마세요." ;;
        note_no_cdn) echo "중요: DNS only(프록시/CDN 금지)." ;;
        err_image_ref_invalid) echo "이미지 참조는 digest 형식(name@sha256:64hex)이어야 합니다. MTG_IMAGE/DD_IMAGE를 설정하세요." ;;
        menu_title) echo "메인 메뉴" ;;
        menu_install) echo "설치" ;;
        menu_healthcheck) echo "상태 점검" ;;
        menu_self_heal) echo "자동 복구" ;;
        menu_upgrade) echo "업그레이드" ;;
        menu_self_update) echo "스크립트 자체 업데이트" ;;
        menu_rotate_secret) echo "시크릿 교체" ;;
        menu_uninstall) echo "제거" ;;
        menu_help) echo "도움말" ;;
        menu_exit) echo "종료" ;;
        ask_oper_mode) echo "모드를 선택하세요:" ;;
        ask_rotate_mode) echo "시크릿 교체 모드를 선택하세요:" ;;
        ask_new_mtg_image) echo "새 MTG 이미지 digest 입력 (빈값=현재 유지): " ;;
        ask_new_dd_image) echo "새 DD 이미지 digest 입력 (빈값=현재 유지): " ;;
        ask_new_secret) echo "새 시크릿 입력 (빈값=EE 자동 생성): " ;;
        ask_front_for_auto_secret) echo "EE 자동 시크릿용 front-domain 입력 (빈값=현재 유지): " ;;
        ask_bind_ip_mode) echo "바인드 IP를 선택하세요:" ;;
        opt_all_interfaces) echo "모든 인터페이스, 권장" ;;
        opt_primary_ipv4) echo "기본 IPv4" ;;
        opt_unavailable) echo "사용 불가" ;;
        ask_bind_ipv4) echo "바인드 IPv4 입력(또는 0.0.0.0): " ;;
        err_primary_ipv4_unavailable) echo "기본 IPv4를 사용할 수 없습니다." ;;
        err_ipv4_invalid) echo "IPv4 형식이 올바르지 않습니다." ;;
        err_bind_ip_not_found) echo "이 호스트에서 해당 IP를 찾을 수 없습니다." ;;
        step_self_update) echo "단계: 스크립트 저장소 업데이트(git pull --ff-only)." ;;
        err_self_update_not_git) echo "self-update는 .git 이 있는 git clone 디렉터리에서만 가능합니다." ;;
        note_self_update_done) echo "스크립트 자체 업데이트가 완료되었습니다." ;;
        note_self_update_rerun) echo "새 로직 적용을 위해 설치 스크립트를 다시 실행하세요:" ;;
        menu_migrate) echo "레거시 마이그레이션" ;;
        menu_rollback) echo "롤백" ;;
        step_migrate) echo "단계: 실행 중인 레거시 컨테이너를 systemd 관리 서비스로 마이그레이션." ;;
        step_backup) echo "단계: 변경 전 백업 생성." ;;
        step_rollback) echo "단계: 백업에서 롤백 수행." ;;
        ask_backup_id) echo "백업 ID 입력 (빈값=최신): " ;;
        note_backup_saved) echo "백업 저장됨:" ;;
        note_backup_latest) echo "최신 백업 사용:" ;;
        note_backup_none) echo "백업이 없습니다." ;;
        note_rollback_done) echo "롤백 완료." ;;
        err_backup_not_found) echo "해당 백업 ID를 찾을 수 없습니다." ;;
        err_lock_busy) echo "다른 install.sh 프로세스가 실행 중입니다. 잠시 후 다시 시도하세요." ;;
        err_lock_unavailable) echo "flock 명령이 없어 단일 실행 잠금을 적용할 수 없습니다." ;;
        err_migrate_no_legacy) echo "마이그레이션할 레거시 프록시 컨테이너가 없습니다." ;;
        err_legacy_container_missing) echo "필수 레거시 컨테이너가 없습니다." ;;
        note_migrate_done) echo "마이그레이션 완료. 서비스가 systemd 관리로 전환되었습니다." ;;
        ask_existing_ee_secret) echo "기존 EE 시크릿 입력 (ee...hex): " ;;
        err_ee_secret_required) echo "마이그레이션에는 EE 시크릿이 필요합니다." ;;
        warn_image_not_digest) echo "현재 이미지는 digest 고정이 아닙니다. 기본 고정 digest로 대체합니다." ;;
        note_using_digest) echo "사용할 digest 이미지:" ;;
        note_recent_logs) echo "최근 컨테이너 로그:" ;;
        warn_service_restarts) echo "서비스 재시작 횟수가 높습니다:" ;;
        warn_container_restarts) echo "컨테이너 재시작 횟수가 높습니다:" ;;
        err_port_binding_mismatch) echo "컨테이너 포트 바인딩이 설정된 IP/포트와 다릅니다." ;;
        err_unknown_arg) echo "알 수 없는 인자:" ;;
        err_unknown_cmd) echo "알 수 없는 명령:" ;;
        err_rotate_mode_required) echo "rotate-secret는 --mode ee|dd가 필요합니다." ;;
        err_mode_value_invalid) echo "잘못된 모드 값:" ;;
        err_not_installed_ee) echo "EE가 설치되어 있지 않습니다." ;;
        err_not_installed_dd) echo "DD가 설치되어 있지 않습니다." ;;
        err_invalid_mtg_image) echo "잘못된 MTG 이미지 digest:" ;;
        err_invalid_dd_image) echo "잘못된 DD 이미지 digest:" ;;
        err_invalid_ee_secret) echo "EE 시크릿 형식이 잘못되었습니다(ee... hex)." ;;
        err_invalid_dd_secret) echo "DD 시크릿 형식이 잘못되었습니다." ;;
        err_migrate_port_missing) echo "레거시 컨테이너에서 호스트 포트 바인딩을 감지할 수 없습니다." ;;
        note_legacy_detected) echo "레거시 배포 감지: 컨테이너는 실행 중이지만 env 파일이 없습니다" ;;
        note_legacy_migrate) echo "migrate/install로 이 인스턴스를 스크립트 관리로 전환하세요" ;;
        ask_new_ee_secret_cli) echo "새 EE 시크릿 입력(hex, 빈값=자동 생성): " ;;
        ask_new_dd_secret_cli) echo "새 DD 시크릿 입력(32hex 또는 dd+32hex): " ;;
        note_attempt_restart_ee) echo "[ee] 재시작 시도 중..." ;;
        note_attempt_restart_dd) echo "[dd] 재시작 시도 중..." ;;
        hc_not_installed) echo "설치되지 않음(env 파일 없음)" ;;
        hc_service_not_active) echo "서비스 비활성" ;;
        hc_container_not_running) echo "컨테이너 미실행" ;;
        hc_port_not_listening) echo "포트 미청취" ;;
        hc_image_mismatch) echo "이미지 불일치" ;;
        hc_healthy) echo "정상" ;;
        critical_need_systemctl) echo "치명적 오류: systemctl 이 필요합니다." ;;
        critical_need_apt) echo "치명적 오류: apt-get 이 필요합니다." ;;
        preflight_warnings) echo "사전 점검 경고:" ;;
        aborted_by_user) echo "사용자에 의해 중단되었습니다." ;;
      esac
      ;;
    ja)
      case "$key" in
        title) echo "Telegram プロキシ導入（EE+DD）— 対話式" ;;
        need_dns) echo "開始前：ドメインのAレコードがこのVPSを指していることを確認してください（DNS only、CDNプロキシ禁止）。" ;;
        step_update) echo "手順：システム更新と基本ツール導入（curl、openssl、ufw、dnsutils等）。" ;;
        step_docker) echo "手順：Dockerのインストールと有効化。" ;;
        step_bbr_q) echo "手順：（任意）ネットワーク調整（BBR + fq）。" ;;
        step_firewall) echo "手順：安全なUFW設定（先にSSH/プロキシポート許可、その後有効化）。" ;;
        step_pull) echo "手順：Dockerイメージ取得（mtg=EE、MTProxy=DD）。" ;;
        step_front_test) echo "手順：frontingドメインのTLSハンドシェイク確認。" ;;
        step_gen_ee) echo "手順：EE（FakeTLS）シークレット生成とmtg設定作成。" ;;
        step_run_ee) echo "手順：mtg（EE）起動。" ;;
        step_gen_dd) echo "手順：DD（padding）シークレット生成。" ;;
        step_run_dd) echo "手順：MTProxy（DD）起動。" ;;
        step_dns_check) echo "手順：接続ドメインのDNS確認。" ;;
        step_summary) echo "完了。設定とワンクリック導入リンクを表示します。" ;;
        ask_mode) echo "デプロイモードを選択してください:" ;;
        mode_ee_only) echo "EEのみ (FakeTLS / mtg)" ;;
        mode_dd_only) echo "DDのみ (padding / MTProxy)" ;;
        mode_both) echo "EE + DD（デュアル運用、推奨）" ;;
        ask_ee_domain) echo "EEの接続ドメイン（例：ee.example.com）: " ;;
        ask_dd_domain) echo "DDの接続ドメイン（例：dd.example.com）: " ;;
        ask_front_domain) echo "EEのfrontingドメイン（既定：www.cloudflare.com）: " ;;
        ask_fronting_mode) echo "frontingドメインの入力方式を選択してください:" ;;
        ask_ee_port) echo "EEのポート（推奨: 443）。番号を入力: " ;;
        ask_dd_port) echo "DDのポート（推奨: 8443）。番号を入力: " ;;
        ask_port_menu) echo "ポートオプションを選択してください:" ;;
        opt_manual_input) echo "手動入力" ;;
        opt_recommended) echo "推奨" ;;
        ask_enable_bbr) echo "BBR+fqを有効化（推奨）[Y/n]: " ;;
        ask_strict_ufw) echo "選択したIPに限定する厳格なUFWルールを有効化しますか？ [y/N]: " ;;
        ask_continue_anyway) echo "このまま続行しますか？ [y/N]: " ;;
        err_port_num) echo "ポートは1〜65535の数字である必要があります。" ;;
        err_port_conflict) echo "同一IPではEEとDDを同じポートにできません。" ;;
        err_port_in_use) echo "そのポートは既に使用中です。" ;;
        warn_443_busy) echo "選択したポートは既に使用中です。" ;;
        note_port_holders) echo "現在このポートで待受しているプロセス:" ;;
        ask_cleanup_proxy_443) echo "旧プロキシコンテナを停止してこのポートを再確認しますか？ [y/N]: " ;;
        note_cleanup_done) echo "クリーンアップを試行しました。選択ポートを再確認します..." ;;
        warn_cleanup_unavailable) echo "Dockerが見つからないため旧プロキシコンテナを自動停止できません。" ;;
        warn_443_still_busy) echo "クリーンアップ後も選択ポートは使用中です。" ;;
        err_empty) echo "空欄は不可です。" ;;
        err_choice_invalid) echo "選択が不正です。表示された番号を入力してください。" ;;
        err_mode_invalid) echo "モード入力が不正です。1、2、3から選択してください。" ;;
        err_domain_invalid) echo "ドメイン形式が不正です。例: sub.example.com" ;;
        warn_dns_unresolved) echo "警告：ドメインにAレコードがありません。" ;;
        warn_dns_mismatch) echo "警告：ドメインAレコードにこのサーバーIPv4がありません。" ;;
        warn_bbr_unsupported) echo "警告：カーネルがBBR対応を示していないためスキップします。" ;;
        warn_bbr_apply_fail) echo "警告：sysctl適用に失敗。BBR変更なしで続行します。" ;;
        tls_ok) echo "TLSハンドシェイクOK。" ;;
        tls_fail) echo "TLSハンドシェイク失敗/タイムアウト。" ;;
        tls_abort) echo "TLS確認失敗かつ続行確認なしのため中止しました。" ;;
        warn_front_fallback) echo "全候補のTLS確認に失敗しました。先頭候補で続行します:" ;;
        note_secret) echo "シークレットを公開しないでください。" ;;
        note_no_cdn) echo "重要：DNSはDNS only（CDNプロキシ禁止）。" ;;
        err_image_ref_invalid) echo "イメージ参照はdigest形式(name@sha256:64hex)である必要があります。MTG_IMAGE/DD_IMAGEを設定してください。" ;;
        menu_title) echo "メインメニュー" ;;
        menu_install) echo "インストール" ;;
        menu_healthcheck) echo "ヘルスチェック" ;;
        menu_self_heal) echo "自動復旧" ;;
        menu_upgrade) echo "アップグレード" ;;
        menu_self_update) echo "スクリプト自己更新" ;;
        menu_rotate_secret) echo "シークレット更新" ;;
        menu_uninstall) echo "アンインストール" ;;
        menu_help) echo "ヘルプ" ;;
        menu_exit) echo "終了" ;;
        ask_oper_mode) echo "モードを選択してください:" ;;
        ask_rotate_mode) echo "シークレット更新モードを選択してください:" ;;
        ask_new_mtg_image) echo "新しいMTGイメージdigestを入力（空欄=現状維持）: " ;;
        ask_new_dd_image) echo "新しいDDイメージdigestを入力（空欄=現状維持）: " ;;
        ask_new_secret) echo "新しいシークレットを入力（空欄=EE自動生成）: " ;;
        ask_front_for_auto_secret) echo "EE自動生成用front-domainを入力（空欄=現状維持）: " ;;
        ask_bind_ip_mode) echo "バインドIPを選択してください:" ;;
        opt_all_interfaces) echo "全インターフェース、推奨" ;;
        opt_primary_ipv4) echo "プライマリIPv4" ;;
        opt_unavailable) echo "利用不可" ;;
        ask_bind_ipv4) echo "バインドIPv4を入力（または0.0.0.0）: " ;;
        err_primary_ipv4_unavailable) echo "プライマリIPv4は利用できません。" ;;
        err_ipv4_invalid) echo "IPv4形式が不正です。" ;;
        err_bind_ip_not_found) echo "このホストにそのIPはありません。" ;;
        step_self_update) echo "手順：スクリプトリポジトリを更新（git pull --ff-only）。" ;;
        err_self_update_not_git) echo "self-update は .git を含む git clone ディレクトリで実行する必要があります。" ;;
        note_self_update_done) echo "スクリプト自己更新が完了しました。" ;;
        note_self_update_rerun) echo "新しいロジックを適用するには再実行してください:" ;;
        menu_migrate) echo "旧構成を移行" ;;
        menu_rollback) echo "ロールバック" ;;
        step_migrate) echo "手順：稼働中の旧コンテナを script 管理の systemd サービスへ移行。" ;;
        step_backup) echo "手順：変更前バックアップを作成。" ;;
        step_rollback) echo "手順：バックアップからロールバック。" ;;
        ask_backup_id) echo "バックアップIDを入力（空欄=最新）: " ;;
        note_backup_saved) echo "バックアップ保存先:" ;;
        note_backup_latest) echo "最新バックアップを使用:" ;;
        note_backup_none) echo "バックアップがありません。" ;;
        note_rollback_done) echo "ロールバック完了。" ;;
        err_backup_not_found) echo "指定したバックアップIDが見つかりません。" ;;
        err_lock_busy) echo "別の install.sh プロセスが実行中です。しばらくして再試行してください。" ;;
        err_lock_unavailable) echo "flock が無いため単一起動ロックを有効化できません。" ;;
        err_migrate_no_legacy) echo "移行対象の旧プロキシコンテナが見つかりません。" ;;
        err_legacy_container_missing) echo "必要な旧コンテナが見つかりません。" ;;
        note_migrate_done) echo "移行が完了し、systemd 管理に切り替わりました。" ;;
        ask_existing_ee_secret) echo "既存EEシークレットを入力（ee...hex）: " ;;
        err_ee_secret_required) echo "移行にはEEシークレットが必要です。" ;;
        warn_image_not_digest) echo "現在のイメージはdigest固定ではないため、既定の固定digestへフォールバックします。" ;;
        note_using_digest) echo "使用するdigestイメージ:" ;;
        note_recent_logs) echo "直近のコンテナログ:" ;;
        warn_service_restarts) echo "サービス再起動回数が高めです:" ;;
        warn_container_restarts) echo "コンテナ再起動回数が高めです:" ;;
        err_port_binding_mismatch) echo "コンテナのポートバインドが設定IP/ポートと一致しません。" ;;
        err_unknown_arg) echo "不明な引数:" ;;
        err_unknown_cmd) echo "不明なコマンド:" ;;
        err_rotate_mode_required) echo "rotate-secret には --mode ee|dd が必要です" ;;
        err_mode_value_invalid) echo "モード値が不正です:" ;;
        err_not_installed_ee) echo "EE は未インストールです。" ;;
        err_not_installed_dd) echo "DD は未インストールです。" ;;
        err_invalid_mtg_image) echo "MTG イメージdigestが不正です:" ;;
        err_invalid_dd_image) echo "DD イメージdigestが不正です:" ;;
        err_invalid_ee_secret) echo "EEシークレット形式が不正です（ee... hex）。" ;;
        err_invalid_dd_secret) echo "DDシークレット形式が不正です。" ;;
        err_migrate_port_missing) echo "旧コンテナからホスト側ポートバインドを検出できません。" ;;
        note_legacy_detected) echo "旧デプロイを検出：コンテナは稼働中ですが env ファイルがありません" ;;
        note_legacy_migrate) echo "migrate/install を実行して script 管理へ移行してください" ;;
        ask_new_ee_secret_cli) echo "新しいEEシークレットを入力（hex、空欄=自動生成）: " ;;
        ask_new_dd_secret_cli) echo "新しいDDシークレットを入力（32hex または dd+32hex）: " ;;
        note_attempt_restart_ee) echo "[ee] 再起動を試行中..." ;;
        note_attempt_restart_dd) echo "[dd] 再起動を試行中..." ;;
        hc_not_installed) echo "未インストール（env ファイル不足）" ;;
        hc_service_not_active) echo "サービス停止" ;;
        hc_container_not_running) echo "コンテナ停止" ;;
        hc_port_not_listening) echo "ポート未待受" ;;
        hc_image_mismatch) echo "イメージ不一致" ;;
        hc_healthy) echo "正常" ;;
        critical_need_systemctl) echo "重大: systemctl が必要です。" ;;
        critical_need_apt) echo "重大: apt-get が必要です。" ;;
        preflight_warnings) echo "事前チェック警告:" ;;
        aborted_by_user) echo "ユーザーにより中断しました。" ;;
      esac
      ;;
  esac
}

# ---------- Utilities ----------
is_port_number() {
  [[ "$1" =~ ^[0-9]+$ ]] && (("$1" >= 1 && "$1" <= 65535))
}

is_valid_domain() {
  local d="$1"
  [[ "$d" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}$ ]]
}

port_in_use() {
  local p="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -lntp 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${p}$"
  elif command -v netstat >/dev/null 2>&1; then
    netstat -lnt 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${p}$"
  else
    return 1
  fi
}

show_port_holders() {
  local p="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -lntp 2>/dev/null | awk -v port=":${p}" '$4 ~ port"$"'
  elif command -v netstat >/dev/null 2>&1; then
    netstat -lntp 2>/dev/null | awk -v port=":${p}" '$4 ~ port"$"'
  fi
}

cleanup_old_proxy_containers() {
  local ids named_ids image_ids
  local -a id_arr=()
  if ! command -v docker >/dev/null 2>&1; then
    return 1
  fi

  named_ids="$(
    {
      docker ps -aq --filter name='^/mtg-ee$' 2>/dev/null || true
      docker ps -aq --filter name='^/mtproto-dd$' 2>/dev/null || true
    } | awk 'NF' | sort -u
  )"
  image_ids="$(docker ps -a --format '{{.ID}} {{.Image}}' 2>/dev/null \
    | awk '$2 ~ /^nineseconds\/mtg(@sha256:|:)/ || $2 ~ /^telegrammessenger\/proxy(@sha256:|:)/ {print $1}' || true)"
  ids="$(printf '%s\n%s\n' "$named_ids" "$image_ids" | awk 'NF' | sort -u)"

  if [[ -n "$ids" ]]; then
    mapfile -t id_arr < <(printf '%s\n' "$ids" | awk 'NF')
    docker rm -f "${id_arr[@]}" >/dev/null 2>&1 || true
  fi
  return 0
}

ask_domain() {
  local prompt_key="$1"
  local var_name="$2"
  local value=""
  while true; do
    echo -n "$(t "$prompt_key")"
    read -r value
    value="${value//[[:space:]]/}"
    value="${value,,}"
    if [[ -z "$value" ]]; then
      t err_empty
      continue
    fi
    if ! is_valid_domain "$value"; then
      t err_domain_invalid
      continue
    fi
    printf -v "$var_name" "%s" "$value"
    return 0
  done
}

ask_front_domain_with_options() {
  local choice=""
  while true; do
    t ask_fronting_mode
    echo "1) www.cloudflare.com ($(t opt_recommended))"
    echo "2) www.google.com"
    echo "3) www.microsoft.com"
    echo "4) aws.amazon.com"
    echo "5) $(t opt_manual_input)"
    read -rp "> " choice
    choice="${choice// /}"
    case "$choice" in
      1)
        FRONT_DOMAIN="www.cloudflare.com"
        return 0
        ;;
      2)
        FRONT_DOMAIN="www.google.com"
        return 0
        ;;
      3)
        FRONT_DOMAIN="www.microsoft.com"
        return 0
        ;;
      4)
        FRONT_DOMAIN="aws.amazon.com"
        return 0
        ;;
      5)
        ask_domain ask_front_domain FRONT_DOMAIN
        return 0
        ;;
      *)
        t err_choice_invalid
        ;;
    esac
  done
}

check_and_prepare_port() {
  local p="$1"
  local do_cleanup=""

  if ! is_port_number "$p"; then
    t err_port_num
    return 1
  fi

  if port_in_use "$p"; then
    t warn_443_busy
    t note_port_holders
    show_port_holders "$p" || true
    echo -n "$(t ask_cleanup_proxy_443)"
    read -r do_cleanup
    if [[ "$do_cleanup" =~ ^[Yy]$ ]]; then
      if cleanup_old_proxy_containers; then
        t note_cleanup_done
      else
        t warn_cleanup_unavailable
      fi
      if port_in_use "$p"; then
        t warn_443_still_busy
        t note_port_holders
        show_port_holders "$p" || true
        t err_port_in_use
        return 1
      fi
      return 0
    fi
    t err_port_in_use
    return 1
  fi

  return 0
}

ask_port() {
  local prompt_key="$1"
  local var_name="$2"
  local p=""
  while true; do
    echo -n "$(t "$prompt_key")"
    read -r p
    p="${p// /}"
    if check_and_prepare_port "$p"; then
      printf -v "$var_name" "%s" "$p"
      return 0
    fi
  done
}

ask_port_with_options() {
  local prompt_key="$1"
  local var_name="$2"
  local opt1="$3"
  local opt2="$4"
  local opt3="$5"
  local choice=""
  local p=""

  while true; do
    t ask_port_menu
    echo "1) ${opt1} ($(t opt_recommended))"
    echo "2) ${opt2}"
    echo "3) ${opt3}"
    echo "4) $(t opt_manual_input)"
    read -rp "> " choice
    choice="${choice// /}"
    case "$choice" in
      1) p="$opt1" ;;
      2) p="$opt2" ;;
      3) p="$opt3" ;;
      4)
        ask_port "$prompt_key" "$var_name"
        return 0
        ;;
      *)
        t err_choice_invalid
        continue
        ;;
    esac

    if check_and_prepare_port "$p"; then
      printf -v "$var_name" "%s" "$p"
      return 0
    fi
  done
}

ask_deploy_mode() {
  local mode=""
  while true; do
    t ask_mode
    echo "1) $(t mode_ee_only)"
    echo "2) $(t mode_dd_only)"
    echo "3) $(t mode_both)"
    read -rp "> " mode
    mode="${mode// /}"
    case "$mode" in
      1)
        DEPLOY_EE=1
        DEPLOY_DD=0
        return 0
        ;;
      2)
        DEPLOY_EE=0
        DEPLOY_DD=1
        return 0
        ;;
      3)
        DEPLOY_EE=1
        DEPLOY_DD=1
        return 0
        ;;
      *)
        t err_mode_invalid
        ;;
    esac
  done
}

confirm_continue() {
  local ans=""
  echo -n "$(t ask_continue_anyway)"
  read -r ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

get_primary_ipv4() {
  local ip=""
  ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="src") {print $(i+1); exit}}')"
  if [[ -z "$ip" ]]; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  printf '%s' "$ip"
}

resolve_domain_a_records() {
  local domain="$1"
  dig +short A "$domain" 2>/dev/null | awk '/^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/'
}

check_domain_dns() {
  local domain="$1"
  local server_ip="$2"
  local records
  records="$(resolve_domain_a_records "$domain" || true)"

  if [[ -z "$records" ]]; then
    printf '%s (%s)\n' "$(t warn_dns_unresolved)" "${domain}"
    confirm_continue || return 1
    return 0
  fi

  if [[ -n "$server_ip" ]] && ! grep -qx "$server_ip" <<<"$records"; then
    printf '%s (%s)\n' "$(t warn_dns_mismatch)" "${domain}"
    echo "A records: $(tr '\n' ' ' <<<"$records" | xargs)"
    echo "Server IP: ${server_ip}"
    confirm_continue || return 1
  fi
}

collect_sshd_ports() {
  local ports
  ports="$(ss -lntp 2>/dev/null | awk '/sshd/ {print $4}' | sed -E 's/.*[:.]([0-9]+)$/\1/' | awk '/^[0-9]+$/' | sort -u || true)"
  if [[ -z "$ports" ]]; then
    echo "22"
  else
    echo "$ports"
  fi
}

is_valid_digest_image_ref() {
  local image_ref="$1"
  [[ "$image_ref" =~ ^[^[:space:]@]+@sha256:[a-f0-9]{64}$ ]]
}

validate_image_refs() {
  if [[ "$DEPLOY_EE" -eq 1 ]] && ! is_valid_digest_image_ref "$MTG_IMAGE"; then
    t err_image_ref_invalid
    echo "MTG_IMAGE=${MTG_IMAGE}"
    exit 1
  fi
  if [[ "$DEPLOY_DD" -eq 1 ]] && ! is_valid_digest_image_ref "$DD_IMAGE"; then
    t err_image_ref_invalid
    echo "DD_IMAGE=${DD_IMAGE}"
    exit 1
  fi
}

usage() {
  cat <<'EOF'
Usage:
  install.sh [install]
  install.sh migrate [--mode ee|dd|all] [--ee-domain DOMAIN] [--dd-domain DOMAIN] [--front-domain DOMAIN]
  install.sh rollback [--mode ee|dd|all] [--backup-id ID]
  install.sh self-update
  install.sh uninstall [--mode ee|dd|all]
  install.sh upgrade [--mode ee|dd|all] [--mtg-image IMAGE@sha256:...] [--dd-image IMAGE@sha256:...]
  install.sh healthcheck [--mode ee|dd|all]
  install.sh self-heal [--mode ee|dd|all]
  install.sh rotate-secret --mode ee|dd [--secret SECRET] [--front-domain DOMAIN]

Notes:
  - No arguments: open interactive menu.
  - migrate imports legacy running containers (mtg-ee / mtproto-dd) into env+systemd management.
  - rollback restores config and units from latest backup or specified backup ID.
  - self-update pulls the latest script repository by fast-forward only.
  - 'install' command: start interactive install flow directly.
  - rotate-secret for DD accepts either 32-hex or dd+32-hex.
EOF
}

set_mode_flags() {
  local mode="${1:-all}"
  case "$mode" in
    ee)
      DEPLOY_EE=1
      DEPLOY_DD=0
      ;;
    dd)
      DEPLOY_EE=0
      DEPLOY_DD=1
      ;;
    all)
      DEPLOY_EE=1
      DEPLOY_DD=1
      ;;
    *)
      printf '%s %s\n' "$(t err_mode_value_invalid)" "$mode"
      return 1
      ;;
  esac
}

is_valid_ipv4() {
  local ip="$1"
  local o1 o2 o3 o4
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS='.' read -r o1 o2 o3 o4 <<<"$ip"
  for octet in "$o1" "$o2" "$o3" "$o4"; do
    ((octet >= 0 && octet <= 255)) || return 1
  done
}

is_local_bind_ip() {
  local ip="$1"
  if [[ "$ip" == "0.0.0.0" ]]; then
    return 0
  fi
  ip -4 -o addr show 2>/dev/null | awk '{split($4,a,"/"); print a[1]}' | grep -qx "$ip"
}

ask_bind_ip_with_options() {
  local var_name="$1"
  local primary_ip="$2"
  local choice=""
  local input_ip=""
  while true; do
    t ask_bind_ip_mode
    echo "1) 0.0.0.0 ($(t opt_all_interfaces))"
    if [[ -n "$primary_ip" ]]; then
      echo "2) ${primary_ip} ($(t opt_primary_ipv4))"
    else
      echo "2) $(t opt_primary_ipv4) ($(t opt_unavailable))"
    fi
    echo "3) $(t opt_manual_input)"
    read -rp "> " choice
    choice="${choice// /}"
    case "$choice" in
      1)
        printf -v "$var_name" "0.0.0.0"
        return 0
        ;;
      2)
        if [[ -n "$primary_ip" ]]; then
          printf -v "$var_name" "%s" "$primary_ip"
          return 0
        fi
        t err_primary_ipv4_unavailable
        ;;
      3)
        read -rp "$(t ask_bind_ipv4)" input_ip
        input_ip="${input_ip// /}"
        if ! is_valid_ipv4 "$input_ip"; then
          t err_ipv4_invalid
          continue
        fi
        if ! is_local_bind_ip "$input_ip"; then
          t err_bind_ip_not_found
          continue
        fi
        printf -v "$var_name" "%s" "$input_ip"
        return 0
        ;;
      *)
        t err_choice_invalid
        ;;
    esac
  done
}

ports_conflict_for_bindings() {
  local p1="$1"
  local ip1="$2"
  local p2="$3"
  local ip2="$4"
  [[ "$p1" == "$p2" ]] || return 1
  if [[ "$ip1" == "0.0.0.0" || "$ip2" == "0.0.0.0" || "$ip1" == "$ip2" ]]; then
    return 0
  fi
  return 1
}

ufw_allow_proxy_port() {
  local p="$1"
  local bind_ip="$2"
  local strict="$3"
  if [[ "$strict" =~ ^[Yy]$ ]] && [[ "$bind_ip" != "0.0.0.0" ]]; then
    ufw allow proto tcp from any to "$bind_ip" port "$p" >/dev/null
  else
    ufw allow "${p}/tcp" >/dev/null
  fi
}

preflight_checks() {
  local warnings=()
  local mem_kb=""
  local disk_mb=""
  local os_id="" os_version=""
  local ntp_sync=""

  if ! command -v systemctl >/dev/null 2>&1; then
    t critical_need_systemctl
    exit 1
  fi
  if [[ "$(ps -p 1 -o comm= 2>/dev/null || true)" != "systemd" ]]; then
    warnings+=("PID 1 is not systemd; service management may fail.")
  fi
  if ! command -v apt-get >/dev/null 2>&1; then
    t critical_need_apt
    exit 1
  fi

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    os_id="${ID:-}"
    os_version="${VERSION_ID:-}"
    if [[ "$os_id" != "ubuntu" || "$os_version" != "22.04" ]]; then
      warnings+=("Target is tuned for Ubuntu 22.04; detected ${os_id:-unknown} ${os_version:-unknown}.")
    fi
  fi

  mem_kb="$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || true)"
  if [[ -n "$mem_kb" ]] && ((mem_kb < 524288)); then
    warnings+=("Memory is below 512MB; proxy stability may be poor.")
  fi

  disk_mb="$(df -Pm / 2>/dev/null | awk 'NR==2 {print $4}' || true)"
  if [[ -n "$disk_mb" ]] && ((disk_mb < 1024)); then
    warnings+=("Free disk is below 1GB.")
  fi

  if command -v timedatectl >/dev/null 2>&1; then
    ntp_sync="$(timedatectl show -p NTPSynchronized --value 2>/dev/null || true)"
    if [[ "$ntp_sync" != "yes" ]]; then
      warnings+=("NTP is not synchronized; time skew can hurt TLS and networking.")
    fi
  fi

  if ! getent hosts registry-1.docker.io >/dev/null 2>&1; then
    warnings+=("DNS lookup for registry-1.docker.io failed; Docker pull may fail.")
  fi

  if ((${#warnings[@]} > 0)); then
    echo
    t preflight_warnings
    printf ' - %s\n' "${warnings[@]}"
    if ! confirm_continue; then
      t aborted_by_user
      exit 1
    fi
  fi
}

ensure_config_dir() {
  mkdir -p "$CONFIG_DIR"
  chmod 700 "$CONFIG_DIR"
}

write_ee_env_file() {
  umask 077
  cat >"$EE_ENV_FILE" <<EOF
EE_DOMAIN=${EE_DOMAIN}
FRONT_DOMAIN=${FRONT_DOMAIN}
EE_PORT=${EE_PORT}
EE_BIND_IP=${EE_BIND_IP}
MTG_IMAGE=${MTG_IMAGE}
EE_SECRET=${EE_SECRET}
EOF
}

write_dd_env_file() {
  umask 077
  cat >"$DD_ENV_FILE" <<EOF
DD_DOMAIN=${DD_DOMAIN}
DD_PORT=${DD_PORT}
DD_BIND_IP=${DD_BIND_IP}
DD_BASE_SECRET=${DD_BASE_SECRET}
DD_SECRET=${DD_SECRET}
DD_IMAGE=${DD_IMAGE}
EOF
}

write_ee_systemd_unit() {
  cat >/etc/systemd/system/"$EE_SERVICE_NAME" <<'EOF'
[Unit]
Description=Telegram Proxy EE (mtg)
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=simple
Restart=always
RestartSec=5
EnvironmentFile=/etc/telegram-proxy/ee.env
ExecStartPre=-/usr/bin/docker rm -f mtg-ee
ExecStart=/usr/bin/docker run --name mtg-ee --cap-drop=ALL --security-opt=no-new-privileges --pids-limit=256 -v /opt/mtg/config.toml:/config.toml:ro -p ${EE_BIND_IP}:${EE_PORT}:3128 ${MTG_IMAGE}
ExecStop=/usr/bin/docker stop -t 10 mtg-ee
ExecStopPost=-/usr/bin/docker rm -f mtg-ee

[Install]
WantedBy=multi-user.target
EOF
}

write_dd_systemd_unit() {
  cat >/etc/systemd/system/"$DD_SERVICE_NAME" <<'EOF'
[Unit]
Description=Telegram Proxy DD (MTProxy padding)
After=network-online.target docker.service
Wants=network-online.target
Requires=docker.service

[Service]
Type=simple
Restart=always
RestartSec=5
EnvironmentFile=/etc/telegram-proxy/dd.env
ExecStartPre=-/usr/bin/docker rm -f mtproto-dd
ExecStart=/usr/bin/docker run --name mtproto-dd --cap-drop=ALL --security-opt=no-new-privileges --pids-limit=256 -p ${DD_BIND_IP}:${DD_PORT}:443 -e SECRET=${DD_SECRET} ${DD_IMAGE}
ExecStop=/usr/bin/docker stop -t 10 mtproto-dd
ExecStopPost=-/usr/bin/docker rm -f mtproto-dd

[Install]
WantedBy=multi-user.target
EOF
}

systemd_reload() {
  systemctl daemon-reload
}

load_env_file() {
  local f="$1"
  [[ -f "$f" ]] || return 1
  # shellcheck disable=SC1090
  source "$f"
}

upsert_env_key() {
  local file="$1"
  local key="$2"
  local value="$3"
  if grep -q "^${key}=" "$file" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >>"$file"
  fi
}

acquire_run_lock() {
  if ! command -v flock >/dev/null 2>&1; then
    t err_lock_unavailable
    exit 1
  fi
  mkdir -p "$(dirname "$LOCK_FILE")"
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    t err_lock_busy
    exit 1
  fi
}

ensure_backup_dir() {
  mkdir -p "$BACKUP_DIR"
  chmod 700 "$BACKUP_DIR"
}

latest_backup_path() {
  local latest=""
  latest="$(ls -1dt "$BACKUP_DIR"/* 2>/dev/null | head -n1 || true)"
  [[ -n "$latest" ]] || return 1
  printf '%s' "$latest"
}

resolve_backup_path() {
  local backup_id="$1"
  if [[ -z "$backup_id" ]]; then
    latest_backup_path
    return
  fi
  if [[ -d "$backup_id" ]]; then
    printf '%s' "$backup_id"
    return 0
  fi
  if [[ -d "${BACKUP_DIR}/${backup_id}" ]]; then
    printf '%s' "${BACKUP_DIR}/${backup_id}"
    return 0
  fi
  return 1
}

create_backup() {
  local action="$1"
  local stamp=""
  local backup_path=""
  stamp="$(date +%Y%m%d-%H%M%S)"
  ensure_backup_dir
  backup_path="${BACKUP_DIR}/${stamp}-${action}"
  mkdir -p "$backup_path"
  chmod 700 "$backup_path"

  if [[ "$DEPLOY_EE" -eq 1 ]]; then
    [[ -f "$EE_ENV_FILE" ]] && cp -a "$EE_ENV_FILE" "${backup_path}/ee.env"
    [[ -f "/etc/systemd/system/${EE_SERVICE_NAME}" ]] && cp -a "/etc/systemd/system/${EE_SERVICE_NAME}" "${backup_path}/${EE_SERVICE_NAME}"
    [[ -f "/opt/mtg/config.toml" ]] && cp -a "/opt/mtg/config.toml" "${backup_path}/config.toml"
  fi
  if [[ "$DEPLOY_DD" -eq 1 ]]; then
    [[ -f "$DD_ENV_FILE" ]] && cp -a "$DD_ENV_FILE" "${backup_path}/dd.env"
    [[ -f "/etc/systemd/system/${DD_SERVICE_NAME}" ]] && cp -a "/etc/systemd/system/${DD_SERVICE_NAME}" "${backup_path}/${DD_SERVICE_NAME}"
  fi

  cat >"${backup_path}/meta.env" <<EOF
ACTION=${action}
DEPLOY_EE=${DEPLOY_EE}
DEPLOY_DD=${DEPLOY_DD}
CREATED_AT=$(date -Iseconds)
EOF

  t note_backup_saved
  echo "${backup_path}"
}

restore_backup() {
  local backup_path="$1"
  local restored=0
  local unit_changed=0

  if [[ "$DEPLOY_EE" -eq 1 ]]; then
    if [[ -f "${backup_path}/ee.env" ]]; then
      ensure_config_dir
      cp -a "${backup_path}/ee.env" "$EE_ENV_FILE"
      chmod 600 "$EE_ENV_FILE"
      restored=1
    fi
    if [[ -f "${backup_path}/${EE_SERVICE_NAME}" ]]; then
      cp -a "${backup_path}/${EE_SERVICE_NAME}" "/etc/systemd/system/${EE_SERVICE_NAME}"
      unit_changed=1
      restored=1
    fi
    if [[ -f "${backup_path}/config.toml" ]]; then
      mkdir -p /opt/mtg
      chmod 700 /opt/mtg
      cp -a "${backup_path}/config.toml" /opt/mtg/config.toml
      chmod 600 /opt/mtg/config.toml
      restored=1
    fi
  fi

  if [[ "$DEPLOY_DD" -eq 1 ]]; then
    if [[ -f "${backup_path}/dd.env" ]]; then
      ensure_config_dir
      cp -a "${backup_path}/dd.env" "$DD_ENV_FILE"
      chmod 600 "$DD_ENV_FILE"
      restored=1
    fi
    if [[ -f "${backup_path}/${DD_SERVICE_NAME}" ]]; then
      cp -a "${backup_path}/${DD_SERVICE_NAME}" "/etc/systemd/system/${DD_SERVICE_NAME}"
      unit_changed=1
      restored=1
    fi
  fi

  if [[ "$restored" -eq 0 ]]; then
    t err_backup_not_found
    return 1
  fi

  if [[ "$unit_changed" -eq 1 ]]; then
    systemd_reload
  fi
  if [[ "$DEPLOY_EE" -eq 1 ]] && [[ -f "$EE_ENV_FILE" ]] && [[ -f "/etc/systemd/system/${EE_SERVICE_NAME}" ]]; then
    systemctl enable --now "$EE_SERVICE_NAME" >/dev/null 2>&1 || true
  fi
  if [[ "$DEPLOY_DD" -eq 1 ]] && [[ -f "$DD_ENV_FILE" ]] && [[ -f "/etc/systemd/system/${DD_SERVICE_NAME}" ]]; then
    systemctl enable --now "$DD_SERVICE_NAME" >/dev/null 2>&1 || true
  fi
  return 0
}

normalize_image_to_digest() {
  local mode="$1"
  local image_ref="$2"
  local repo_digest=""
  local fallback=""

  if is_valid_digest_image_ref "$image_ref"; then
    printf '%s' "$image_ref"
    return 0
  fi

  repo_digest="$(docker image inspect "$image_ref" --format '{{index .RepoDigests 0}}' 2>/dev/null || true)"
  if [[ -n "$repo_digest" ]] && is_valid_digest_image_ref "$repo_digest"; then
    printf '%s' "$repo_digest"
    return 0
  fi

  t warn_image_not_digest
  if [[ "$mode" == "ee" ]]; then
    fallback="$MTG_IMAGE"
  else
    fallback="$DD_IMAGE"
  fi
  printf '%s' "$fallback"
}

docker_container_exists() {
  local name="$1"
  docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$name"
}

docker_env_value() {
  local container="$1"
  local key="$2"
  docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$container" 2>/dev/null \
    | awk -F= -v k="$key" '$1 == k {sub($1"=","",$0); print; exit}'
}

docker_binding_ip() {
  local container="$1"
  local container_port="$2"
  local ip=""
  ip="$(docker inspect -f "{{with index .HostConfig.PortBindings \"${container_port}\"}}{{(index . 0).HostIp}}{{end}}" "$container" 2>/dev/null || true)"
  if [[ -z "$ip" ]]; then
    ip="0.0.0.0"
  fi
  printf '%s' "$ip"
}

docker_binding_port() {
  local container="$1"
  local container_port="$2"
  docker inspect -f "{{with index .HostConfig.PortBindings \"${container_port}\"}}{{(index . 0).HostPort}}{{end}}" "$container" 2>/dev/null || true
}

extract_ee_secret_from_config() {
  if [[ -f /opt/mtg/config.toml ]]; then
    sed -n 's/^[[:space:]]*secret[[:space:]]*=[[:space:]]*"\([A-Za-z0-9]\+\)".*/\1/p' /opt/mtg/config.toml | head -n1
  fi
}

check_mode_health() {
  local mode="$1"
  local service_name=""
  local container_name=""
  local env_file=""
  local port=""
  local bind_ip=""
  local expected_image=""
  local container_port_key=""
  local ok=0
  local mode_container_running=0
  local service_restarts=0
  local container_restarts=0
  local running_image=""
  local actual_bind_ip=""
  local actual_bind_port=""

  case "$mode" in
    ee)
      service_name="$EE_SERVICE_NAME"
      container_name="$EE_CONTAINER_NAME"
      env_file="$EE_ENV_FILE"
      container_port_key="3128/tcp"
      ;;
    dd)
      service_name="$DD_SERVICE_NAME"
      container_name="$DD_CONTAINER_NAME"
      env_file="$DD_ENV_FILE"
      container_port_key="443/tcp"
      ;;
    *)
      return 1
      ;;
  esac

  if docker ps --format '{{.Names}}' | grep -qx "$container_name"; then
    mode_container_running=1
  fi

  if [[ ! -f "$env_file" ]]; then
    if [[ "$mode_container_running" -eq 1 ]]; then
      printf '[%s] %s (%s)\n' "$mode" "$(t note_legacy_detected)" "$env_file"
      printf '[%s] %s\n' "$mode" "$(t note_legacy_migrate)"
      return 0
    fi
    printf '[%s] %s: %s\n' "$mode" "$(t hc_not_installed)" "$env_file"
    return 2
  fi

  if ! systemctl is-active --quiet "$service_name"; then
    printf '[%s] %s: %s\n' "$mode" "$(t hc_service_not_active)" "$service_name"
    ok=1
  fi

  if ! docker ps --format '{{.Names}}' | grep -qx "$container_name"; then
    printf '[%s] %s: %s\n' "$mode" "$(t hc_container_not_running)" "$container_name"
    ok=1
  fi

  # shellcheck disable=SC1090
  source "$env_file"
  if [[ "$mode" == "ee" ]]; then
    port="${EE_PORT}"
    bind_ip="${EE_BIND_IP:-0.0.0.0}"
    expected_image="${MTG_IMAGE:-}"
  else
    port="${DD_PORT}"
    bind_ip="${DD_BIND_IP:-0.0.0.0}"
    expected_image="${DD_IMAGE:-}"
  fi

  service_restarts="$(systemctl show -p NRestarts --value "$service_name" 2>/dev/null || echo 0)"
  if [[ "$service_restarts" =~ ^[0-9]+$ ]] && ((service_restarts >= 5)); then
    printf '[%s] %s %s\n' "$mode" "$(t warn_service_restarts)" "$service_restarts"
  fi

  container_restarts="$(docker inspect -f '{{.RestartCount}}' "$container_name" 2>/dev/null || echo 0)"
  if [[ "$container_restarts" =~ ^[0-9]+$ ]] && ((container_restarts >= 5)); then
    printf '[%s] %s %s\n' "$mode" "$(t warn_container_restarts)" "$container_restarts"
  fi

  running_image="$(docker inspect -f '{{.Config.Image}}' "$container_name" 2>/dev/null || true)"
  if [[ -n "$expected_image" && -n "$running_image" && "$running_image" != "$expected_image" ]]; then
    printf '[%s] %s: running=%s configured=%s\n' "$mode" "$(t hc_image_mismatch)" "$running_image" "$expected_image"
    ok=1
  fi

  actual_bind_ip="$(docker_binding_ip "$container_name" "$container_port_key")"
  actual_bind_port="$(docker_binding_port "$container_name" "$container_port_key")"
  if [[ -n "$actual_bind_port" ]] && { [[ "$actual_bind_port" != "$port" ]] || [[ "$actual_bind_ip" != "$bind_ip" ]]; }; then
    echo "[${mode}] $(t err_port_binding_mismatch)"
    echo "[${mode}] expected=${bind_ip}:${port} actual=${actual_bind_ip}:${actual_bind_port}"
    ok=1
  fi

  if ! port_in_use "$port"; then
    printf '[%s] %s: %s\n' "$mode" "$(t hc_port_not_listening)" "$port"
    ok=1
  fi

  if [[ "$ok" -eq 0 ]]; then
    printf '[%s] %s\n' "$mode" "$(t hc_healthy)"
    return 0
  fi
  if docker_container_exists "$container_name"; then
    echo "[${mode}] $(t note_recent_logs)"
    docker logs --tail 5 "$container_name" 2>&1 | sed "s/^/[${mode}] log: /" || true
  fi
  return 1
}

cmd_healthcheck() {
  local failed=0
  local rc=0
  if [[ "$DEPLOY_EE" -eq 1 ]]; then
    check_mode_health ee || rc=$?
    if [[ "$rc" -eq 1 ]]; then
      failed=1
    fi
  fi
  rc=0
  if [[ "$DEPLOY_DD" -eq 1 ]]; then
    check_mode_health dd || rc=$?
    if [[ "$rc" -eq 1 ]]; then
      failed=1
    fi
  fi
  return "$failed"
}

cmd_self_heal() {
  local failed=0
  local rc=0
  if [[ "$DEPLOY_EE" -eq 1 ]]; then
    check_mode_health ee || rc=$?
    if [[ "$rc" -eq 1 ]]; then
      t note_attempt_restart_ee
      systemctl restart "$EE_SERVICE_NAME" || true
      sleep 2
      check_mode_health ee || failed=1
    fi
  fi
  rc=0
  if [[ "$DEPLOY_DD" -eq 1 ]]; then
    check_mode_health dd || rc=$?
    if [[ "$rc" -eq 1 ]]; then
      t note_attempt_restart_dd
      systemctl restart "$DD_SERVICE_NAME" || true
      sleep 2
      check_mode_health dd || failed=1
    fi
  fi
  return "$failed"
}

cmd_uninstall() {
  if [[ "$DEPLOY_EE" -eq 1 ]]; then
    systemctl disable --now "$EE_SERVICE_NAME" >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/"$EE_SERVICE_NAME" "$EE_ENV_FILE"
    docker rm -f "$EE_CONTAINER_NAME" >/dev/null 2>&1 || true
    rm -f /opt/mtg/config.toml
  fi
  if [[ "$DEPLOY_DD" -eq 1 ]]; then
    systemctl disable --now "$DD_SERVICE_NAME" >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/"$DD_SERVICE_NAME" "$DD_ENV_FILE"
    docker rm -f "$DD_CONTAINER_NAME" >/dev/null 2>&1 || true
  fi
  systemd_reload
  rmdir "$CONFIG_DIR" >/dev/null 2>&1 || true
}

cmd_rollback() {
  local backup_id="${1:-}"
  local backup_path=""

  echo
  t step_rollback
  if ! backup_path="$(resolve_backup_path "$backup_id")"; then
    if [[ -z "$backup_id" ]]; then
      t note_backup_none
    else
      t err_backup_not_found
      echo "$backup_id"
    fi
    return 1
  fi

  if [[ -z "$backup_id" ]]; then
    t note_backup_latest
  else
    t note_backup_saved
  fi
  echo "$backup_path"

  restore_backup "$backup_path"
  t note_rollback_done
  cmd_healthcheck || true
}

cmd_migrate() {
  local ee_domain_arg="$1"
  local dd_domain_arg="$2"
  local front_domain_arg="$3"
  local ee_secret_input=""
  local image_ref=""
  local migrated_any=0

  echo
  t step_migrate
  t step_backup
  create_backup "migrate"
  ensure_config_dir
  mkdir -p /opt/mtg
  chmod 700 /opt/mtg

  if [[ "$DEPLOY_EE" -eq 1 ]]; then
    if ! docker_container_exists "$EE_CONTAINER_NAME"; then
      if [[ "$DEPLOY_DD" -eq 1 ]] && docker_container_exists "$DD_CONTAINER_NAME"; then
        DEPLOY_EE=0
      else
        t err_legacy_container_missing
        echo "$EE_CONTAINER_NAME"
        return 1
      fi
    fi
  fi
  if [[ "$DEPLOY_DD" -eq 1 ]]; then
    if ! docker_container_exists "$DD_CONTAINER_NAME"; then
      if [[ "$DEPLOY_EE" -eq 1 ]] && docker_container_exists "$EE_CONTAINER_NAME"; then
        DEPLOY_DD=0
      else
        t err_legacy_container_missing
        echo "$DD_CONTAINER_NAME"
        return 1
      fi
    fi
  fi

  if [[ "$DEPLOY_EE" -eq 0 && "$DEPLOY_DD" -eq 0 ]]; then
    t err_migrate_no_legacy
    return 1
  fi

  if [[ "$DEPLOY_EE" -eq 1 ]]; then
    if ! docker_container_exists "$EE_CONTAINER_NAME"; then
      t err_legacy_container_missing
      echo "$EE_CONTAINER_NAME"
      return 1
    fi
    EE_DOMAIN="${ee_domain_arg:-}"
    if [[ -z "$EE_DOMAIN" ]]; then
      ask_domain ask_ee_domain EE_DOMAIN
    fi
    FRONT_DOMAIN="${front_domain_arg:-www.cloudflare.com}"
    EE_BIND_IP="$(docker_binding_ip "$EE_CONTAINER_NAME" "3128/tcp")"
    EE_PORT="$(docker_binding_port "$EE_CONTAINER_NAME" "3128/tcp")"
    if [[ -z "$EE_PORT" ]]; then
      t err_migrate_port_missing
      return 1
    fi
    image_ref="$(docker inspect -f '{{.Config.Image}}' "$EE_CONTAINER_NAME" 2>/dev/null || true)"
    MTG_IMAGE="$(normalize_image_to_digest ee "$image_ref")"
    printf '%s %s\n' "$(t note_using_digest)" "$MTG_IMAGE"
    EE_SECRET="$(extract_ee_secret_from_config || true)"
    if [[ -z "$EE_SECRET" ]]; then
      read -rp "$(t ask_existing_ee_secret)" ee_secret_input
      ee_secret_input="${ee_secret_input// /}"
      EE_SECRET="$ee_secret_input"
    fi
    if [[ -z "$EE_SECRET" ]]; then
      t err_ee_secret_required
      return 1
    fi
    umask 077
    cat >/opt/mtg/config.toml <<EOF
secret = "$EE_SECRET"
bind-to = "0.0.0.0:3128"
EOF
    chmod 600 /opt/mtg/config.toml
    write_ee_env_file
    write_ee_systemd_unit
    migrated_any=1
  fi

  if [[ "$DEPLOY_DD" -eq 1 ]]; then
    DD_DOMAIN="${dd_domain_arg:-}"
    if [[ -z "$DD_DOMAIN" ]]; then
      ask_domain ask_dd_domain DD_DOMAIN
    fi
    DD_BIND_IP="$(docker_binding_ip "$DD_CONTAINER_NAME" "443/tcp")"
    DD_PORT="$(docker_binding_port "$DD_CONTAINER_NAME" "443/tcp")"
    if [[ -z "$DD_PORT" ]]; then
      t err_migrate_port_missing
      return 1
    fi
    image_ref="$(docker inspect -f '{{.Config.Image}}' "$DD_CONTAINER_NAME" 2>/dev/null || true)"
    DD_IMAGE="$(normalize_image_to_digest dd "$image_ref")"
    printf '%s %s\n' "$(t note_using_digest)" "$DD_IMAGE"

    DD_BASE_SECRET="$(docker_env_value "$DD_CONTAINER_NAME" "SECRET")"
    if ! normalize_dd_secret "$DD_BASE_SECRET"; then
      t err_invalid_dd_secret
      return 1
    fi
    write_dd_env_file
    write_dd_systemd_unit
    migrated_any=1
  fi

  if [[ "$migrated_any" -eq 0 ]]; then
    t err_migrate_no_legacy
    return 1
  fi

  systemd_reload
  if [[ "$DEPLOY_EE" -eq 1 ]]; then
    systemctl enable --now "$EE_SERVICE_NAME" >/dev/null
  fi
  if [[ "$DEPLOY_DD" -eq 1 ]]; then
    systemctl enable --now "$DD_SERVICE_NAME" >/dev/null
  fi
  t note_migrate_done
  cmd_healthcheck || true
}

cmd_self_update() {
  local script_dir
  script_dir="$(cd "$(dirname "$0")" && pwd -P)"
  if [[ ! -d "${script_dir}/.git" ]]; then
    t err_self_update_not_git
    echo "${script_dir}"
    return 1
  fi
  echo
  t step_self_update
  git -C "$script_dir" pull --ff-only
  t note_self_update_done
  t note_self_update_rerun
  echo "sudo bash ${script_dir}/install.sh"
}

cmd_upgrade() {
  local mtg_new_image="$1"
  local dd_new_image="$2"
  local current_mtg_image=""
  local current_dd_image=""

  echo
  t step_backup
  create_backup "upgrade"

  if [[ "$DEPLOY_EE" -eq 1 ]]; then
    [[ -f "$EE_ENV_FILE" ]] || {
      t err_not_installed_ee
      return 1
    }
    # shellcheck disable=SC1090
    source "$EE_ENV_FILE"
    current_mtg_image="${MTG_IMAGE:-}"
    mtg_new_image="${mtg_new_image:-$current_mtg_image}"
    if ! is_valid_digest_image_ref "$mtg_new_image"; then
      printf '%s %s\n' "$(t err_invalid_mtg_image)" "$mtg_new_image"
      return 1
    fi
    upsert_env_key "$EE_ENV_FILE" "MTG_IMAGE" "$mtg_new_image"
    docker pull "$mtg_new_image"
    write_ee_systemd_unit
    systemd_reload
    systemctl restart "$EE_SERVICE_NAME"
  fi

  if [[ "$DEPLOY_DD" -eq 1 ]]; then
    [[ -f "$DD_ENV_FILE" ]] || {
      t err_not_installed_dd
      return 1
    }
    # shellcheck disable=SC1090
    source "$DD_ENV_FILE"
    current_dd_image="${DD_IMAGE:-}"
    dd_new_image="${dd_new_image:-$current_dd_image}"
    if ! is_valid_digest_image_ref "$dd_new_image"; then
      printf '%s %s\n' "$(t err_invalid_dd_image)" "$dd_new_image"
      return 1
    fi
    upsert_env_key "$DD_ENV_FILE" "DD_IMAGE" "$dd_new_image"
    docker pull "$dd_new_image"
    write_dd_systemd_unit
    systemd_reload
    systemctl restart "$DD_SERVICE_NAME"
  fi
}

normalize_dd_secret() {
  local input="${1,,}"
  if [[ "$input" =~ ^dd[a-f0-9]{32}$ ]]; then
    DD_BASE_SECRET="${input#dd}"
    DD_SECRET="$input"
    return 0
  fi
  if [[ "$input" =~ ^[a-f0-9]{32}$ ]]; then
    DD_BASE_SECRET="$input"
    DD_SECRET="dd${input}"
    return 0
  fi
  return 1
}

cmd_rotate_secret() {
  local mode="$1"
  local input_secret="$2"
  local front_domain_arg="$3"

  echo
  t step_backup
  create_backup "rotate-secret"

  case "$mode" in
    ee)
      [[ -f "$EE_ENV_FILE" ]] || {
        t err_not_installed_ee
        return 1
      }
      # shellcheck disable=SC1090
      source "$EE_ENV_FILE"
      if [[ -z "$input_secret" ]]; then
        read -rp "$(t ask_new_ee_secret_cli)" input_secret
      fi
      if [[ -z "$input_secret" ]]; then
        local use_front=""
        use_front="${front_domain_arg:-${FRONT_DOMAIN:-}}"
        if [[ -z "$use_front" ]]; then
          ask_domain ask_front_domain use_front
        fi
        input_secret="$(docker run --rm "$MTG_IMAGE" generate-secret --hex "$use_front" | tr -d '\r\n')"
        upsert_env_key "$EE_ENV_FILE" "FRONT_DOMAIN" "$use_front"
      fi
      if [[ ! "$input_secret" =~ ^[Ee][Ee][A-Fa-f0-9]{32,}$ ]]; then
        t err_invalid_ee_secret
        return 1
      fi
      EE_SECRET="${input_secret,,}"
      mkdir -p /opt/mtg
      chmod 700 /opt/mtg
      umask 077
      cat >/opt/mtg/config.toml <<EOF
secret = "$EE_SECRET"
bind-to = "0.0.0.0:3128"
EOF
      chmod 600 /opt/mtg/config.toml
      upsert_env_key "$EE_ENV_FILE" "EE_SECRET" "$EE_SECRET"
      write_ee_systemd_unit
      systemd_reload
      systemctl restart "$EE_SERVICE_NAME"
      ;;
    dd)
      [[ -f "$DD_ENV_FILE" ]] || {
        t err_not_installed_dd
        return 1
      }
      if [[ -z "$input_secret" ]]; then
        read -rp "$(t ask_new_dd_secret_cli)" input_secret
      fi
      if ! normalize_dd_secret "$input_secret"; then
        t err_invalid_dd_secret
        return 1
      fi
      upsert_env_key "$DD_ENV_FILE" "DD_BASE_SECRET" "$DD_BASE_SECRET"
      upsert_env_key "$DD_ENV_FILE" "DD_SECRET" "$DD_SECRET"
      # Re-write unit so legacy installs that used DD_BASE_SECRET switch to DD_SECRET.
      # shellcheck disable=SC1090
      source "$DD_ENV_FILE"
      write_dd_systemd_unit
      systemd_reload
      systemctl restart "$DD_SERVICE_NAME"
      ;;
    *)
      t err_rotate_mode_required
      return 1
      ;;
  esac
}

command_install() {
  local SERVER_IPV4=""
  local ENABLE_BBR="Y"
  local STRICT_UFW="N"
  local EE_BIND_IP="0.0.0.0"
  local DD_BIND_IP="0.0.0.0"

  if [[ "${SKIP_LANGUAGE_PROMPT:-0}" != "1" ]]; then
    select_language
  fi
  echo
  echo "============================================================"
  t title
  echo "============================================================"
  t need_dns
  t note_no_cdn
  echo

  ask_deploy_mode

  EE_DOMAIN=""
  DD_DOMAIN=""
  FRONT_DOMAIN=""
  EE_PORT=""
  DD_PORT=""
  EE_SECRET=""
  DD_BASE_SECRET=""
  DD_SECRET=""

  SERVER_IPV4="$(get_primary_ipv4)"

  if [[ "$DEPLOY_EE" -eq 1 ]]; then
    ask_domain ask_ee_domain EE_DOMAIN
    ask_front_domain_with_options
    ask_port_with_options ask_ee_port EE_PORT "443" "8443" "9443"
    ask_bind_ip_with_options EE_BIND_IP "$SERVER_IPV4"
  fi

  if [[ "$DEPLOY_DD" -eq 1 ]]; then
    ask_domain ask_dd_domain DD_DOMAIN
    ask_port_with_options ask_dd_port DD_PORT "8443" "443" "9443"
    ask_bind_ip_with_options DD_BIND_IP "$SERVER_IPV4"
  fi

  if [[ "$DEPLOY_EE" -eq 1 && "$DEPLOY_DD" -eq 1 ]] && ports_conflict_for_bindings "$EE_PORT" "$EE_BIND_IP" "$DD_PORT" "$DD_BIND_IP"; then
    t err_port_conflict
    exit 1
  fi

  echo -n "$(t ask_enable_bbr)"
  read -r ENABLE_BBR
  ENABLE_BBR="${ENABLE_BBR:-Y}"

  if [[ ("$DEPLOY_EE" -eq 1 && "$EE_BIND_IP" != "0.0.0.0") || ("$DEPLOY_DD" -eq 1 && "$DD_BIND_IP" != "0.0.0.0") ]]; then
    echo -n "$(t ask_strict_ufw)"
    read -r STRICT_UFW
    STRICT_UFW="${STRICT_UFW:-N}"
  fi

  preflight_checks

  echo
  t step_update
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg lsb-release ufw openssl jq dnsutils iproute2

  echo
  t step_dns_check
  if [[ "$DEPLOY_EE" -eq 1 ]]; then
    check_domain_dns "$EE_DOMAIN" "$SERVER_IPV4"
  fi
  if [[ "$DEPLOY_DD" -eq 1 ]]; then
    check_domain_dns "$DD_DOMAIN" "$SERVER_IPV4"
  fi

  echo
  t step_docker
  if ! command -v docker >/dev/null 2>&1; then
    apt-get install -y docker.io
  fi
  systemctl enable --now docker

  if [[ "$ENABLE_BBR" =~ ^[Yy]$ ]]; then
    echo
    t step_bbr_q
    if sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
      cat >/etc/sysctl.d/99-bbr.conf <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
      if ! sysctl --system >/dev/null 2>&1; then
        t warn_bbr_apply_fail
      fi
    else
      t warn_bbr_unsupported
    fi
  fi

  echo
  t step_firewall
  ufw allow OpenSSH >/dev/null 2>&1 || true
  while read -r ssh_port; do
    [[ -n "$ssh_port" ]] || continue
    ufw allow "${ssh_port}/tcp" >/dev/null
  done < <(collect_sshd_ports)
  if [[ "$DEPLOY_EE" -eq 1 ]]; then
    ufw_allow_proxy_port "$EE_PORT" "$EE_BIND_IP" "$STRICT_UFW"
  fi
  if [[ "$DEPLOY_DD" -eq 1 ]]; then
    ufw_allow_proxy_port "$DD_PORT" "$DD_BIND_IP" "$STRICT_UFW"
  fi
  if ufw status | grep -qi inactive; then
    ufw --force enable >/dev/null
  fi
  ufw reload >/dev/null

  validate_image_refs
  echo
  t step_pull
  if [[ "$DEPLOY_EE" -eq 1 ]]; then
    docker pull "$MTG_IMAGE" >/dev/null
  fi
  if [[ "$DEPLOY_DD" -eq 1 ]]; then
    docker pull "$DD_IMAGE" >/dev/null
  fi

  if [[ "$DEPLOY_EE" -eq 1 ]]; then
    echo
    printf '%s (%s)\n' "$(t step_front_test)" "${FRONT_DOMAIN}"
    if timeout 6 openssl s_client -connect "${FRONT_DOMAIN}:443" -servername "${FRONT_DOMAIN}" </dev/null >/dev/null 2>&1; then
      t tls_ok
    else
      t tls_fail
      if ! confirm_continue; then
        t tls_abort
        exit 1
      fi
    fi
  fi

  ensure_config_dir
  mkdir -p /opt/mtg
  chmod 700 /opt/mtg

  if [[ "$DEPLOY_EE" -eq 1 ]]; then
    echo
    t step_gen_ee
    EE_SECRET="$(docker run --rm "$MTG_IMAGE" generate-secret --hex "$FRONT_DOMAIN" | tr -d '\r\n')"
    # Docker host IP binding is controlled by -p ${EE_BIND_IP}:${EE_PORT}:3128 in systemd.
    # mtg internal bind stays 0.0.0.0:3128 inside container.
    umask 077
    cat >/opt/mtg/config.toml <<EOF
secret = "$EE_SECRET"
bind-to = "0.0.0.0:3128"
EOF
    chmod 600 /opt/mtg/config.toml
    write_ee_env_file
    write_ee_systemd_unit
  fi

  if [[ "$DEPLOY_DD" -eq 1 ]]; then
    echo
    t step_gen_dd
    DD_BASE_SECRET="$(openssl rand -hex 16)"
    DD_SECRET="dd${DD_BASE_SECRET}"
    write_dd_env_file
    write_dd_systemd_unit
  fi

  systemd_reload
  if [[ "$DEPLOY_EE" -eq 1 ]]; then
    echo
    printf '%s (port %s)\n' "$(t step_run_ee)" "${EE_PORT}"
    systemctl enable --now "$EE_SERVICE_NAME"
  fi
  if [[ "$DEPLOY_DD" -eq 1 ]]; then
    echo
    printf '%s (port %s)\n' "$(t step_run_dd)" "${DD_PORT}"
    systemctl enable --now "$DD_SERVICE_NAME"
  fi

  echo
  t step_summary
  t note_secret
  echo
  echo "Images       :"
  if [[ "$DEPLOY_EE" -eq 1 ]]; then
    echo "MTG          : ${MTG_IMAGE}"
  fi
  if [[ "$DEPLOY_DD" -eq 1 ]]; then
    echo "DD           : ${DD_IMAGE}"
  fi
  echo

  if [[ "$DEPLOY_EE" -eq 1 ]]; then
    echo "EE (FakeTLS): tg://proxy?server=${EE_DOMAIN}&port=${EE_PORT}&secret=${EE_SECRET}"
    echo
  fi
  if [[ "$DEPLOY_DD" -eq 1 ]]; then
    echo "DD (padding): tg://proxy?server=${DD_DOMAIN}&port=${DD_PORT}&secret=${DD_SECRET}"
    echo
  fi
  cmd_healthcheck || true
}

prompt_mode_all() {
  local mode_choice=""
  while true; do
    t ask_oper_mode >&2
    echo "1) ee" >&2
    echo "2) dd" >&2
    echo "3) all" >&2
    read -rp "> " mode_choice
    mode_choice="${mode_choice// /}"
    case "$mode_choice" in
      1)
        echo "ee"
        return 0
        ;;
      2)
        echo "dd"
        return 0
        ;;
      3)
        echo "all"
        return 0
        ;;
      *)
        t err_choice_invalid >&2
        ;;
    esac
  done
}

prompt_mode_rotate() {
  local mode_choice=""
  while true; do
    t ask_rotate_mode >&2
    echo "1) ee" >&2
    echo "2) dd" >&2
    read -rp "> " mode_choice
    mode_choice="${mode_choice// /}"
    case "$mode_choice" in
      1)
        echo "ee"
        return 0
        ;;
      2)
        echo "dd"
        return 0
        ;;
      *)
        t err_choice_invalid >&2
        ;;
    esac
  done
}

interactive_menu() {
  local choice=""
  local mode=""
  local mtg_image_arg=""
  local dd_image_arg=""
  local migrate_ee_domain=""
  local migrate_dd_domain=""
  local migrate_front_domain=""
  local backup_id=""
  local rotate_mode=""
  local rotate_secret=""
  local rotate_front=""

  select_language

  while true; do
    echo
    echo "================ $(t menu_title) ================"
    echo "1) $(t menu_install)"
    echo "2) $(t menu_healthcheck)"
    echo "3) $(t menu_self_heal)"
    echo "4) $(t menu_upgrade)"
    echo "5) $(t menu_self_update)"
    echo "6) $(t menu_migrate)"
    echo "7) $(t menu_rollback)"
    echo "8) $(t menu_rotate_secret)"
    echo "9) $(t menu_uninstall)"
    echo "10) $(t menu_help)"
    echo "0) $(t menu_exit)"
    read -rp "> " choice
    choice="${choice// /}"

    case "$choice" in
      1)
        SKIP_LANGUAGE_PROMPT=1 command_install
        ;;
      2)
        mode="$(prompt_mode_all)"
        set_mode_flags "$mode" || continue
        cmd_healthcheck || true
        ;;
      3)
        mode="$(prompt_mode_all)"
        set_mode_flags "$mode" || continue
        cmd_self_heal || true
        ;;
      4)
        mode="$(prompt_mode_all)"
        set_mode_flags "$mode" || continue
        mtg_image_arg=""
        dd_image_arg=""
        if [[ "$DEPLOY_EE" -eq 1 ]]; then
          read -rp "$(t ask_new_mtg_image)" mtg_image_arg
        fi
        if [[ "$DEPLOY_DD" -eq 1 ]]; then
          read -rp "$(t ask_new_dd_image)" dd_image_arg
        fi
        if cmd_upgrade "$mtg_image_arg" "$dd_image_arg"; then
          cmd_healthcheck || true
        fi
        ;;
      5)
        cmd_self_update
        ;;
      6)
        mode="$(prompt_mode_all)"
        set_mode_flags "$mode" || continue
        migrate_ee_domain=""
        migrate_dd_domain=""
        migrate_front_domain=""
        if [[ "$DEPLOY_EE" -eq 1 ]]; then
          ask_domain ask_ee_domain migrate_ee_domain
          ask_front_domain_with_options
          migrate_front_domain="$FRONT_DOMAIN"
        fi
        if [[ "$DEPLOY_DD" -eq 1 ]]; then
          ask_domain ask_dd_domain migrate_dd_domain
        fi
        cmd_migrate "$migrate_ee_domain" "$migrate_dd_domain" "$migrate_front_domain"
        ;;
      7)
        mode="$(prompt_mode_all)"
        set_mode_flags "$mode" || continue
        read -rp "$(t ask_backup_id)" backup_id
        cmd_rollback "$backup_id"
        ;;
      8)
        rotate_mode="$(prompt_mode_rotate)"
        read -rp "$(t ask_new_secret)" rotate_secret
        rotate_front=""
        if [[ "$rotate_mode" == "ee" ]]; then
          read -rp "$(t ask_front_for_auto_secret)" rotate_front
        fi
        if cmd_rotate_secret "$rotate_mode" "$rotate_secret" "$rotate_front"; then
          set_mode_flags "$rotate_mode" || continue
          cmd_healthcheck || true
        fi
        ;;
      9)
        mode="$(prompt_mode_all)"
        set_mode_flags "$mode" || continue
        if confirm_continue; then
          cmd_uninstall
        fi
        ;;
      10)
        usage
        ;;
      0)
        return 0
        ;;
      *)
        t err_choice_invalid
        ;;
    esac
  done
}

main() {
  local cmd="${1:-install}"
  local mode="all"
  local mtg_image_arg=""
  local dd_image_arg=""
  local ee_domain_arg=""
  local dd_domain_arg=""
  local front_domain_arg=""
  local backup_id=""
  local rotate_mode=""
  local rotate_secret=""
  local rotate_front=""

  if [[ "$cmd" != "-h" && "$cmd" != "--help" && "$cmd" != "help" ]]; then
    acquire_run_lock
  fi

  if [[ "$#" -eq 0 ]]; then
    interactive_menu
    return 0
  fi

  case "$cmd" in
    install)
      command_install
      ;;
    migrate)
      shift || true
      while (($#)); do
        case "$1" in
          --mode)
            mode="${2:-all}"
            shift 2
            ;;
          --ee-domain)
            ee_domain_arg="${2:-}"
            shift 2
            ;;
          --dd-domain)
            dd_domain_arg="${2:-}"
            shift 2
            ;;
          --front-domain)
            front_domain_arg="${2:-}"
            shift 2
            ;;
          *)
            printf '%s %s\n' "$(t err_unknown_arg)" "$1"
            usage
            exit 1
            ;;
        esac
      done
      set_mode_flags "$mode" || exit 1
      cmd_migrate "$ee_domain_arg" "$dd_domain_arg" "$front_domain_arg"
      ;;
    rollback)
      shift || true
      while (($#)); do
        case "$1" in
          --mode)
            mode="${2:-all}"
            shift 2
            ;;
          --backup-id)
            backup_id="${2:-}"
            shift 2
            ;;
          *)
            printf '%s %s\n' "$(t err_unknown_arg)" "$1"
            usage
            exit 1
            ;;
        esac
      done
      set_mode_flags "$mode" || exit 1
      cmd_rollback "$backup_id"
      ;;
    self-update | self_update)
      shift || true
      if (($#)); then
        printf '%s %s\n' "$(t err_unknown_arg)" "$1"
        usage
        exit 1
      fi
      cmd_self_update
      ;;
    uninstall)
      shift || true
      while (($#)); do
        case "$1" in
          --mode)
            mode="${2:-all}"
            shift 2
            ;;
          *)
            printf '%s %s\n' "$(t err_unknown_arg)" "$1"
            usage
            exit 1
            ;;
        esac
      done
      set_mode_flags "$mode" || exit 1
      cmd_uninstall
      ;;
    upgrade)
      shift || true
      while (($#)); do
        case "$1" in
          --mode)
            mode="${2:-all}"
            shift 2
            ;;
          --mtg-image)
            mtg_image_arg="${2:-}"
            shift 2
            ;;
          --dd-image)
            dd_image_arg="${2:-}"
            shift 2
            ;;
          *)
            printf '%s %s\n' "$(t err_unknown_arg)" "$1"
            usage
            exit 1
            ;;
        esac
      done
      set_mode_flags "$mode" || exit 1
      cmd_upgrade "$mtg_image_arg" "$dd_image_arg"
      cmd_healthcheck
      ;;
    healthcheck)
      shift || true
      while (($#)); do
        case "$1" in
          --mode)
            mode="${2:-all}"
            shift 2
            ;;
          *)
            printf '%s %s\n' "$(t err_unknown_arg)" "$1"
            usage
            exit 1
            ;;
        esac
      done
      set_mode_flags "$mode" || exit 1
      cmd_healthcheck
      ;;
    self-heal | self_heal)
      shift || true
      while (($#)); do
        case "$1" in
          --mode)
            mode="${2:-all}"
            shift 2
            ;;
          *)
            printf '%s %s\n' "$(t err_unknown_arg)" "$1"
            usage
            exit 1
            ;;
        esac
      done
      set_mode_flags "$mode" || exit 1
      cmd_self_heal
      ;;
    rotate-secret | rotate_secret)
      shift || true
      while (($#)); do
        case "$1" in
          --mode)
            rotate_mode="${2:-}"
            shift 2
            ;;
          --secret)
            rotate_secret="${2:-}"
            shift 2
            ;;
          --front-domain)
            rotate_front="${2:-}"
            shift 2
            ;;
          *)
            printf '%s %s\n' "$(t err_unknown_arg)" "$1"
            usage
            exit 1
            ;;
        esac
      done
      if [[ -z "$rotate_mode" ]]; then
        t err_rotate_mode_required
        exit 1
      fi
      cmd_rotate_secret "$rotate_mode" "$rotate_secret" "$rotate_front"
      set_mode_flags "$rotate_mode" || exit 1
      cmd_healthcheck
      ;;
    -h | --help | help)
      usage
      ;;
    *)
      printf '%s %s\n' "$(t err_unknown_cmd)" "$cmd"
      usage
      exit 1
      ;;
  esac
}

main "$@"
