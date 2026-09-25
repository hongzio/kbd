public struct EngineResult: Equatable, Sendable {
    /// Text to commit before showing `preedit`.
    public var commit: String
    /// Marked text for the syllable still being composed.
    public var preedit: String
    /// false: the key isn't part of the layout. `commit` already holds the flushed syllable;
    /// the caller should insert it and let the app handle the original key.
    public var handled: Bool
}

public enum BackspaceUnit: String, Codable, Sendable {
    case jamo
    case syllable
}

/// Turns ABC-layout key characters into Hangul using a `Layout`.
public struct HangulComposer {
    private let layout: CompiledLayout
    private let backspaceUnit: BackspaceUnit

    private var current = Syllable()
    /// States of `current` before each keystroke, for jamo-level backspace.
    private var history: [Syllable] = []

    public init(layout: Layout, backspaceUnit: BackspaceUnit = .jamo) throws(LayoutError) {
        self.layout = try CompiledLayout(layout)
        self.backspaceUnit = backspaceUnit
    }

    public var isEmpty: Bool { current.isEmpty }
    public var preedit: String { current.render() }

    /// `key` is the ABC-layout character with Shift applied (CapsLock must already be ignored).
    public mutating func process(_ key: Character) -> EngineResult {
        switch layout.output(for: key) {
        case nil:
            return EngineResult(commit: flush(), preedit: "", handled: false)
        case .text(let text):
            return EngineResult(commit: flush() + text, preedit: "", handled: true)
        case .jamo(let jamo):
            let committed = switch layout.automaton {
            case .jamo: inputDubeolsik(jamo)
            case .jaso: inputSebeolsik(jamo)
            }
            return EngineResult(commit: committed, preedit: preedit, handled: true)
        }
    }

    /// nil when nothing is being composed, so the app should delete the previous character.
    public mutating func backspace() -> EngineResult? {
        guard !current.isEmpty else { return nil }
        switch backspaceUnit {
        case .jamo:
            current = history.popLast() ?? Syllable()
        case .syllable:
            current = Syllable()
            history = []
        }
        return EngineResult(commit: "", preedit: preedit, handled: true)
    }

    /// Returns the syllable being composed and clears the state.
    public mutating func flush() -> String {
        let text = preedit
        current = Syllable()
        history = []
        return text
    }

    // MARK: - 두벌식

    private mutating func inputDubeolsik(_ jamo: Unicode.Scalar) -> String {
        let s = current
        switch Jamo.role(of: jamo) {
        case .choseong:
            let asFinal = Jamo.jongseong(fromChoseong: jamo)
            if let jong = s.jong {
                if let asFinal, let combined = layout.combine(jong, asFinal) {
                    return update { $0.jong = combined }
                }
                return startSyllable(Syllable(cho: jamo))
            }
            if s.jung != nil {
                if s.cho != nil, let asFinal {
                    return update { $0.jong = asFinal }
                }
                return startSyllable(Syllable(cho: jamo))
            }
            if let cho = s.cho {
                if let combined = layout.combine(cho, jamo) {
                    return update { $0.cho = combined }
                }
                return startSyllable(Syllable(cho: jamo))
            }
            return update { $0.cho = jamo }

        case .jungseong:
            if let jong = s.jong {
                return moveFinalToNextSyllable(jong, vowel: jamo)
            }
            if let jung = s.jung {
                if let combined = layout.combine(jung, jamo) {
                    return update { $0.jung = combined }
                }
                return startSyllable(Syllable(jung: jamo))
            }
            return update { $0.jung = jamo }

        case .jongseong, nil:
            // Rejected when the layout was compiled.
            return startSyllable(Syllable())
        }
    }

    /// 도깨비불: a vowel after a final takes the final (or a cluster's last part) as its initial.
    private mutating func moveFinalToNextSyllable(_ jong: Unicode.Scalar, vowel: Unicode.Scalar) -> String {
        var kept = current
        let moving: Unicode.Scalar
        if let (first, second) = layout.split(jong) {
            kept.jong = first
            moving = second
        } else {
            kept.jong = nil
            moving = jong
        }
        guard let initial = Jamo.choseong(fromJongseong: moving) else {
            return startSyllable(Syllable(jung: vowel))
        }
        current = Syllable(cho: initial, jung: vowel)
        history = [Syllable(), Syllable(cho: initial)]
        return kept.render()
    }

    // MARK: - 세벌식

    private mutating func inputSebeolsik(_ jamo: Unicode.Scalar) -> String {
        let s = current
        switch Jamo.role(of: jamo) {
        case .choseong:
            if s.isEmpty {
                return update { $0.cho = jamo }
            }
            if let cho = s.cho, s.jung == nil, s.jong == nil, let combined = layout.combine(cho, jamo) {
                return update { $0.cho = combined }
            }
            return startSyllable(Syllable(cho: jamo))

        case .jungseong:
            if s.jong != nil {
                return startSyllable(Syllable(jung: jamo))
            }
            if let jung = s.jung {
                if let combined = layout.combine(jung, jamo) {
                    return update { $0.jung = combined }
                }
                return startSyllable(Syllable(jung: jamo))
            }
            return update { $0.jung = jamo }

        case .jongseong:
            if let jong = s.jong {
                if let combined = layout.combine(jong, jamo) {
                    return update { $0.jong = combined }
                }
                return startSyllable(Syllable(jong: jamo))
            }
            if s.jung != nil {
                return update { $0.jong = jamo }
            }
            return startSyllable(Syllable(jong: jamo))

        case nil:
            return startSyllable(Syllable())
        }
    }

    // MARK: - State

    /// Applies a change to the current syllable, keeping the previous state for backspace.
    private mutating func update(_ change: (inout Syllable) -> Void) -> String {
        history.append(current)
        change(&current)
        return ""
    }

    /// Commits the current syllable and starts a new one from a single jamo.
    private mutating func startSyllable(_ syllable: Syllable) -> String {
        let committed = current.render()
        current = syllable
        history = syllable.isEmpty ? [] : [Syllable()]
        return committed
    }
}
