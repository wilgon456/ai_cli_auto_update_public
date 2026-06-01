# ai_cli_auto_update

Codex CLI, Antigravity CLI 같은 로컬 AI 코딩 CLI를 보수적으로 자동 업데이트하는 작은 유틸리티입니다.

- macOS: Bash 스크립트 + `launchd`
- Windows: PowerShell 스크립트 + 작업 스케줄러
- 매일 새벽 5시에 자동 실행하도록 템플릿을 제공합니다.
- 해당 시스템에 CLI가 설치되어 있지 않으면 실패로 처리하지 않고 `pass`로 건너뜁니다.

## 업데이트 대상

| CLI | macOS 지원 방식 | Windows 지원 방식 | 미설치 시 동작 |
| --- | --- | --- | --- |
| `codex` | Homebrew `codex` 또는 npm `@openai/codex` | npm `@openai/codex` | `pass` 후 계속 진행 |
| `agy` | Antigravity CLI 내장 `agy update` | 미지원 | `pass` 후 계속 진행 |

Windows PowerShell 스크립트는 기존 npm 기반 `claude`, `gemini` 업데이트 경로를 유지합니다.

> 원칙: 설치되어 있는 도구만 업데이트합니다. 없는 CLI를 새로 설치하지 않습니다.

## 빠른 실행

### macOS / Linux 계열 셸

```bash
git clone https://github.com/wilgon456/ai_cli_auto_update_public.git
cd ai_cli_auto_update_public
./bin/update_ai_clis.sh --dry-run
./bin/update_ai_clis.sh
```

### Windows PowerShell

```powershell
git clone https://github.com/wilgon456/ai_cli_auto_update_public.git
cd ai_cli_auto_update_public
.\bin\update_ai_clis.ps1 -DryRun
.\bin\update_ai_clis.ps1
```

## 로그 위치

기본 로그 위치는 운영체제별로 다릅니다.

| OS | 기본 로그 위치 |
| --- | --- |
| macOS / Bash | `~/.ai-cli-auto-update/logs/` |
| Windows PowerShell | `%USERPROFILE%\.ai-cli-auto-update\logs\` |

환경변수나 파라미터로 바꿀 수 있습니다.

```bash
LOG_DIR=/path/to/logs ./bin/update_ai_clis.sh
```

```powershell
.\bin\update_ai_clis.ps1 -LogDir "C:\path\to\logs"
```

각 실행은 timestamp 로그와 `latest.log`를 남깁니다.

## 안전 동작

- 동시에 두 번 실행되지 않도록 잠금 처리합니다.
- 업데이트 전/후 버전과 경로를 기록합니다.
- 한 CLI 업데이트가 실패해도 나머지 CLI 업데이트는 계속 진행합니다.
- CLI가 아예 설치되어 있지 않으면 실패가 아니라 `pass`로 기록합니다.
- 환경변수 전체나 토큰/시크릿 값을 출력하지 않습니다.
- 실제 변경 없이 확인할 수 있는 dry-run 모드를 지원합니다.
  - Bash: `--dry-run` 또는 `--check`
  - PowerShell: `-DryRun`

## 매일 새벽 5시 자동 실행

### macOS: launchd

`launchd/com.example.ai-cli-auto-update.plist` 템플릿은 매일 05:00에 실행되도록 설정되어 있습니다.

```bash
mkdir -p ~/Library/LaunchAgents
cp launchd/com.example.ai-cli-auto-update.plist ~/Library/LaunchAgents/com.example.ai-cli-auto-update.plist

# 필요하면 plist 안의 ProgramArguments 경로를 본인 clone 경로로 수정하세요.
launchctl load ~/Library/LaunchAgents/com.example.ai-cli-auto-update.plist
```

수정 후 다시 로드하려면:

```bash
launchctl unload ~/Library/LaunchAgents/com.example.ai-cli-auto-update.plist 2>/dev/null || true
launchctl load ~/Library/LaunchAgents/com.example.ai-cli-auto-update.plist
```

### Windows: 작업 스케줄러

관리자 권한이 아니어도 현재 사용자 작업으로 등록할 수 있습니다.

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
.\windows\install_scheduled_task.ps1
```

기본값:

- 작업 이름: `AI CLI Auto Update`
- 실행 시각: 매일 05:00
- 실행 스크립트: `bin\update_ai_clis.ps1`

시각이나 경로를 바꾸려면:

```powershell
.\windows\install_scheduled_task.ps1 -At "05:00" -ScriptPath "C:\path\to\ai_cli_auto_update\bin\update_ai_clis.ps1"
```

등록 확인:

```powershell
Get-ScheduledTask -TaskName "AI CLI Auto Update"
```

수동 실행:

```powershell
Start-ScheduledTask -TaskName "AI CLI Auto Update"
```

## Cron 예시

`launchd`나 작업 스케줄러를 쓰지 않고 cron을 쓰는 환경이라면 매일 05:00에 아래처럼 등록할 수 있습니다.

```cron
0 5 * * * /path/to/ai_cli_auto_update/bin/update_ai_clis.sh >> "$HOME/.ai-cli-auto-update/cron.log" 2>&1
```

## 다른 자동화와 연동

cron job이나 다른 자동화에서 이 스크립트를 직접 호출해도 됩니다. 이 저장소는 특정 런타임 내부 구현에 의존하지 않도록 Bash/PowerShell 중심으로 구성되어 있습니다.

예시:

```text
/path/to/ai_cli_auto_update/bin/update_ai_clis.sh
```

## 개발/검증

macOS/Bash 쪽 문법 확인:

```bash
bash -n bin/update_ai_clis.sh
./bin/update_ai_clis.sh --dry-run
```

Windows/PowerShell 쪽은 PowerShell이 있는 환경에서 확인합니다.

```powershell
.\bin\update_ai_clis.ps1 -DryRun
```

## 라이선스

MIT
