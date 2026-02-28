# Telegram MTProto Proxy Installer (EE + DD)

[English](#english) | [中文](#chinese) | [한국어](#korean) | [日本語](#japanese)

A one-click interactive installer for Telegram MTProto proxy on Ubuntu 22.04.

- EE (FakeTLS): `nineseconds/mtg`
- DD (padding): `telegrammessenger/proxy`
- Entry script: `install.sh`

<a id="english"></a>
## English

### Features
- Deploy mode: `EE only` / `DD only` / `EE+DD`
- Fronting domain: preset options + single manual input
- Port: preset options + manual input, conflict detection, optional old-proxy cleanup
- Bind IP selection for multi-IP hosts
- Optional strict UFW rules scoped to selected bind IP(s)
- `systemd` managed services for EE/DD
- Ops commands: `healthcheck`, `self-heal`, `upgrade`, `uninstall`, `rotate-secret`
- Preflight checks: OS/memory/disk/time sync/DNS
- Security defaults: pinned image digest, hardened container flags
- CI quality checks: `shellcheck` + `shfmt`

### Requirements
- Ubuntu 22.04
- Root privilege
- Domain A records already point to your VPS (`DNS only`, no CDN proxy)

### Quick Start
```bash
git -C ~/telegram-proxy-20260226 pull || git clone https://github.com/k3-on/telegram-proxy-20260226.git ~/telegram-proxy-20260226; sudo bash ~/telegram-proxy-20260226/install.sh
```

### Operations
```bash
# health checks
sudo bash install.sh healthcheck --mode all

# self-heal if unhealthy
sudo bash install.sh self-heal --mode all

# upgrade image digest(s)
sudo bash install.sh upgrade --mode ee --mtg-image 'nineseconds/mtg@sha256:<digest>'
sudo bash install.sh upgrade --mode dd --dd-image 'telegrammessenger/proxy@sha256:<digest>'

# self-update script repo
sudo bash install.sh self-update

# manual secret rotation
sudo bash install.sh rotate-secret --mode ee --secret '<new_ee_secret_hex>'
sudo bash install.sh rotate-secret --mode dd --secret 'dd<32hex>'  # or just 32hex

# uninstall
sudo bash install.sh uninstall --mode all
```

### Pinned Digests
The script requires digest-style image references (`name@sha256:...`).

Current defaults:
- `MTG_IMAGE="nineseconds/mtg@sha256:f0e90be754c59e729bc4e219eeb210a602f7ad4e39167833166a176cd6fa0461"`
- `DD_IMAGE="telegrammessenger/proxy@sha256:73210d43c8f8e4c888ba4e30d6daf7742528e9134252a1cd538caabf5e24a597"`

Optional override:
```bash
export MTG_IMAGE='nineseconds/mtg@sha256:<64-hex-digest>'
export DD_IMAGE='telegrammessenger/proxy@sha256:<64-hex-digest>'
sudo -E bash install.sh
```

Fetch digest in a networked environment:
```bash
docker pull nineseconds/mtg:2
docker pull telegrammessenger/proxy:latest
docker image inspect nineseconds/mtg:2 --format '{{index .RepoDigests 0}}'
docker image inspect telegrammessenger/proxy:latest --format '{{index .RepoDigests 0}}'
```

<a id="chinese"></a>
## 中文

### 功能
- 部署模式：`仅 EE` / `仅 DD` / `EE+DD`
- Fronting 域名：预设选项 + 单个手动输入
- 端口：预设选项 + 手动输入，冲突检测，可选清理旧代理容器
- 支持绑定 IP（多公网 IP 场景）
- 可选启用按绑定 IP 精确放行的严格 UFW 规则
- 使用 `systemd` 托管 EE/DD 服务
- 运维命令：`healthcheck`、`self-heal`、`upgrade`、`uninstall`、`rotate-secret`
- 增强前置检查：系统/内存/磁盘/时间同步/DNS
- 安全默认：固定 digest、容器安全参数加固
- CI 质量检查：`shellcheck` + `shfmt`

### 前置条件
- Ubuntu 22.04
- root 权限
- 域名 A 记录已解析到 VPS（`DNS only`，不要 CDN 代理）

### 快速开始
```bash
git -C ~/telegram-proxy-20260226 pull || git clone https://github.com/k3-on/telegram-proxy-20260226.git ~/telegram-proxy-20260226; sudo bash ~/telegram-proxy-20260226/install.sh
```

### 运维命令
```bash
# 健康检查
sudo bash install.sh healthcheck --mode all

# 异常自愈
sudo bash install.sh self-heal --mode all

# 升级镜像 digest
sudo bash install.sh upgrade --mode ee --mtg-image 'nineseconds/mtg@sha256:<digest>'
sudo bash install.sh upgrade --mode dd --dd-image 'telegrammessenger/proxy@sha256:<digest>'

# 脚本自更新
sudo bash install.sh self-update

# 手动轮换 secret
sudo bash install.sh rotate-secret --mode ee --secret '<new_ee_secret_hex>'
sudo bash install.sh rotate-secret --mode dd --secret 'dd<32hex>'  # 或仅 32hex

# 卸载
sudo bash install.sh uninstall --mode all
```

### 固定 Digest
脚本要求镜像使用 digest 形式（`name@sha256:...`）。

当前默认值：
- `MTG_IMAGE="nineseconds/mtg@sha256:f0e90be754c59e729bc4e219eeb210a602f7ad4e39167833166a176cd6fa0461"`
- `DD_IMAGE="telegrammessenger/proxy@sha256:73210d43c8f8e4c888ba4e30d6daf7742528e9134252a1cd538caabf5e24a597"`

可选覆盖：
```bash
export MTG_IMAGE='nineseconds/mtg@sha256:<64位十六进制digest>'
export DD_IMAGE='telegrammessenger/proxy@sha256:<64位十六进制digest>'
sudo -E bash install.sh
```

联网环境下查询 digest：
```bash
docker pull nineseconds/mtg:2
docker pull telegrammessenger/proxy:latest
docker image inspect nineseconds/mtg:2 --format '{{index .RepoDigests 0}}'
docker image inspect telegrammessenger/proxy:latest --format '{{index .RepoDigests 0}}'
```

<a id="korean"></a>
## 한국어

### 기능
- 배포 모드: `EE만` / `DD만` / `EE+DD`
- Fronting 도메인: 프리셋 + 단일 수동 입력
- 포트: 프리셋 + 수동 입력, 충돌 감지, 기존 프록시 정리 옵션
- 멀티 공인 IP 환경에서 바인드 IP 선택 지원
- 선택한 바인드 IP에 한정한 엄격 UFW 규칙(옵션)
- EE/DD 서비스를 `systemd` 로 관리
- 운영 명령: `healthcheck`, `self-heal`, `upgrade`, `uninstall`, `rotate-secret`
- 사전 점검: OS/메모리/디스크/시간 동기화/DNS
- 보안 기본값: digest 고정, 컨테이너 보안 옵션 강화
- CI 품질 검사: `shellcheck` + `shfmt`

### 요구사항
- Ubuntu 22.04
- root 권한
- 도메인 A 레코드가 VPS를 가리켜야 함 (`DNS only`, CDN 프록시 금지)

### 빠른 시작
```bash
git -C ~/telegram-proxy-20260226 pull || git clone https://github.com/k3-on/telegram-proxy-20260226.git ~/telegram-proxy-20260226; sudo bash ~/telegram-proxy-20260226/install.sh
```

### 운영 명령
```bash
# 상태 점검
sudo bash install.sh healthcheck --mode all

# 자동 복구
sudo bash install.sh self-heal --mode all

# 이미지 digest 업그레이드
sudo bash install.sh upgrade --mode ee --mtg-image 'nineseconds/mtg@sha256:<digest>'
sudo bash install.sh upgrade --mode dd --dd-image 'telegrammessenger/proxy@sha256:<digest>'

# 스크립트 자체 업데이트
sudo bash install.sh self-update

# secret 수동 교체
sudo bash install.sh rotate-secret --mode ee --secret '<new_ee_secret_hex>'
sudo bash install.sh rotate-secret --mode dd --secret 'dd<32hex>'  # 또는 32hex

# 제거
sudo bash install.sh uninstall --mode all
```

### 고정 Digest
스크립트는 digest 형식(`name@sha256:...`) 이미지만 허용합니다.

현재 기본값:
- `MTG_IMAGE="nineseconds/mtg@sha256:f0e90be754c59e729bc4e219eeb210a602f7ad4e39167833166a176cd6fa0461"`
- `DD_IMAGE="telegrammessenger/proxy@sha256:73210d43c8f8e4c888ba4e30d6daf7742528e9134252a1cd538caabf5e24a597"`

선택적으로 덮어쓰기:
```bash
export MTG_IMAGE='nineseconds/mtg@sha256:<64-hex-digest>'
export DD_IMAGE='telegrammessenger/proxy@sha256:<64-hex-digest>'
sudo -E bash install.sh
```

네트워크 환경에서 digest 조회:
```bash
docker pull nineseconds/mtg:2
docker pull telegrammessenger/proxy:latest
docker image inspect nineseconds/mtg:2 --format '{{index .RepoDigests 0}}'
docker image inspect telegrammessenger/proxy:latest --format '{{index .RepoDigests 0}}'
```

<a id="japanese"></a>
## 日本語

### 機能
- デプロイモード: `EEのみ` / `DDのみ` / `EE+DD`
- fronting ドメイン: プリセット + 単一手動入力
- ポート: プリセット + 手動入力、競合検出、旧プロキシ整理オプション
- マルチIP環境でバインドIP選択に対応
- 選択したバインドIPに限定する厳格なUFWルール（任意）
- EE/DD を `systemd` で管理
- 運用コマンド: `healthcheck`、`self-heal`、`upgrade`、`uninstall`、`rotate-secret`
- 事前チェック: OS/メモリ/ディスク/時刻同期/DNS
- セキュリティ既定: digest 固定、コンテナ安全オプション強化
- CI 品質チェック: `shellcheck` + `shfmt`

### 前提条件
- Ubuntu 22.04
- root 権限
- ドメインAレコードがVPSを向いていること（`DNS only`、CDNプロキシ禁止）

### クイックスタート
```bash
git -C ~/telegram-proxy-20260226 pull || git clone https://github.com/k3-on/telegram-proxy-20260226.git ~/telegram-proxy-20260226; sudo bash ~/telegram-proxy-20260226/install.sh
```

### 運用コマンド
```bash
# ヘルスチェック
sudo bash install.sh healthcheck --mode all

# 自動復旧
sudo bash install.sh self-heal --mode all

# イメージ digest 更新
sudo bash install.sh upgrade --mode ee --mtg-image 'nineseconds/mtg@sha256:<digest>'
sudo bash install.sh upgrade --mode dd --dd-image 'telegrammessenger/proxy@sha256:<digest>'

# スクリプト自己更新
sudo bash install.sh self-update

# secret 手動ローテーション
sudo bash install.sh rotate-secret --mode ee --secret '<new_ee_secret_hex>'
sudo bash install.sh rotate-secret --mode dd --secret 'dd<32hex>'  # または 32hex

# アンインストール
sudo bash install.sh uninstall --mode all
```

### 固定 Digest
スクリプトは digest 形式（`name@sha256:...`）を必須とします。

現在の既定値:
- `MTG_IMAGE="nineseconds/mtg@sha256:f0e90be754c59e729bc4e219eeb210a602f7ad4e39167833166a176cd6fa0461"`
- `DD_IMAGE="telegrammessenger/proxy@sha256:73210d43c8f8e4c888ba4e30d6daf7742528e9134252a1cd538caabf5e24a597"`

必要に応じて上書き:
```bash
export MTG_IMAGE='nineseconds/mtg@sha256:<64-hex-digest>'
export DD_IMAGE='telegrammessenger/proxy@sha256:<64-hex-digest>'
sudo -E bash install.sh
```

ネットワーク接続環境での digest 取得:
```bash
docker pull nineseconds/mtg:2
docker pull telegrammessenger/proxy:latest
docker image inspect nineseconds/mtg:2 --format '{{index .RepoDigests 0}}'
docker image inspect telegrammessenger/proxy:latest --format '{{index .RepoDigests 0}}'
```
