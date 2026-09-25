@testable import KbdCore

/// Simulates an app hosting the composer: "⌫" is backspace; keys the composer doesn't handle are
/// inserted as-is (as the app would after the IME passes them through). Returns the final text.
func type(_ keys: String, layout: Layout = .dubeolsik, backspaceUnit: BackspaceUnit = .jamo) -> String {
    var composer = try! HangulComposer(layout: layout, backspaceUnit: backspaceUnit)
    var text = ""
    for key in keys {
        if key == "⌫" {
            if composer.backspace() == nil, !text.isEmpty {
                text.removeLast()
            }
            continue
        }
        let result = composer.process(key)
        text += result.commit
        if !result.handled {
            text.append(key)
        }
    }
    return text + composer.flush()
}

/// 세벌식 최종 (3-91), unshifted keys only. A test fixture to check that role-explicit layouts fit
/// the engine's model; not a shipping layout (shifted keys and symbols are missing).
let sebeolsikFinalFixture = Layout(
    id: "sebeolsik-final-fixture",
    name: "세벌식 최종 (test fixture)",
    automaton: .jaso,
    keymap: {
        let cho: [Character: Unicode.Scalar] = [
            "k": "ㄱ", "h": "ㄴ", "u": "ㄷ", "y": "ㄹ", "i": "ㅁ", ";": "ㅂ", "n": "ㅅ",
            "j": "ㅇ", "l": "ㅈ", "o": "ㅊ", "0": "ㅋ", "'": "ㅌ", "p": "ㅍ", "m": "ㅎ",
        ]
        let jung: [Character: Unicode.Scalar] = [
            "f": "ㅏ", "r": "ㅐ", "6": "ㅑ", "t": "ㅓ", "c": "ㅔ", "e": "ㅕ", "7": "ㅖ",
            "v": "ㅗ", "/": "ㅗ", "4": "ㅛ", "b": "ㅜ", "9": "ㅜ", "5": "ㅠ", "g": "ㅡ", "8": "ㅢ", "d": "ㅣ",
        ]
        let jong: [Character: Unicode.Scalar] = [
            "x": "ㄱ", "s": "ㄴ", "w": "ㄹ", "z": "ㅁ", "3": "ㅂ", "q": "ㅅ", "2": "ㅆ", "a": "ㅇ", "1": "ㅎ",
        ]
        var keymap: [String: String] = [:]
        for (key, compat) in cho { keymap[String(key)] = String(Jamo.cho(compat)) }
        for (key, compat) in jung { keymap[String(key)] = String(Jamo.jung(compat)) }
        for (key, compat) in jong { keymap[String(key)] = String(Jamo.jong(compat)) }
        return keymap
    }(),
    combinations: Layout.combinations(
        choseong: ["ㄱㄱ": "ㄲ", "ㄷㄷ": "ㄸ", "ㅂㅂ": "ㅃ", "ㅅㅅ": "ㅆ", "ㅈㅈ": "ㅉ"],
        jungseong: Layout.standardVowelClusters,
        jongseong: Layout.standardFinalClusters.merging(["ㄱㄱ": "ㄲ", "ㅅㅅ": "ㅆ"]) { a, _ in a }
    )
)
