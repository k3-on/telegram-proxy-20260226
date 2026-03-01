# Telegram MTProto Proxy Installer (EE + DD)

[English](#english) | [中文](#chinese) | [한국어](#korean) | [日本語](#japanese)

One-click interactive installer for Telegram MTProto proxy on Ubuntu 22.04.

- EE (FakeTLS): `nineseconds/mtg`
- DD (padding): `telegrammessenger/proxy`
- Entry script: `install.sh`

<a id="english"></a>
## English

### Features
- Deploy mode: `EE only` / `DD only` / `EE+DD`
- Fronting domain: presets + manual input
- Port: presets + manual input, conflict detection
- Multi-IP bind support
- `systemd` managed services
- Healthcheck / self-heal / self-update
- Upgrade / migrate / rollback / rotate-secret (advanced)

### Requirements
- Ubuntu 22.04
- Root privilege
- Domain A records point to your VPS (`DNS only`, no CDN proxy)

### Quick Start
```bash
git -C ~/telegram-proxy-20260226 pull || git clone https://github.com/k3-on/telegram-proxy-20260226.git ~/telegram-proxy-20260226; sudo bash ~/telegram-proxy-20260226/install.sh
```

### Common Operations
```bash
sudo bash install.sh healthcheck --mode all
sudo bash install.sh self-heal --mode all
sudo bash install.sh self-update
sudo bash install.sh uninstall --mode all
```

<details>
<summary>Advanced Operations</summary>

```bash
# upgrade image digest(s)
sudo bash install.sh upgrade --mode ee --mtg-image 'nineseconds/mtg@sha256:<digest>'
sudo bash install.sh upgrade --mode dd --dd-image 'telegrammessenger/proxy@sha256:<digest>'

# migrate legacy running containers into script-managed services
sudo bash install.sh migrate --mode all

# rollback (latest backup by default)
sudo bash install.sh rollback --mode all
sudo bash install.sh rollback --mode ee --backup-id '<backup-id>'

# manual secret rotation
sudo bash install.sh rotate-secret --mode ee --secret '<new_ee_secret_hex>'
sudo bash install.sh rotate-secret --mode dd --secret 'dd<32hex>'  # or just 32hex
```

</details>

<details>
<summary>Advanced: Pinned Digests</summary>

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

</details>

<a id="chinese"></a>
## 中文

### 功能
- 部署模式：`仅 EE` / `仅 DD` / `EE+DD`
- Fronting 域名：预设 + 手动输入
- 端口：预设 + 手动输入，冲突检测
- 支持多 IP 绑定
- `systemd` 托管服务
- 健康检查 / 自愈 / 脚本自更新
- 升级 / 迁移 / 回滚 / 轮换密钥（高级）

### 前置条件
- Ubuntu 22.04
- root 权限
- 域名 A 记录已解析到 VPS（`DNS only`，不要 CDN 代理）

### 快速开始
```bash
git -C ~/telegram-proxy-20260226 pull || git clone https://github.com/k3-on/telegram-proxy-20260226.git ~/telegram-proxy-20260226; sudo bash ~/telegram-proxy-20260226/install.sh
```

### 常用命令
```bash
sudo bash install.sh healthcheck --mode all
sudo bash install.sh self-heal --mode all
sudo bash install.sh self-update
sudo bash install.sh uninstall --mode all
```

<details>
<summary>高级命令</summary>

```bash
# 升级镜像 digest
sudo bash install.sh upgrade --mode ee --mtg-image 'nineseconds/mtg@sha256:<digest>'
sudo bash install.sh upgrade --mode dd --dd-image 'telegrammessenger/proxy@sha256:<digest>'

# 迁移旧版正在运行的容器到脚本托管
sudo bash install.sh migrate --mode all

# 回滚（默认最新备份）
sudo bash install.sh rollback --mode all
sudo bash install.sh rollback --mode ee --backup-id '<backup-id>'

# 手动轮换 secret
sudo bash install.sh rotate-secret --mode ee --secret '<new_ee_secret_hex>'
sudo bash install.sh rotate-secret --mode dd --secret 'dd<32hex>'  # 或仅 32hex
```

</details>

<details>
<summary>高级：固定 Digest</summary>

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

</details>

<a id="korean"></a>
## 한국어

### 기능
- 배포 모드: `EE만` / `DD만` / `EE+DD`
- Fronting 도메인: 프리셋 + 수동 입력
- 포트: 프리셋 + 수동 입력, 충돌 감지
- 멀티 IP 바인드 지원
- `systemd` 서비스 관리
- 상태 점검 / 자동 복구 / 스크립트 업데이트
- 업그레이드 / 마이그레이션 / 롤백 / 시크릿 교체 (고급)

### 요구사항
- Ubuntu 22.04
- root 권한
- 도메인 A 레코드가 VPS를 가리켜야 함 (`DNS only`, CDN 프록시 금지)

### 빠른 시작
```bash
git -C ~/telegram-proxy-20260226 pull || git clone https://github.com/k3-on/telegram-proxy-20260226.git ~/telegram-proxy-20260226; sudo bash ~/telegram-proxy-20260226/install.sh
```

### 기본 명령
```bash
sudo bash install.sh healthcheck --mode all
sudo bash install.sh self-heal --mode all
sudo bash install.sh self-update
sudo bash install.sh uninstall --mode all
```

<details>
<summary>고급 명령</summary>

```bash
# 이미지 digest 업그레이드
sudo bash install.sh upgrade --mode ee --mtg-image 'nineseconds/mtg@sha256:<digest>'
sudo bash install.sh upgrade --mode dd --dd-image 'telegrammessenger/proxy@sha256:<digest>'

# 레거시 실행 컨테이너를 스크립트 관리로 마이그레이션
sudo bash install.sh migrate --mode all

# 롤백 (기본: 최신 백업)
sudo bash install.sh rollback --mode all
sudo bash install.sh rollback --mode ee --backup-id '<backup-id>'

# 시크릿 수동 교체
sudo bash install.sh rotate-secret --mode ee --secret '<new_ee_secret_hex>'
sudo bash install.sh rotate-secret --mode dd --secret 'dd<32hex>'  # 또는 32hex
```

</details>

<details>
<summary>고급: 고정 Digest</summary>

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

</details>

<a id="japanese"></a>
## 日本語

### 機能
- デプロイモード: `EEのみ` / `DDのみ` / `EE+DD`
- fronting ドメイン: プリセット + 手動入力
- ポート: プリセット + 手動入力、競合検出
- マルチIPバインド対応
- `systemd` サービス管理
- ヘルスチェック / 自動復旧 / スクリプト自己更新
- アップグレード / 移行 / ロールバック / シークレット更新（上級）

### 前提条件
- Ubuntu 22.04
- root 権限
- ドメインAレコードがVPSを向いていること（`DNS only`、CDNプロキシ禁止）

### クイックスタート
```bash
git -C ~/telegram-proxy-20260226 pull || git clone https://github.com/k3-on/telegram-proxy-20260226.git ~/telegram-proxy-20260226; sudo bash ~/telegram-proxy-20260226/install.sh
```

### 基本コマンド
```bash
sudo bash install.sh healthcheck --mode all
sudo bash install.sh self-heal --mode all
sudo bash install.sh self-update
sudo bash install.sh uninstall --mode all
```

<details>
<summary>上級コマンド</summary>

```bash
# イメージ digest 更新
sudo bash install.sh upgrade --mode ee --mtg-image 'nineseconds/mtg@sha256:<digest>'
sudo bash install.sh upgrade --mode dd --dd-image 'telegrammessenger/proxy@sha256:<digest>'

# 稼働中の旧コンテナを script 管理に移行
sudo bash install.sh migrate --mode all

# ロールバック（既定: 最新バックアップ）
sudo bash install.sh rollback --mode all
sudo bash install.sh rollback --mode ee --backup-id '<backup-id>'

# secret 手動ローテーション
sudo bash install.sh rotate-secret --mode ee --secret '<new_ee_secret_hex>'
sudo bash install.sh rotate-secret --mode dd --secret 'dd<32hex>'  # または 32hex
```

</details>

<details>
<summary>上級：固定 Digest</summary>

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

</details>
