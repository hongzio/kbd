public enum ConfigTemplate {
    /// Written when the user opens the config from the menu and no file exists yet.
    public static let text = #"""
    # kbd 설정 파일입니다. 저장하면 바로 반영됩니다.

    [toggle]
    # 한/영 전환 키입니다. 이 키는 원래 기능을 잃고 전환 전용이 됩니다.
    # caps_lock | {left,right}_{command,option,control,shift} | f13 ~ f20
    key = "right_command"
    # 수식키나 CapsLock을 고르면 HID 레벨에서 이 F키로 리매핑합니다. (f13 ~ f20)
    # F키를 key로 직접 지정하면(예: Karabiner로 이미 매핑한 경우) 리매핑하지 않습니다.
    remap_to = "f20"

    [hangul]
    layout = "dubeolsik"     # dubeolsik
    backspace = "jamo"       # jamo(자모 단위) | syllable(음절 단위)

    [escape]
    # ESC(또는 Ctrl-[)를 누르면 영문으로 전환합니다. ESC 키는 앱에 그대로 전달됩니다.
    # 기본은 꺼 두고, 아래 앱별 설정에서 필요한 앱만 켭니다.
    enabled = false
    keys = ["escape", "ctrl+["]

    [mode]
    # 처음 보는 앱의 모드: inherit(직전 모드 유지) | en | ko
    new_app = "inherit"

    # 앱별 설정 (bundle ID)
    #   on_activate = "remember"  앱마다 마지막 모드를 기억 (기본값)
    #   on_activate = "en" | "ko"  앱이 활성화될 때마다 이 모드로 시작
    #   escape = true | false      [escape].enabled를 이 앱에서만 바꿈
    #   composition = "auto" | "inline" | "marked"
    #       조합 중인 글자 표시 방식. inline은 실제 텍스트로 넣고 바꿔치기(시스템 한국어
    #       입력기와 같음, Enter 전송 앱에서 한 번에 동작), marked는 조합 표시. auto(기본)는
    #       첫 키에서 앱이 바꿔치기를 지원하는지 확인해 고릅니다.
    #   commit_keys = { "키" = "문자열", ... }
    #       조합을 끝낸 키를 버리는 앱용 우회. 조합 중 이 키를 누르면 확정된 글자 뒤에 문자열을
    #       붙여 한 번에 보내고 키는 소비합니다. 키: [shift+][ctrl+][alt+][cmd+]enter|tab|escape
    #       escape는 문자열을 글자와 따로 보냅니다(neovim 등에서 ESC 키로 전달되도록).
    #       그래서 제어 문자 하나만 적으면 오류입니다(macOS가 전달하지 않음).
    #
    # Ghostty: 터미널이라 바꿔치기가 불가능하고, 조합을 끝낸 키를 버립니다(ghostty#14272).
    [apps."com.mitchellh.ghostty"]
    escape = true
    composition = "marked"
    [apps."com.mitchellh.ghostty".commit_keys]
    enter = "\r"
    "shift+enter" = "\n"     # 줄바꿈(LF): Claude Code 등에서 제출 없이 줄바꿈
    tab = "\t"
    # ESC는 확정된 글자와 따로 보냅니다. 글자에 붙여 보내면 neovim처럼 kitty 키보드 프로토콜을
    # 쓰는 프로그램에서 Ghostty가 글자를 버리기 때문입니다.
    # 값을 두 번 반복한 것은 macOS가 제어 문자 하나만 담긴 입력을 전달하지 않기 때문입니다.
    # Ghostty는 제어 문자로 시작하는 입력을 ESC 키 한 번으로 보내므로, 실제로는 ESC가 한 번만 갑니다.
    escape = "\u001B\u001B"

    [apps."com.googlecode.iterm2"]
    escape = true

    [apps."com.apple.Terminal"]
    escape = true

    [apps."com.microsoft.VSCode"]
    escape = true

    [apps."com.jetbrains.intellij"]
    escape = true

    # 소켓 IPC. 이 섹션이 없으면 ~/.local/state/kbd/kbd.sock 하나를 엽니다.
    # 섹션을 쓰면 적은 소켓만 열리므로, 기본 소켓도 원하면 함께 적어야 합니다.
    # 요청은 한 줄 텍스트이고 응답도 한 줄입니다 (subscribe는 변경마다 한 줄씩).
    #   기본 요청: ping, version, get, "set en", "set ko", switch(= set en), toggle, subscribe
    #   예) echo get | nc -U ~/.local/state/kbd/kbd.sock
    # requests로 요청 이름을 추가하거나 기본 요청의 응답을 바꿀 수 있습니다.
    #   action: ping | version | get | "set en" | "set ko" | toggle | subscribe
    #   reply 변수: {mode} {app} {result} {active} {version}
    #
    # [[ipc.socket]]
    # path = "~/.local/state/kbd/kbd.sock"
    #
    # [[ipc.socket]]
    # path = "~/.local/state/other/other.sock"
    # [ipc.socket.requests]
    # "leave-insert" = { action = "set en", reply = "ok {result}" }

    """#
}
