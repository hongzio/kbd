import KbdCore
import Testing
@testable import KbdConfig

@Suite("ConfigParser")
struct ConfigParserTests {
    @Test func emptyFileGivesDefaults() throws {
        let parsed = try ConfigParser.parse("")
        #expect(parsed.config == Config())
        #expect(parsed.warnings.isEmpty)
    }

    @Test func templateParsesCleanly() throws {
        let parsed = try ConfigParser.parse(ConfigTemplate.text)
        #expect(parsed.warnings.isEmpty)
        #expect(parsed.config.toggle == Config.Toggle())
        #expect(parsed.config.escape.enabled == false)
        #expect(parsed.config.escapeEnabled(for: "com.mitchellh.ghostty"))
        #expect(!parsed.config.escapeEnabled(for: "ru.keepcoder.Telegram"))
        #expect(parsed.config.compatibility(for: "com.mitchellh.ghostty") == .init(
            composition: .marked,
            commitKeys: [.init(.enter): "\r", .init(.enter, .shift): "\n", .init(.tab): "\t", .init(.escape): "\u{1B}"]
        ))
    }

    @Test func fullConfig() throws {
        let parsed = try ConfigParser.parse("""
        [toggle]
        key = "caps_lock"
        remap_to = "f19"

        [hangul]
        backspace = "syllable"

        [escape]
        enabled = true
        keys = ["escape"]

        [mode]
        new_app = "en"

        [apps."com.mitchellh.ghostty"]
        on_activate = "en"

        [apps."ru.keepcoder.Telegram"]
        escape = false
        """)
        let config = parsed.config
        #expect(config.toggle.key.name == "caps_lock")
        #expect(config.toggle.needsRemap)
        #expect(config.toggle.keyCode == 80)  // F19
        #expect(config.hangul.backspace == .syllable)
        #expect(config.escape.keys == [.escape])
        #expect(config.mode.newApp == .en)
        #expect(config.apps["com.mitchellh.ghostty"]?.onActivate == .en)
        #expect(config.escapeEnabled(for: "com.mitchellh.ghostty"))
        #expect(!config.escapeEnabled(for: "ru.keepcoder.Telegram"))
        #expect(config.escapeEnabled(for: nil))
    }

    @Test func functionKeyToggleNeedsNoRemap() throws {
        let config = try ConfigParser.parse("[toggle]\nkey = \"f18\"").config
        #expect(!config.toggle.needsRemap)
        #expect(config.toggle.keyCode == 79)
    }

    @Test func unknownKeysAreWarnings() throws {
        let parsed = try ConfigParser.parse("""
        colour = "red"
        [toggle]
        kye = "caps_lock"
        [apps."com.example"]
        on_actvate = "en"
        """)
        #expect(parsed.config == { var c = Config(); c.apps["com.example"] = .init(); return c }())
        #expect(parsed.warnings.count == 3)
        #expect(parsed.warnings.contains { $0.hasPrefix("toggle.kye:") })
        #expect(parsed.warnings.contains { $0.hasPrefix("apps.\"com.example\".on_actvate:") })
        #expect(parsed.warnings.contains { $0.hasPrefix("colour:") })
    }

    @Test func invalidValuesAreAllReported() {
        #expect {
            try ConfigParser.parse("""
            [toggle]
            key = "hyper"
            remap_to = "right_command"
            [hangul]
            backspace = "word"
            """)
        } throws: { error in
            let messages = (error as! ConfigError).messages
            return messages.count == 3
                && messages[0].hasPrefix("toggle.key: \"hyper\"")
                && messages[1].hasPrefix("toggle.remap_to: \"right_command\"")
                && messages[2].hasPrefix("hangul.backspace: \"word\"")
        }
    }

    @Test func typeMismatch() {
        #expect {
            try ConfigParser.parse("[escape]\nenabled = \"yes\"")
        } throws: { error in
            let message = (error as! ConfigError).messages.first ?? ""
            return message.hasPrefix("TOML 오류") && message.contains("Line 2") && message.contains("enabled")
        }
    }

    @Test func syntaxErrorMentionsLine() {
        #expect {
            try ConfigParser.parse("[toggle]\nkey = \n")
        } throws: { error in
            let message = (error as! ConfigError).messages.first ?? ""
            return message.hasPrefix("TOML 문법 오류") && message.contains("Line 2")
        }
    }

    @Test func compatibilityDefaults() {
        // No hidden per-app defaults: everything comes from the file.
        let defaults = Config()
        #expect(defaults.compatibility(for: "com.mitchellh.ghostty") == .init(composition: .auto, commitKeys: [:]))
        #expect(defaults.compatibility(for: nil) == .init(composition: .auto, commitKeys: [:]))
    }

    @Test func commitKeys() throws {
        let config = try ConfigParser.parse(#"""
        [apps."com.example"]
        composition = "marked"
        [apps."com.example".commit_keys]
        enter = "\r"
        "shift+enter" = "\n"
        "ctrl+shift+tab" = "x"
        escape = "\u001B"
        """#).config
        let compat = config.compatibility(for: "com.example")
        #expect(compat.composition == .marked)
        #expect(compat.commitKeys == [
            .init(.enter): "\r",
            .init(.enter, .shift): "\n",
            .init(.tab, [.ctrl, .shift]): "x",
            .init(.escape): "\u{1B}",
        ])
    }

    @Test func invalidCommitKeys() {
        #expect {
            try ConfigParser.parse(#"""
            [apps."com.example".commit_keys]
            "hyper+enter" = "x"
            space = "x"
            "shift+shift+tab" = "x"
            tab = ""
            """#)
        } throws: { error in
            let messages = (error as! ConfigError).messages
            return messages.count == 4
                && messages.contains { $0.hasPrefix(#"apps."com.example".commit_keys."hyper+enter""#) }
                && messages.contains { $0.hasPrefix(#"apps."com.example".commit_keys."space""#) }
                && messages.contains { $0.hasPrefix(#"apps."com.example".commit_keys."shift+shift+tab""#) }
                && messages.contains { $0.hasPrefix(#"apps."com.example".commit_keys."tab": 보낼 문자열이 비어"#) }
        }
    }

    @Test func duplicateTriggerSpellings() {
        #expect {
            try ConfigParser.parse(#"""
            [apps."com.example".commit_keys]
            "shift+ctrl+enter" = "a"
            "ctrl+shift+enter" = "b"
            """#)
        } throws: { error in
            (error as! ConfigError).messages.contains { $0.contains("중복") }
        }
    }

    @Test func invalidComposition() {
        #expect {
            try ConfigParser.parse("[apps.\"com.example\"]\ncomposition = \"underline\"")
        } throws: { error in
            (error as! ConfigError).messages.first?.hasPrefix("apps.\"com.example\".composition: \"underline\"") == true
        }
    }
}
