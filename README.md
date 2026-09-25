# kbd

개발자를 위한 macOS 한글 입력기.


터미널, 에디터, vim, tmux를 오가며 한글과 영문을 섞어 쓰는 환경에 맞췄습니다. 한/영 전환은 입력 소스를 바꾸지 않고 입력기 안에서 처리하므로 지연이나 첫 글자 씹힘이 없고, 한글 모드에서도 단축키와 tmux prefix가 영문 키로 전달됩니다.

## 기능

- **즉시 한/영 전환**: 전용 전환 키(기본 오른쪽 ⌘)를 누르는 순간 전환합니다. 입력 소스를 바꾸지 않기 때문에 전환 지연이 없습니다.
- **전환 키 전용화**: 전환 키로 고른 수식키나 CapsLock을 HID 레벨에서 F키로 리매핑하고 전역 단축키로 받으므로, 그 키의 원래 기능(⌘C, ⌘Tab 등)은 사라지고 어떤 앱에도 전달되지 않습니다.
- **한글 모드에서 단축키 그대로**: ⌘/Ctrl/⌥ 조합은 조합 중인 글자를 확정한 뒤 영문 키로 전달합니다. `⌘ㅁ`가 아니라 `⌘A`가 가므로 tmux·herdr prefix, vim의 Ctrl 조합이 한글 모드에서도 동작합니다.
- **앱별 모드 기억**: 앱마다 마지막 한/영 모드를 기억하고, 앱별로 항상 영문/한글로 시작하게 할 수도 있습니다.
- **ESC → 영문**: ESC나 Ctrl-[를 누르면 영문으로 전환합니다(앱별로 켜기). ESC는 앱에 그대로 전달됩니다.
- **소켓 IPC**: 유닉스 소켓으로 모드를 조회·변경하고 변경을 구독할 수 있습니다. nvim, 상태줄, 스크립트와 연동할 수 있습니다.
- **설정 파일**: `~/.config/kbd/config.toml`. 저장하면 재시작 없이 바로 반영됩니다.
- **자판**: 두벌식(KS X 5002). 백스페이스는 자모 단위(기본) 또는 음절 단위.

## 요구 사항

- macOS 14 이상
- 소스에서 빌드: Xcode Command Line Tools (Xcode 불필요)

## 설치

현재는 소스에서 빌드해 설치합니다.

```sh
make install
```

`~/Library/Input Methods/kbd.app`에 설치되고 시스템에 입력기로 등록됩니다. 그다음:

1. 시스템 설정 → 키보드 → 입력 소스 → 편집 → `+` → 한국어 → **kbd** 추가
2. 한/영 상태는 kbd의 메뉴 막대 아이콘(`한` / `A`)으로 표시됩니다. 시스템 입력 메뉴 아이콘은 항상 `KBD`로 고정되므로, 입력 소스 설정에서 "메뉴 막대에서 입력 메뉴 보기"를 꺼도 됩니다.
3. 새 macOS에서 kbd 아이콘이 보이지 않으면 시스템 설정 → 메뉴 막대에서 kbd를 허용합니다.

입력 소스 목록에 kbd가 보이지 않으면 로그아웃 후 다시 로그인하세요.

### 제거

```sh
make uninstall
```

시스템 설정의 입력 소스 목록에서도 kbd를 삭제하세요.

## 설정

kbd 메뉴 막대 아이콘 → **설정 파일 열기**를 누르면 `~/.config/kbd/config.toml`이 없을 경우 주석이 달린 템플릿으로 만들어 엽니다. 파일은 저장하는 즉시 다시 읽힙니다.

```toml
[toggle]
key = "right_command"      # caps_lock | {left,right}_{command,option,control,shift} | f13 ~ f20
remap_to = "f20"           # 수식키/CapsLock을 이 F키로 리매핑 (key가 F키면 리매핑하지 않음)

[hangul]
layout = "dubeolsik"
backspace = "jamo"         # jamo | syllable

[escape]
enabled = false            # 기본은 끄고 앱별로 켭니다
keys = ["escape", "ctrl+["]

[mode]
new_app = "inherit"        # 처음 보는 앱의 모드: inherit | en | ko

[apps."com.mitchellh.ghostty"]
on_activate = "remember"   # remember | en | ko (활성화될 때마다 이 모드로 시작)
escape = true              # 이 앱에서만 [escape].enabled를 바꿈
composition = "marked"     # auto | inline | marked
[apps."com.mitchellh.ghostty".commit_keys]
enter = "\r"              # 조합 중 이 키를 누르면 확정된 글자 뒤에 문자열을 붙여 보냄
"shift+enter" = "\n"
```

- `composition`: 조합 중인 음절을 보여 주는 방식입니다. `inline`은 음절을 실제 텍스트로 넣고 키마다 바꿔치기합니다. 시스템 한국어 입력기와 같은 방식이라, Enter로 전송하는 앱(Telegram 등)에서 한 번에 전송됩니다. `marked`는 조합 중 표시(밑줄/블록)입니다. `auto`(기본)는 첫 키에서 앱이 바꿔치기를 지원하는지 확인해 고르고, 터미널처럼 지원하지 않는 앱에서는 `marked`를 씁니다.
- `commit_keys`: 조합을 끝낸 키를 버리는 앱을 위한 우회입니다. 키는 `[shift+][ctrl+][alt+][cmd+]enter|tab|escape` 형식입니다. 확정된 글자 뒤에 문자열을 붙여 보내되, `escape`는 ESC 키로 전달되도록 글자와 따로 보냅니다. macOS가 제어 문자 하나짜리 입력을 버리기 때문에 템플릿의 Ghostty 섹션은 `escape = "\u001B\u001B"`처럼 두 개를 적습니다(Ghostty는 ESC 키 한 번으로 보냄). `escape`에 제어 문자 하나만 적으면 설정 오류로 처리합니다.

- 값이 잘못되었거나 문법 오류가 있으면 설정 전체를 적용하지 않고 마지막 정상 설정을 유지합니다. 이때 메뉴 막대 아이콘에 `!`가 붙고, 메뉴에서 오류 내용(줄 번호 포함)을 볼 수 있습니다.
- 알 수 없는 키(오타 등)는 설정을 적용하되 메뉴에 경고로 표시합니다.
- 설정 파일이 dotfile 관리 도구의 심볼릭 링크여도 변경을 감지합니다.

### 전환 키와 Karabiner-Elements

`toggle.key`에 수식키나 CapsLock을 지정하면 kbd가 실행되는 동안 해당 키를 `remap_to` F키로 리매핑합니다(`hidutil`과 같은 `UserKeyMapping` 방식, 다른 도구가 건 매핑은 유지). kbd가 종료되면 매핑을 되돌립니다.

Karabiner-Elements로 이미 특정 키를 F키로 보내고 있다면, 그 F키를 `toggle.key`에 직접 지정하세요. 이 경우 kbd는 리매핑하지 않습니다.

## IPC

기본 소켓은 `~/.local/state/kbd/kbd.sock`입니다(디렉터리 0700, 소켓 0600). 요청은 한 줄 텍스트, 응답도 한 줄이며 응답 후 연결을 닫습니다. `subscribe`만 연결을 유지하고, 연결 직후 현재 상태를 한 줄 보낸 뒤 모드나 포커스된 앱이 바뀔 때마다 한 줄씩 보냅니다.

| 요청 | 기본 응답 |
|---|---|
| `ping` | `pong` |
| `version` | `ok kbd <version> proto 1` |
| `get` | `ok <en\|ko> <bundle id> <active\|inactive>` |
| `set en`, `set ko` | `ok <switched\|noop> <active\|inactive>` |
| `switch` | `set en`과 같음 |
| `toggle` | `ok <en\|ko> <active\|inactive>` |
| `subscribe` | `mode <en\|ko> <bundle id> <active\|inactive>` (변경마다) |

`active`는 kbd가 현재 선택된 입력 소스인지를 나타냅니다. 모드를 바꾸는 요청은 입력 중인 글자를 확정한 뒤 전환합니다.

```sh
echo get | nc -U ~/.local/state/kbd/kbd.sock
echo "set en" | nc -U ~/.local/state/kbd/kbd.sock
nc -U ~/.local/state/kbd/kbd.sock <<< subscribe   # 변경을 계속 출력
```

### 소켓과 요청 설정

`[[ipc.socket]]`으로 여는 소켓과 요청을 정할 수 있습니다. 이 섹션을 쓰면 적은 소켓만 열리므로, 기본 소켓도 원하면 함께 적어야 합니다. 각 소켓은 기본 요청을 모두 받고, `requests`로 요청 이름을 추가하거나 기본 요청의 응답 형식을 바꿀 수 있습니다.

```toml
[[ipc.socket]]
path = "~/.local/state/kbd/kbd.sock"

[[ipc.socket]]
path = "~/.local/state/other/other.sock"
[ipc.socket.requests]
"leave-insert" = { action = "set en", reply = "ok {result}" }
get = { action = "get", reply = "{mode}" }
```

- `action`: `ping` | `version` | `get` | `set en` | `set ko` | `toggle` | `subscribe`
- `reply` 변수: `{mode}` `{app}` `{result}` `{active}` `{version}` (생략하면 같은 동작의 기본 응답)

다른 프로세스가 이미 사용 중인 소켓 경로는 열지 않고 메뉴에 경고를 표시합니다.

#### imswitch

[imswitch](https://github.com/hongzio/imswitch)의 nvim 플러그인과 `imswitch remote`는 `switch` 요청을 보내므로, `imswitch serve` 대신 kbd가 imswitch 소켓을 열게 하면 수정 없이 동작합니다.

```sh
brew services stop imswitch
```

```toml
[[ipc.socket]]
path = "~/.local/state/kbd/kbd.sock"

[[ipc.socket]]
path = "~/.local/state/imswitch/imswitch.sock"
```

## 알려진 제약

- kbd의 한/영 상태는 kbd 내부에만 있습니다. 시스템 입력 소스를 보고 한/영을 판단하는 도구(Karabiner의 `input_source_if` 등)는 항상 kbd로만 보므로, 한/영 상태는 IPC로 조회해야 합니다.
- kbd가 비정상 종료되면(강제 종료, 크래시) 전환 키 리매핑이 남을 수 있습니다. 재부팅하면 사라집니다.
- kbd는 시스템이 필요할 때 실행합니다. 로그인 후 처음 입력하기 전에는 소켓이 없을 수 있습니다.

### Ghostty

- 조합 중에 누른 키를 Ghostty가 버립니다([ghostty#14272](https://github.com/ghostty-org/ghostty/pull/14272)). 설정 템플릿의 Ghostty 섹션(`commit_keys`)이 이를 우회해서, Enter/Tab/ESC와 Shift+Enter(LF로 전송)가 한 번에 동작합니다.
- Ghostty 1.3.1은 확정된 글자를 그 키 이벤트에 붙여 보냅니다. 그래서 다음 경우 마지막 음절이 사라집니다. 이 부분은 Ghostty tip 빌드(`brew install --cask ghostty@tip`)에서 고쳐져 있습니다.
  - kitty 키보드 프로토콜을 쓰는 프로그램(neovim 등)에서 조합 중 Tab. Ghostty가 Tab 키에 붙은 글자를 버리고 탭만 보냅니다. Apple 입력기도 같습니다.
  - 조합을 끝낸 키에 Ghostty 키 바인딩이 걸린 경우. 예를 들어 Claude Code의 터미널 설정이 추가하는 `keybind = shift+enter=text:\n`이 있으면 Shift+Enter에서 음절이 사라집니다. Ghostty에서는 이 바인딩 없이도 Claude Code의 Shift+Enter가 동작하므로 지우는 것을 권장합니다.

## 개발

```sh
make build     # build/kbd.app 생성 (ad-hoc 서명)
make test      # 단위 테스트 (Swift Testing)
make install   # 빌드 후 ~/Library/Input Methods에 설치, 등록, 재시작
make log       # kbd 로그 실시간 보기
```

| 경로 | 내용 |
|---|---|
| `Sources/KbdCore` | 한글 조합 엔진. AppKit/IMK 의존 없음. 자판은 데이터 테이블(keymap, 결합 규칙)이고 오토마타는 두벌식(`jamo`)·세벌식(`jaso`) 두 종류 |
| `Sources/KbdConfig` | `config.toml` 모델, 파싱, 검증, IPC 요청/응답 정의 |
| `Sources/kbd` | 입력기 본체: InputMethodKit 컨트롤러, 모드 상태, HID 리매핑, 설정 감시, 소켓 서버, 메뉴 막대 아이콘 |
| `Tests/` | `KbdCore`, `KbdConfig` 단위 테스트 |
| `scripts/` | 앱 번들 조립, 아이콘 생성, 입력기 등록 |

Command Line Tools만 설치된 환경에서는 원격 패키지 의존성이 있을 때 `swift test`가 Swift Testing 매크로 플러그인을 찾지 못합니다. `make test`는 플러그인을 직접 지정해 이를 우회합니다.
