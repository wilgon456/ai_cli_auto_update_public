<div align="center">

# AI CLI Auto Update

**Codex, OpenCode, Claude Code, Grok Build 등 로컬 AI 코딩 CLI를<br>
macOS와 Windows에서 매일 안전하게 최신 상태로 유지합니다.**

[![ShellCheck](https://github.com/wilgon456/ai_cli_auto_update_public/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/wilgon456/ai_cli_auto_update_public/actions/workflows/shellcheck.yml)
[![macOS](https://img.shields.io/badge/macOS-launchd-000000?logo=apple&logoColor=white)](#macos-launchd)
[![Windows](https://img.shields.io/badge/Windows-Task_Scheduler-0078D4?logo=windows11&logoColor=white)](#windows-task-scheduler)
[![License: MIT](https://img.shields.io/badge/License-MIT-22c55e.svg)](LICENSE)

설치된 도구만 업데이트 · 도구별 실패 격리 · dry-run 지원 · 버전과 로그 기록

</div>

---

## 한눈에 보기

- **멀티 플랫폼** — macOS는 Bash + `launchd`, Windows는 PowerShell + 작업 스케줄러
- **6개 CLI 지원** — Kimi, Codex, OpenCode, Antigravity, Claude Code, Grok Build
- **보수적인 기본값** — 설치되지 않은 CLI는 새로 설치하지 않고 `pass` 처리
- **실패 격리** — 한 도구의 업데이트가 실패해도 나머지 도구는 계속 진행
- **안전한 운영** — 중복 실행 잠금, timeout, 업데이트 전후 버전, 30일 로그 보관
- **선택 실행** — 원하는 CLI만 골라 확인하거나 업데이트 가능

```text
05:00 스케줄 실행
       ↓
설치 방식 감지 (Homebrew / npm / 내장 updater)
       ↓
업데이트 전 버전 → 도구별 업데이트 → 업데이트 후 버전
       ↓
~/.ai-cli-auto-update/logs/latest.log
```

## 지원하는 CLI

| 대상 | 실제 명령 | macOS 업데이트 경로 | Windows 업데이트 경로 |
| --- | --- | --- | --- |
| Kimi Code | `kimi` | npm `@moonshot-ai/kimi-code` | npm `@moonshot-ai/kimi-code` |
| OpenAI Codex | `codex` | Homebrew `codex` 또는 npm `@openai/codex` | npm `@openai/codex` |
| OpenCode | `opencode` | Homebrew `opencode` → npm `opencode-ai` → `opencode upgrade` | npm `opencode-ai` → `opencode upgrade` |
| Antigravity | `agy` | `agy update` | `agy update` |
| Claude Code | `claude` | Homebrew → npm `@anthropic-ai/claude-code` → `claude update` | npm → `claude update` |
| Grok Build | `grok` | xAI 공식 설치 스크립트 | xAI 공식 PowerShell 설치 스크립트 |

> 기본 대상은 `kimi,gpt,opencode,agy,claude,grok`입니다. `gpt`는 Codex를 가리키는 선택 이름이며, 기존 자동화 호환을 위해 `codex`도 같은 대상으로 인식합니다.

## 빠른 시작

### macOS

```bash
git clone https://github.com/wilgon456/ai_cli_auto_update_public.git
cd ai_cli_auto_update_public

# 변경 없이 감지 결과와 실행 흐름 확인
./bin/update_ai_clis.sh --dry-run

# 설치된 기본 대상 업데이트
./bin/update_ai_clis.sh
```

특정 도구만 실행할 수도 있습니다.

```bash
./bin/update_ai_clis.sh --targets codex,opencode,claude,grok
```

### Windows PowerShell

```powershell
git clone https://github.com/wilgon456/ai_cli_auto_update_public.git
cd ai_cli_auto_update_public

# 변경 없이 감지 결과와 실행 흐름 확인
.\bin\update_ai_clis.ps1 -DryRun

# 설치된 기본 대상 업데이트
.\bin\update_ai_clis.ps1
```

특정 도구만 실행할 수도 있습니다.

```powershell
.\bin\update_ai_clis.ps1 -Targets codex,opencode,claude,grok
```

## 자동 실행 설정

### macOS: launchd

저장소의 템플릿은 매일 **05:00**에 실행되도록 구성되어 있습니다.

```bash
mkdir -p ~/Library/LaunchAgents
cp launchd/com.example.ai-cli-auto-update.plist \
  ~/Library/LaunchAgents/com.example.ai-cli-auto-update.plist
```

복사한 plist에서 다음 경로를 실제 clone 위치와 사용자 홈에 맞게 수정합니다.

```xml
<string>/path/to/ai_cli_auto_update/bin/update_ai_clis.sh</string>
<string>/Users/your-user/.ai-cli-auto-update/launchd.out.log</string>
<string>/Users/your-user/.ai-cli-auto-update/launchd.err.log</string>
```

설정을 등록합니다.

```bash
launchctl load ~/Library/LaunchAgents/com.example.ai-cli-auto-update.plist
launchctl list | grep ai-cli-auto-update
```

plist를 수정한 경우 다시 로드합니다.

```bash
launchctl unload ~/Library/LaunchAgents/com.example.ai-cli-auto-update.plist 2>/dev/null || true
launchctl load ~/Library/LaunchAgents/com.example.ai-cli-auto-update.plist
```

### Windows: Task Scheduler

관리자 권한 없이 현재 사용자 작업으로 매일 **05:00** 실행되도록 등록합니다.

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\windows\install_scheduled_task.ps1
```

등록 결과를 확인하거나 즉시 실행할 수 있습니다.

```powershell
Get-ScheduledTask -TaskName "AI CLI Auto Update"
Start-ScheduledTask -TaskName "AI CLI Auto Update"
```

실행 시각과 대상을 직접 지정하려면 다음처럼 등록합니다.

```powershell
.\windows\install_scheduled_task.ps1 `
  -At "05:00" `
  -Targets "codex,opencode,claude,grok"
```

## 설정

### 대상 선택

| 환경 | 명령 예시 |
| --- | --- |
| Bash 인자 | `./bin/update_ai_clis.sh --targets kimi,codex,opencode` |
| Bash 환경변수 | `AI_CLI_TARGETS=kimi,codex,opencode ./bin/update_ai_clis.sh` |
| PowerShell | `.\bin\update_ai_clis.ps1 -Targets kimi,codex,opencode` |
| 전체 대상 | `--targets all` 또는 `-Targets all` |

### 미설치 도구 설치

기본값에서는 설치되지 않은 CLI를 건너뜁니다. 새 도구 설치는 반드시 명시적으로 허용해야 합니다.

```bash
./bin/update_ai_clis.sh --targets opencode --install-missing
```

```powershell
.\bin\update_ai_clis.ps1 -Targets opencode -InstallMissing
```

### 로그와 보관 기간

| OS | 기본 로그 위치 |
| --- | --- |
| macOS / Bash | `~/.ai-cli-auto-update/logs/` |
| Windows | `%USERPROFILE%\.ai-cli-auto-update\logs\` |

각 실행은 timestamp 로그와 `latest.log`를 남깁니다. 기본 보관 기간은 30일입니다.

```bash
LOG_RETENTION_DAYS=14 ./bin/update_ai_clis.sh
LOG_DIR=/path/to/logs ./bin/update_ai_clis.sh
```

```powershell
.\bin\update_ai_clis.ps1 -LogRetentionDays 14
.\bin\update_ai_clis.ps1 -LogDir "C:\logs\ai-cli-update"
```

## 안전 장치

| 장치 | 동작 |
| --- | --- |
| 중복 실행 방지 | Bash lock directory / Windows 사용자별 mutex |
| dry-run | 실제 업데이트와 로그 정리 없이 실행 흐름 확인 |
| 실패 격리 | 한 CLI가 실패해도 다음 CLI 업데이트 계속 진행 |
| 설치 보호 | `--install-missing` 또는 `-InstallMissing` 없이는 새 CLI 설치 금지 |
| timeout | 버전 확인 10초, 내장 updater와 설치 스크립트 300초 |
| 비밀 보호 | 환경변수 전체와 토큰 값을 출력하지 않음 |
| 추적 가능성 | 업데이트 전후 버전, 실행 경로, 결과를 로그로 기록 |

## 운영 범위와 한계

이 프로젝트는 개인 장비와 소규모 내부 환경에 적합합니다.

| 환경 | 적합도 |
| --- | --- |
| 개인 macOS / Windows 장비 | ✅ 적합 |
| 소규모 팀 내부 자동화 | ⚠️ 조건부 적합 |
| 고객 대상 핵심 상용 인프라 | 🛠️ 추가 보강 필요 |

현재 다음 기능은 포함하지 않습니다.

- 업데이트 실패 알림
- 문제 버전 자동 rollback
- 패키지별 별도 서명 검증 정책
- Windows PowerShell의 지속적인 CI 실행

Grok Build는 베타 성격과 계정·구독 조건이 있을 수 있습니다. 각 CLI의 패키지 관리자와 공식 updater를 신뢰하는 구조이므로 조직 환경에서는 별도의 변경 관리 정책을 권장합니다.

## Cron으로 실행하기

`launchd` 대신 cron을 사용하는 환경에서는 다음과 같이 등록할 수 있습니다.

```cron
0 5 * * * /path/to/ai_cli_auto_update/bin/update_ai_clis.sh >> "$HOME/.ai-cli-auto-update/cron.log" 2>&1
```

## 개발 및 검증

```bash
bash -n bin/update_ai_clis.sh
shellcheck bin/update_ai_clis.sh
./bin/update_ai_clis.sh --dry-run
```

PowerShell이 있는 환경에서는 다음 명령으로 Windows 실행 경로를 확인합니다.

```powershell
.\bin\update_ai_clis.ps1 -DryRun
```

## 공식 문서

- [Kimi Code CLI](https://www.kimi.com/code/docs/en/kimi-code-cli/guides/getting-started.html)
- [OpenAI Codex CLI](https://help.openai.com/en/articles/11096431)
- [OpenCode](https://github.com/anomalyco/opencode#installation)
- [Claude Code](https://code.claude.com/docs/en/installation)
- [Grok Build](https://docs.x.ai/build/overview)

## License

MIT License. 자세한 내용은 [LICENSE](LICENSE)를 확인하세요.
