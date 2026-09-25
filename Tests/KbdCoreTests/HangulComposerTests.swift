import Foundation
import Testing
@testable import KbdCore

@Suite("두벌식")
struct DubeolsikTests {
    @Test(arguments: [
        ("dkssudgktpdy", "안녕하세요"),
        ("rkqt", "값"),
        ("rkqtdl", "값이"),
        ("dhk", "와"),
        ("ghkfkd", "화랑"),
        ("RkTdl", "깠이"),
        ("rkTdj", "갔어"),
        ("ekfr", "닭"),
        ("tjdnf", "서울"),
        ("dmlwk", "의자"),
    ])
    func words(keys: String, expected: String) {
        #expect(type(keys) == expected)
    }

    @Test("도깨비불", arguments: [
        ("rkrk", "가가"),
        ("dlfrj", "일거"),     // ㄺ splits: ㄹ stays, ㄱ moves
        ("dlfrdj", "읽어"),    // ㅇ can't join ㄺ, starts a new syllable
        ("rkRk", "가까"),      // ㄲ typed as one key moves whole
        ("dkswk", "안자"),     // ㄵ splits
    ])
    func finalMovesToNextSyllable(keys: String, expected: String) {
        #expect(type(keys) == expected)
    }

    @Test("incomplete syllables", arguments: [
        ("k", "ㅏ"),
        ("kk", "ㅏㅏ"),
        ("rr", "ㄱㄱ"),       // no doubling by repetition
        ("QWE", "ㅃㅉㄸ"),
        ("rkE", "가ㄸ"),       // ㄸ can't be a final
    ])
    func incomplete(keys: String, expected: String) {
        #expect(type(keys) == expected)
    }

    @Test("keys outside the layout flush and pass through", arguments: [
        ("ek r", "다 ㄱ"),
        ("gks`", "한`"),
        ("rk1", "가1"),
    ])
    func passthrough(keys: String, expected: String) {
        #expect(type(keys) == expected)
    }

    @Test("backspace by jamo", arguments: [
        ("dkfr⌫", "알"),
        ("dhk⌫", "오"),
        ("gks⌫⌫", "ㅎ"),
        ("gks⌫⌫⌫", ""),
        ("rkqt⌫", "갑"),
        ("rkrk⌫", "가ㄱ"),     // after 도깨비불 only the new syllable is editable
        ("rk ⌫", "가"),        // nothing composing: app deletes
    ])
    func backspaceJamo(keys: String, expected: String) {
        #expect(type(keys) == expected)
    }

    @Test("backspace by syllable")
    func backspaceSyllable() {
        #expect(type("rkqt⌫", backspaceUnit: .syllable) == "")
        #expect(type("rkrk⌫", backspaceUnit: .syllable) == "가")
    }

    @Test("result fields")
    func resultFields() throws {
        var composer = try HangulComposer(layout: .dubeolsik)
        #expect(composer.process("g") == EngineResult(commit: "", preedit: "ㅎ", handled: true))
        #expect(composer.process("k") == EngineResult(commit: "", preedit: "하", handled: true))
        #expect(composer.process("s") == EngineResult(commit: "", preedit: "한", handled: true))
        #expect(composer.process("k") == EngineResult(commit: "하", preedit: "나", handled: true))
        #expect(composer.process(" ") == EngineResult(commit: "나", preedit: "", handled: false))
        #expect(composer.isEmpty)
        #expect(composer.backspace() == nil)
    }

    @Test("output is precomposed (NFC)")
    func precomposed() {
        let text = type("gksrmf")
        #expect(text == "한글")
        #expect(text.unicodeScalars.count == 2)
    }
}

@Suite("세벌식 (fixture)")
struct SebeolsikTests {
    @Test(arguments: [
        ("kfx", "각"),
        ("jfs", "안"),
        ("kkf", "까"),        // initial doubled by repetition
        ("jvf", "와"),
        ("j/f", "와"),
        ("jfxq", "앇"),       // final cluster
        ("kfxf", "각ㅏ"),      // no 도깨비불
        ("kfkf", "가가"),
        ("jfxx", "앆"),
    ])
    func syllables(keys: String, expected: String) {
        #expect(type(keys, layout: sebeolsikFinalFixture) == expected)
    }

    @Test("backspace", arguments: [
        ("kfx⌫", "가"),
        ("jvf⌫", "오"),
        ("kkf⌫", "ㄲ"),
        ("kkf⌫⌫", "ㄱ"),      // undoes the ㄱ+ㄱ combination, like ㅘ → ㅗ
    ])
    func backspace(keys: String, expected: String) {
        #expect(type(keys, layout: sebeolsikFinalFixture) == expected)
    }
}

@Suite("Layout")
struct LayoutTests {
    @Test func builtInsCompile() throws {
        _ = try HangulComposer(layout: .dubeolsik)
        _ = try HangulComposer(layout: sebeolsikFinalFixture)
    }

    @Test func codableRoundTrip() throws {
        let data = try JSONEncoder().encode(Layout.dubeolsik)
        let decoded = try JSONDecoder().decode(Layout.self, from: data)
        var composer = try HangulComposer(layout: decoded)
        _ = composer.process("g")
        _ = composer.process("k")
        #expect(composer.flush() == "하")
    }

    @Test func rejectsFinalsInTwoSetKeymap() {
        let layout = Layout(id: "bad", name: "bad", automaton: .jamo,
                            keymap: ["x": String(Jamo.jong("ㄱ"))], combinations: [:])
        #expect(throws: LayoutError.invalidKeyOutput(key: "x", output: String(Jamo.jong("ㄱ")))) {
            _ = try HangulComposer(layout: layout)
        }
    }

    @Test func rejectsMixedRoleCombination() {
        let pair = String(Jamo.cho("ㄱ")) + String(Jamo.jong("ㅅ"))
        let layout = Layout(id: "bad", name: "bad", automaton: .jamo,
                            keymap: [:], combinations: [pair: String(Jamo.jong("ㄳ"))])
        #expect(throws: LayoutError.invalidCombination(pair)) {
            _ = try HangulComposer(layout: layout)
        }
    }
}
