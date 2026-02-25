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
        ask_ee_port) echo "Choose port for EE (recommended: 443). Enter a number: " ;;
        ask_dd_port) echo "Choose port for DD (recommended: 8443). Enter a number: " ;;
        ask_enable_bbr) echo "Enable BBR+fq (recommended) [Y/n]: " ;;
        ask_continue_anyway) echo "Continue anyway? [y/N]: " ;;
        err_port_num) echo "Port must be a number between 1 and 65535." ;;
        err_port_conflict) echo "EE port and DD port cannot be the same on a single IP. Choose different ports." ;;
        err_port_in_use) echo "Port is already in use on this server. Choose another one." ;;
        err_empty) echo "This value cannot be empty." ;;
        err_mode_invalid) echo "Invalid mode. Choose 1, 2, or 3." ;;
        err_domain_invalid) echo "Invalid domain format. Example: sub.example.com" ;;
        warn_dns_unresolved) echo "Warning: domain has no A record yet." ;;
        warn_dns_mismatch) echo "Warning: domain A records do not include this server IPv4." ;;
        warn_bbr_unsupported) echo "Warning: kernel does not advertise BBR support. Skipping BBR tuning." ;;
        warn_bbr_apply_fail) echo "Warning: failed to apply sysctl settings. Continuing without BBR changes." ;;
        tls_ok) echo "TLS handshake OK." ;;
        tls_fail) echo "TLS handshake FAILED or timed out. FakeTLS may be unstable with this fronting domain." ;;
        tls_abort) echo "Aborted because TLS check failed and user did not confirm continuation." ;;
        note_secret) echo "Do NOT share secrets publicly. Anyone with the secret can use your proxy." ;;
        note_no_cdn) echo "Important: DNS should be 'DNS only' (no CDN proxy). MTProto is not standard HTTPS." ;;
        err_image_ref_invalid) echo "Image reference must be digest format: name@sha256:64hex. Please set MTG_IMAGE/DD_IMAGE." ;;
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
        ask_ee_port) echo "请选择 EE 端口（推荐 443）。请输入端口号： " ;;
        ask_dd_port) echo "请选择 DD 端口（推荐 8443）。请输入端口号： " ;;
        ask_enable_bbr) echo "是否启用 BBR+fq（推荐）[Y/n]： " ;;
        ask_continue_anyway) echo "是否仍继续？[y/N]： " ;;
        err_port_num) echo "端口必须是 1~65535 的数字。" ;;
        err_port_conflict) echo "同一台机器的同一个 IP 上，EE 和 DD 不能使用同一个端口。请选不同端口。" ;;
        err_port_in_use) echo "该端口在本机已被占用。请换一个端口。" ;;
        err_empty) echo "该项不能为空。" ;;
        err_mode_invalid) echo "模式输入无效，请输入 1、2 或 3。" ;;
        err_domain_invalid) echo "域名格式不合法，例如：sub.example.com" ;;
        warn_dns_unresolved) echo "警告：该域名当前没有 A 记录。" ;;
        warn_dns_mismatch) echo "警告：该域名的 A 记录未包含本机 IPv4。" ;;
        warn_bbr_unsupported) echo "警告：当前内核未显示支持 BBR，跳过 BBR 配置。" ;;
        warn_bbr_apply_fail) echo "警告：sysctl 配置应用失败，将继续但不保证 BBR 生效。" ;;
        tls_ok) echo "TLS 握手正常。" ;;
        tls_fail) echo "TLS 握手失败或超时。FakeTLS 可能不稳定，建议更换 fronting 域名。" ;;
        tls_abort) echo "由于 TLS 检测失败且未确认继续，脚本已中止。" ;;
        note_secret) echo "不要公开分享 secret。任何拿到 secret 的人都能使用你的代理。" ;;
        note_no_cdn) echo "重要：DNS 必须是 DNS only/灰云（不要 CDN 代理）。MTProto 不是标准 HTTPS。" ;;
        err_image_ref_invalid) echo "镜像引用必须是 digest 格式：name@sha256:64位十六进制。请设置 MTG_IMAGE/DD_IMAGE。" ;;
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
        ask_ee_port) echo "EE 포트 선택(권장: 443). 포트 번호 입력: " ;;
        ask_dd_port) echo "DD 포트 선택(권장: 8443). 포트 번호 입력: " ;;
        ask_enable_bbr) echo "BBR+fq 활성화(권장) [Y/n]: " ;;
        ask_continue_anyway) echo "계속 진행할까요? [y/N]: " ;;
        err_port_num) echo "포트는 1~65535 사이의 숫자여야 합니다." ;;
        err_port_conflict) echo "같은 IP에서 EE와 DD는 동일 포트를 사용할 수 없습니다." ;;
        err_port_in_use) echo "해당 포트가 이미 사용 중입니다." ;;
        err_empty) echo "빈 값은 허용되지 않습니다." ;;
        err_mode_invalid) echo "모드 입력이 잘못되었습니다. 1, 2, 3 중에서 선택하세요." ;;
        err_domain_invalid) echo "도메인 형식이 올바르지 않습니다. 예: sub.example.com" ;;
        warn_dns_unresolved) echo "경고: 도메인에 A 레코드가 없습니다." ;;
        warn_dns_mismatch) echo "경고: 도메인 A 레코드에 서버 IPv4가 없습니다." ;;
        warn_bbr_unsupported) echo "경고: 커널에서 BBR 지원이 확인되지 않아 건너뜁니다." ;;
        warn_bbr_apply_fail) echo "경고: sysctl 적용 실패. BBR 없이 계속 진행합니다." ;;
        tls_ok) echo "TLS 핸드셰이크 OK." ;;
        tls_fail) echo "TLS 핸드셰이크 실패/타임아웃." ;;
        tls_abort) echo "TLS 검사 실패 후 계속 확인이 없어 중단합니다." ;;
        note_secret) echo "시크릿을 공개 공유하지 마세요." ;;
        note_no_cdn) echo "중요: DNS only(프록시/CDN 금지)." ;;
        err_image_ref_invalid) echo "이미지 참조는 digest 형식(name@sha256:64hex)이어야 합니다. MTG_IMAGE/DD_IMAGE를 설정하세요." ;;
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
        ask_ee_port) echo "EEのポート（推奨: 443）。番号を入力: " ;;
        ask_dd_port) echo "DDのポート（推奨: 8443）。番号を入力: " ;;
        ask_enable_bbr) echo "BBR+fqを有効化（推奨）[Y/n]: " ;;
        ask_continue_anyway) echo "このまま続行しますか？ [y/N]: " ;;
        err_port_num) echo "ポートは1〜65535の数字である必要があります。" ;;
        err_port_conflict) echo "同一IPではEEとDDを同じポートにできません。" ;;
        err_port_in_use) echo "そのポートは既に使用中です。" ;;
        err_empty) echo "空欄は不可です。" ;;
        err_mode_invalid) echo "モード入力が不正です。1、2、3から選択してください。" ;;
        err_domain_invalid) echo "ドメイン形式が不正です。例: sub.example.com" ;;
        warn_dns_unresolved) echo "警告：ドメインにAレコードがありません。" ;;
        warn_dns_mismatch) echo "警告：ドメインAレコードにこのサーバーIPv4がありません。" ;;
        warn_bbr_unsupported) echo "警告：カーネルがBBR対応を示していないためスキップします。" ;;
        warn_bbr_apply_fail) echo "警告：sysctl適用に失敗。BBR変更なしで続行します。" ;;
        tls_ok) echo "TLSハンドシェイクOK。" ;;
        tls_fail) echo "TLSハンドシェイク失敗/タイムアウト。" ;;
        tls_abort) echo "TLS確認失敗かつ続行確認なしのため中止しました。" ;;
        note_secret) echo "シークレットを公開しないでください。" ;;
        note_no_cdn) echo "重要：DNSはDNS only（CDNプロキシ禁止）。" ;;
        err_image_ref_invalid) echo "イメージ参照はdigest形式(name@sha256:64hex)である必要があります。MTG_IMAGE/DD_IMAGEを設定してください。" ;;
      esac
      ;;
  esac
}

# ---------- Utilities ----------
is_port_number() {
  [[ "$1" =~ ^[0-9]+$ ]] && (( "$1" >= 1 && "$1" <= 65535 ))
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
      echo "$(t err_empty)"
      continue
    fi
    if ! is_valid_domain "$value"; then
      echo "$(t err_domain_invalid)"
      continue
    fi
    printf -v "$var_name" "%s" "$value"
    return 0
  done
}

ask_port() {
  local prompt_key="$1"
  local var_name="$2"
  local p=""
  while true; do
    echo -n "$(t "$prompt_key")"
    read -r p
    p="${p// /}"
    if ! is_port_number "$p"; then
      echo "$(t err_port_num)"
      continue
    fi
    if port_in_use "$p"; then
      echo "$(t err_port_in_use)"
      continue
    fi
    printf -v "$var_name" "%s" "$p"
    return 0
  done
}

ask_deploy_mode() {
  local mode=""
  while true; do
    echo "$(t ask_mode)"
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
        echo "$(t err_mode_invalid)"
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
    echo "$(t warn_dns_unresolved) (${domain})"
    confirm_continue || return 1
    return 0
  fi

  if [[ -n "$server_ip" ]] && ! grep -qx "$server_ip" <<<"$records"; then
    echo "$(t warn_dns_mismatch) (${domain})"
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
    echo "$(t err_image_ref_invalid)"
    echo "MTG_IMAGE=${MTG_IMAGE}"
    exit 1
  fi
  if [[ "$DEPLOY_DD" -eq 1 ]] && ! is_valid_digest_image_ref "$DD_IMAGE"; then
    echo "$(t err_image_ref_invalid)"
    echo "DD_IMAGE=${DD_IMAGE}"
    exit 1
  fi
}

# ---------- Start ----------
select_language
echo
echo "============================================================"
echo "$(t title)"
echo "============================================================"
echo "$(t need_dns)"
echo "$(t note_no_cdn)"
echo

# Inputs
ask_deploy_mode

EE_DOMAIN=""
DD_DOMAIN=""
FRONT_DOMAIN=""
EE_PORT=""
DD_PORT=""
EE_SECRET=""
DD_BASE_SECRET=""
DD_SECRET=""

if [[ "$DEPLOY_EE" -eq 1 ]]; then
  ask_domain ask_ee_domain EE_DOMAIN

  echo -n "$(t ask_front_domain)"
  read -r FRONT_DOMAIN
  FRONT_DOMAIN="${FRONT_DOMAIN:-www.cloudflare.com}"
  FRONT_DOMAIN="${FRONT_DOMAIN//[[:space:]]/}"
  FRONT_DOMAIN="${FRONT_DOMAIN,,}"
  if ! is_valid_domain "$FRONT_DOMAIN"; then
    echo "$(t err_domain_invalid)"
    exit 1
  fi

  ask_port ask_ee_port EE_PORT
fi

if [[ "$DEPLOY_DD" -eq 1 ]]; then
  ask_domain ask_dd_domain DD_DOMAIN
  ask_port ask_dd_port DD_PORT
fi

if [[ "$DEPLOY_EE" -eq 1 && "$DEPLOY_DD" -eq 1 && "$EE_PORT" == "$DD_PORT" ]]; then
  echo "$(t err_port_conflict)"
  exit 1
fi

echo -n "$(t ask_enable_bbr)"
read -r ENABLE_BBR
ENABLE_BBR="${ENABLE_BBR:-Y}"

# Step: Update + tools
echo
echo "$(t step_update)"
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release ufw openssl jq dnsutils iproute2

# Step: DNS checks
echo
echo "$(t step_dns_check)"
SERVER_IPV4="$(get_primary_ipv4)"
if [[ "$DEPLOY_EE" -eq 1 ]]; then
  check_domain_dns "$EE_DOMAIN" "$SERVER_IPV4"
fi
if [[ "$DEPLOY_DD" -eq 1 ]]; then
  check_domain_dns "$DD_DOMAIN" "$SERVER_IPV4"
fi

# Step: Docker
echo
echo "$(t step_docker)"
if ! command -v docker >/dev/null 2>&1; then
  apt-get install -y docker.io
fi
systemctl enable --now docker

# Step: Optional BBR
if [[ "$ENABLE_BBR" =~ ^[Yy]$ ]]; then
  echo
  echo "$(t step_bbr_q)"
  if sysctl net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -qw bbr; then
    cat >/etc/sysctl.d/99-bbr.conf <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
    if ! sysctl --system >/dev/null 2>&1; then
      echo "$(t warn_bbr_apply_fail)"
    fi
  else
    echo "$(t warn_bbr_unsupported)"
  fi
fi

# Step: Firewall (safe order)
echo
echo "$(t step_firewall)"
ufw allow OpenSSH >/dev/null 2>&1 || true
while read -r ssh_port; do
  [[ -n "$ssh_port" ]] || continue
  ufw allow "${ssh_port}/tcp" >/dev/null
done < <(collect_sshd_ports)
if [[ "$DEPLOY_EE" -eq 1 ]]; then
  ufw allow "${EE_PORT}/tcp" >/dev/null
fi
if [[ "$DEPLOY_DD" -eq 1 ]]; then
  ufw allow "${DD_PORT}/tcp" >/dev/null
fi
if ufw status | grep -qi inactive; then
  ufw --force enable >/dev/null
fi
ufw reload >/dev/null

# Step: Pull images
validate_image_refs
echo
echo "$(t step_pull)"
if [[ "$DEPLOY_EE" -eq 1 ]]; then
  docker pull "$MTG_IMAGE" >/dev/null
fi
if [[ "$DEPLOY_DD" -eq 1 ]]; then
  docker pull "$DD_IMAGE" >/dev/null
fi

if [[ "$DEPLOY_EE" -eq 1 ]]; then
  # Step: Test TLS to fronting
  echo
  echo "$(t step_front_test) (${FRONT_DOMAIN})"
  if timeout 6 openssl s_client -connect "${FRONT_DOMAIN}:443" -servername "${FRONT_DOMAIN}" </dev/null >/dev/null 2>&1; then
    echo "$(t tls_ok)"
  else
    echo "$(t tls_fail)"
    if ! confirm_continue; then
      echo "$(t tls_abort)"
      exit 1
    fi
  fi

  # Step: Generate EE secret & config
  echo
  echo "$(t step_gen_ee)"
  EE_SECRET="$(docker run --rm "$MTG_IMAGE" generate-secret --hex "$FRONT_DOMAIN" | tr -d '\r\n')"
  mkdir -p /opt/mtg
  cat >/opt/mtg/config.toml <<EOF
secret = "$EE_SECRET"
bind-to = "0.0.0.0:3128"
EOF

  # Step: Run EE
  echo
  echo "$(t step_run_ee) (port ${EE_PORT})"
  docker rm -f mtg-ee >/dev/null 2>&1 || true
  docker run -d --name mtg-ee \
    --restart unless-stopped \
    -v /opt/mtg/config.toml:/config.toml \
    -p "${EE_PORT}:3128" \
    "$MTG_IMAGE" >/dev/null
fi

if [[ "$DEPLOY_DD" -eq 1 ]]; then
  # Step: Generate DD secret
  echo
  echo "$(t step_gen_dd)"
  DD_BASE_SECRET="$(openssl rand -hex 16)"
  DD_SECRET="dd${DD_BASE_SECRET}"

  # Step: Run DD
  echo
  echo "$(t step_run_dd) (port ${DD_PORT})"
  docker rm -f mtproto-dd >/dev/null 2>&1 || true
  docker run -d --name mtproto-dd \
    --restart unless-stopped \
    -p "${DD_PORT}:443" \
    -e SECRET="${DD_BASE_SECRET}" \
    "$DD_IMAGE" >/dev/null
fi

# Summary
echo
echo "$(t step_summary)"
echo "$(t note_secret)"
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
  echo "================= EE (FakeTLS / mtg) ================="
  echo "Entry domain : ${EE_DOMAIN}"
  echo "Port         : ${EE_PORT}"
  echo "Fronting     : ${FRONT_DOMAIN}"
  echo "Secret (EE)  : ${EE_SECRET}"
  echo "Import link  : tg://proxy?server=${EE_DOMAIN}&port=${EE_PORT}&secret=${EE_SECRET}"
  echo
fi
if [[ "$DEPLOY_DD" -eq 1 ]]; then
  echo "================= DD (padding / MTProxy) ============="
  echo "Entry domain : ${DD_DOMAIN}"
  echo "Port         : ${DD_PORT}"
  echo "Secret (DD)  : ${DD_SECRET}"
  echo "Import link  : tg://proxy?server=${DD_DOMAIN}&port=${DD_PORT}&secret=${DD_SECRET}"
  echo
fi
echo "Docker status:"
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'
echo
echo "Firewall status:"
ufw status numbered || true
