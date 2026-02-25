# Telegram MTProto Proxy Installer (EE + DD)

English | 中文 | 한국어 | 日本語

This repository provides an interactive one-click installer script for Telegram MTProto proxy deployment on Ubuntu 22.04.

- Script: `/Users/keons/Documents/GitHub/telegram-proxy-20260226/install.sh`
- Modes:
  - EE (FakeTLS) via `nineseconds/mtg`
  - DD (padding) via `telegrammessenger/proxy`

## English

### Features
- Interactive setup (domain, ports, BBR)
- i18n prompts (EN/ZH/KO/JA)
- Safer UFW order (allow first, then enable)
- TLS precheck for fronting domain
- Docker-based deployment
- Reproducible image pinning with digest (`@sha256:...`)

### Requirements
- Ubuntu 22.04
- Root privilege
- Domain A records already point to your VPS (DNS only, no CDN proxy)

### Quick Start
```bash
sudo bash /Users/keons/Documents/GitHub/telegram-proxy-20260226/install.sh
```

### Reproducible Deployment with Pinned Digests
`install.sh` requires digest-style image refs.

Default values in the script:
- `MTG_IMAGE="nineseconds/mtg@sha256:f0e90be754c59e729bc4e219eeb210a602f7ad4e39167833166a176cd6fa0461"`
- `DD_IMAGE="telegrammessenger/proxy@sha256:73210d43c8f8e4c888ba4e30d6daf7742528e9134252a1cd538caabf5e24a597"`

Set real digests before running:
```bash
export MTG_IMAGE='nineseconds/mtg@sha256:<64-hex-digest>'
export DD_IMAGE='telegrammessenger/proxy@sha256:<64-hex-digest>'
sudo -E bash /Users/keons/Documents/GitHub/telegram-proxy-20260226/install.sh
```

Example way to fetch digests in a networked environment:
```bash
docker pull nineseconds/mtg:2
docker pull telegrammessenger/proxy:latest
docker image inspect nineseconds/mtg:2 --format '{{index .RepoDigests 0}}'
docker image inspect telegrammessenger/proxy:latest --format '{{index .RepoDigests 0}}'
```

## 中文

### 功能
- 交互式安装（域名、端口、BBR）
- 四语提示（中英韩日）
- 更安全的 UFW 顺序（先放行再启用）
- fronting 域名 TLS 预检查
- 基于 Docker 部署
- 支持通过 digest 固定镜像（`@sha256:...`）实现可复现部署

### 前置条件
- Ubuntu 22.04
- root 权限
- 域名 A 记录已解析到 VPS（DNS only/灰云，不走 CDN 代理）

### 快速使用
```bash
sudo bash /Users/keons/Documents/GitHub/telegram-proxy-20260226/install.sh
```

### 固定 digest（可复现部署）
`install.sh` 会校验镜像必须是 digest 形式。

脚本默认值：
- `MTG_IMAGE="nineseconds/mtg@sha256:f0e90be754c59e729bc4e219eeb210a602f7ad4e39167833166a176cd6fa0461"`
- `DD_IMAGE="telegrammessenger/proxy@sha256:73210d43c8f8e4c888ba4e30d6daf7742528e9134252a1cd538caabf5e24a597"`

运行前请先设置真实 digest：
```bash
export MTG_IMAGE='nineseconds/mtg@sha256:<64位十六进制digest>'
export DD_IMAGE='telegrammessenger/proxy@sha256:<64位十六进制digest>'
sudo -E bash /Users/keons/Documents/GitHub/telegram-proxy-20260226/install.sh
```

联网环境下可参考：
```bash
docker pull nineseconds/mtg:2
docker pull telegrammessenger/proxy:latest
docker image inspect nineseconds/mtg:2 --format '{{index .RepoDigests 0}}'
docker image inspect telegrammessenger/proxy:latest --format '{{index .RepoDigests 0}}'
```

## 한국어

### 기능
- 대화형 설치(도메인, 포트, BBR)
- 4개 언어 안내(EN/ZH/KO/JA)
- 안전한 UFW 순서(허용 후 활성화)
- fronting 도메인 TLS 사전 점검
- Docker 기반 배포
- digest 고정(`@sha256:...`)으로 재현 가능한 배포

### 요구사항
- Ubuntu 22.04
- root 권한
- 도메인 A 레코드가 VPS를 가리켜야 함(DNS only, CDN 프록시 금지)

### 빠른 실행
```bash
sudo bash /Users/keons/Documents/GitHub/telegram-proxy-20260226/install.sh
```

### digest 고정 사용
스크립트는 digest 형식 이미지만 허용합니다.

기본값:
- `MTG_IMAGE="nineseconds/mtg@sha256:f0e90be754c59e729bc4e219eeb210a602f7ad4e39167833166a176cd6fa0461"`
- `DD_IMAGE="telegrammessenger/proxy@sha256:73210d43c8f8e4c888ba4e30d6daf7742528e9134252a1cd538caabf5e24a597"`

실제 digest 지정 후 실행:
```bash
export MTG_IMAGE='nineseconds/mtg@sha256:<64-hex-digest>'
export DD_IMAGE='telegrammessenger/proxy@sha256:<64-hex-digest>'
sudo -E bash /Users/keons/Documents/GitHub/telegram-proxy-20260226/install.sh
```

## 日本語

### 機能
- 対話式インストール（ドメイン、ポート、BBR）
- 4言語表示（英語/中国語/韓国語/日本語）
- 安全なUFW手順（許可してから有効化）
- frontingドメインのTLS事前確認
- Dockerベースのデプロイ
- digest固定（`@sha256:...`）による再現可能なデプロイ

### 前提条件
- Ubuntu 22.04
- root権限
- ドメインAレコードがVPSを向いていること（DNS only、CDNプロキシ禁止）

### クイックスタート
```bash
sudo bash /Users/keons/Documents/GitHub/telegram-proxy-20260226/install.sh
```

### digest固定
スクリプトは digest 形式のイメージ参照のみ許可します。

スクリプトのデフォルト値:
- `MTG_IMAGE="nineseconds/mtg@sha256:f0e90be754c59e729bc4e219eeb210a602f7ad4e39167833166a176cd6fa0461"`
- `DD_IMAGE="telegrammessenger/proxy@sha256:73210d43c8f8e4c888ba4e30d6daf7742528e9134252a1cd538caabf5e24a597"`

実行前に digest を設定:
```bash
export MTG_IMAGE='nineseconds/mtg@sha256:<64-hex-digest>'
export DD_IMAGE='telegrammessenger/proxy@sha256:<64-hex-digest>'
sudo -E bash /Users/keons/Documents/GitHub/telegram-proxy-20260226/install.sh
```
