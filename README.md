# ai_cli_auto_update

Kimi Code CLI, GPT/Codex CLI, Antigravity CLI, Claude Code, Grok Build 같은 로컬 AI 코딩 CLI를 보수적으로 자동 업데이트하는 작은 유틸리티입니다.

- macOS: Bash 스크립트 + `launchd`
- Windows: PowerShell 스크립트 + 작업 스케줄러
- 매일 새벽 5시에 자동 실행하도록 템플릿을 제공합니다.
- 해당 시스템에 CLI가 설치되어 있지 않으면 실패로 처리하지 않고 `pass`로 건너뜁니다.

## 업데이트 대상

| CLI | macOS 지원 방식 | Windows 지원 방식 | 미설치 시 동작 |
| --- | --- | --- | --- |
| `kimi` | npm `@moonshot-ai/kimi-code` | npm `@moonshot-ai/kimi-code` | `pass` 후 계속 진행 |
| `gpt` | OpenAI Codex CLI: Homebrew `codex` 또는 npm `@openai/codex` | npm `@openai/codex` | `pass` 후 계속 진행 |
| `agy` | Antigravity CLI 내장 `agy update` | Antigravity CLI 내장 `agy update` | `pass` 후 계속 진행 |
| `claude` | Homebrew `claude-code`, npm `@anthropic-ai/claude-code`, 또는 `claude update` | npm `@anthropic-ai/claude-code` 또는 `claude update` | `pass` 후 계속 진행 |
| `grok` | xAI 공식 install script 재실행 | xAI 공식 PowerShell install script 재실행 | `pass` 후 계속 진행 |

> 원칙: 설치되어 있는 도구만 업데이트합니다. 없는 CLI를 새로 설치하지 않습니다.

기본 대상은 `kimi,gpt,agy,claude,grok`입니다. `AI_CLI_TARGETS` 또는 `--targets` / `-Targets`로 원하는 CLI만 선택할 수 있습니다.
`gpt`는 OpenAI Codex CLI의 선택 이름이며 실제 명령은 `codex`입니다. 기존 자동화 호환을 위해 `codex` 타깃 이름도 계속 허용합니다.

```bash
AI_CLI_TARGETS=kimi,gpt ./bin/update_ai_clis.sh --dry-run
./bin/update_ai_clis.sh --targets kimi,gpt,agy
```

```powershell
.\bin\update_ai_clis.ps1 -Targets kimi,gpt -DryRun
```

미설치 CLI를 새로 설치하려면 명시적으로 opt-in 해야 합니다.

```bash
./bin/update_ai_clis.sh --targets kimi --install-missing
```

```powershell
.\bin\update_ai_clis.ps1 -Targets kimi -InstallMissing
```

## 운영 적합성

이 유틸리티는 개인 장비나 소규모 내부 환경에서 로컬 AI CLI를 최신 상태로 유지하는 용도에 맞춰져 있습니다.

| 사용 환경 | 적합도 |
| --- | --- |
| 개인 macOS/Windows 장비의 자동 업데이트 | 적합 |
| 소규모 팀 내부 유틸리티 | 조건부 적합 |
| 고객 대상 상용 제품의 핵심 운영 구성요소 | 추가 보강 필요 |

상용 운영 수준으로 쓰려면 최소한 실패 알림, CI 기반 Windows 검증, 보안/운영 정책 문서화, 업데이트 실패 리포트를 추가하는 것을 권장합니다.

상용화 버전에서는 설치 단계에서 사용자가 업데이트할 AI CLI를 선택하도록 만드는 구성이 자연스럽습니다.

권장 흐름:

1. OS와 패키지 매니저 감지
2. 지원 CLI 목록 표시: `kimi`, `gpt`, `agy`, `claude`, `grok`
3. 사용자가 설치/자동 업데이트 대상을 선택
4. 선택 결과를 설정 파일 또는 스케줄러 환경변수의 `AI_CLI_TARGETS`로 저장
5. 미설치 CLI는 사용자가 동의한 경우에만 설치
6. 스케줄러는 저장된 대상만 업데이트

Kimi Code CLI는 최신 공식 문서 기준으로 새 버전이 Node.js 기반이며, npm 패키지 이름은 `@moonshot-ai/kimi-code`입니다. 기존 Python/uv 기반 `kimi-cli`는 점진적으로 교체되는 경로로 안내되어 있으므로, 자동화에는 npm 기반 설치를 우선합니다.
Claude Code는 npm `@anthropic-ai/claude-code` 또는 CLI 내장 `claude update`를 우선합니다. Grok Build는 xAI 공식 install script를 재실행하는 방식입니다. Grok 쪽은 공식 문서상 베타 성격이 강하고 계정/구독 조건이 있을 수 있으므로, 상용화 시에는 설치 가능 여부와 약관을 별도 표시하는 것이 좋습니다.

공식 참고 문서:

- Kimi Code CLI: <https://www.kimi.com/code/docs/en/kimi-code-cli/guides/getting-started.html>
- OpenAI Codex CLI: <https://help.openai.com/en/articles/11096431>
- Claude Code: <https://code.claude.com/docs/en/installation>
- Grok Build: <https://docs.x.ai/build/overview>

## 빠른 실행

### macOS / Linux 계열 셸

```bash
git clone https://github.com/wilgon456/ai_cli_auto_update_public.git
cd ai_cli_auto_update_public
./bin/update_ai_clis.sh --dry-run
./bin/update_ai_clis.sh
./bin/update_ai_clis.sh --targets kimi,gpt,claude
```

### Windows PowerShell

```powershell
git clone https://github.com/wilgon456/ai_cli_auto_update_public.git
cd ai_cli_auto_update_public
.\bin\update_ai_clis.ps1 -DryRun
.\bin\update_ai_clis.ps1
.\bin\update_ai_clis.ps1 -Targets kimi,gpt,claude
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
LOG_RETENTION_DAYS=14 ./bin/update_ai_clis.sh
```

```powershell
.\bin\update_ai_clis.ps1 -LogDir "C:\path\to\logs"
.\bin\update_ai_clis.ps1 -LogRetentionDays 14
```

각 실행은 timestamp 로그와 `latest.log`를 남깁니다.
기본적으로 30일보다 오래된 `update-*.log`는 자동 삭제합니다. `LOG_RETENTION_DAYS`로 조정할 수 있고, `0`이면 정리를 끕니다.

## 안전 동작

- 동시에 두 번 실행되지 않도록 잠금 처리합니다.
- 업데이트 전/후 버전과 경로를 기록합니다.
- 오래된 timestamp 로그를 자동 정리하고 `latest.log`는 유지합니다.
- 한 CLI 업데이트가 실패해도 나머지 CLI 업데이트는 계속 진행합니다.
- CLI가 아예 설치되어 있지 않으면 실패가 아니라 `pass`로 기록합니다.
- 환경변수 전체나 토큰/시크릿 값을 출력하지 않습니다.
- 실제 변경 없이 확인할 수 있는 dry-run 모드를 지원합니다.
  - Bash: `--dry-run` 또는 `--check`
  - PowerShell: `-DryRun`
- 업데이트 대상 선택을 지원합니다.
  - Bash: `AI_CLI_TARGETS=kimi,gpt,claude` 또는 `--targets kimi,gpt,claude`
  - PowerShell: `-Targets kimi,gpt,claude`
- 미설치 CLI 설치는 기본 비활성화이며, 명시적인 opt-in이 필요합니다.
  - Bash: `--install-missing`
  - PowerShell: `-InstallMissing`
- 버전 확인 명령은 기본 10초 timeout을 적용합니다.
- `agy update`, `claude update`, Grok install script는 최대 300초 후 timeout 처리해 대화형 프롬프트나 hang이 자동 실행을 영구 점유하지 않도록 합니다.

## 알려진 한계

- 실패 알림은 아직 없습니다. 실패 여부는 `latest.log` 또는 timestamp 로그를 확인해야 합니다.
- PowerShell 스크립트는 Windows 환경에서 별도 검증해야 합니다.
- `agy update`가 향후 공식 non-interactive 옵션을 제공하면 timeout보다 해당 옵션을 쓰는 것이 더 좋습니다.
- 업데이트 후 CLI 자체가 회귀했을 때 자동 rollback하지 않습니다.
- 패키지 매니저와 CLI 내장 updater를 신뢰하는 구조이며, 별도의 서명 검증 정책은 포함하지 않습니다.

## 매일 새벽 5시 자동 실행

### macOS: launchd

`launchd/com.example.ai-cli-auto-update.plist` 템플릿은 매일 05:00에 실행되도록 설정되어 있습니다.

```bash
mkdir -p ~/Library/LaunchAgents
cp launchd/com.example.ai-cli-auto-update.plist ~/Library/LaunchAgents/com.example.ai-cli-auto-update.plist

# 필요하면 plist 안의 ProgramArguments 경로를 본인 clone 경로로 수정하세요.
launchctl load ~/Library/LaunchAgents/com.example.ai-cli-auto-update.plist
```

특정 CLI만 자동 업데이트하려면 plist에 환경변수를 추가하거나, `ProgramArguments`에 `--targets`를 넣으면 됩니다.

```xml
<key>EnvironmentVariables</key>
<dict>
  <key>AI_CLI_TARGETS</key>
  <string>kimi,gpt,claude</string>
</dict>
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
- 업데이트 대상: `kimi,gpt,agy,claude,grok`

시각, 경로, 업데이트 대상을 바꾸려면:

```powershell
.\windows\install_scheduled_task.ps1 -At "05:00" -ScriptPath "C:\path\to\ai_cli_auto_update\bin\update_ai_clis.ps1"
.\windows\install_scheduled_task.ps1 -Targets "kimi,gpt,claude"
.\windows\install_scheduled_task.ps1 -Targets "kimi" -InstallMissing
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
