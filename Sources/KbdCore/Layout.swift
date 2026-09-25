/// How a layout's jamo are assembled into syllables.
public enum AutomatonKind: String, Codable, Sendable {
    /// 두벌식 style: consonants carry no position; a consonant after a vowel becomes a final and
    /// moves to the next syllable if a vowel follows (도깨비불).
    case jamo
    /// 세벌식 style: every key produces an explicit initial, medial or final; no 도깨비불.
    case jaso
}

/// Data-only layout definition. Built-in layouts are Swift literals; the same shape is meant to be
/// decoded from user files later.
public struct Layout: Codable, Sendable {
    public var id: String
    public var name: String
    public var automaton: AutomatonKind
    /// ABC-layout character (Shift already applied) → one conjoining jamo, or literal text.
    public var keymap: [String: String]
    /// Two conjoining jamo → combined jamo, e.g. "ᅩᅡ" → "ᅪ". Roles are implied by the code points.
    public var combinations: [String: String]

    public init(id: String, name: String, automaton: AutomatonKind,
                keymap: [String: String], combinations: [String: String]) {
        self.id = id
        self.name = name
        self.automaton = automaton
        self.keymap = keymap
        self.combinations = combinations
    }
}

public enum LayoutError: Error, Equatable {
    case invalidKey(String)
    case invalidKeyOutput(key: String, output: String)
    case invalidCombination(String)
}

/// Validated, lookup-ready form of a `Layout`.
struct CompiledLayout {
    enum KeyOutput {
        case jamo(Unicode.Scalar)
        case text(String)
    }

    private struct Pair: Hashable {
        let first: Unicode.Scalar
        let second: Unicode.Scalar
    }

    let automaton: AutomatonKind
    private let keymap: [Character: KeyOutput]
    private let combined: [Pair: Unicode.Scalar]
    private let splits: [Unicode.Scalar: (Unicode.Scalar, Unicode.Scalar)]

    init(_ layout: Layout) throws(LayoutError) {
        automaton = layout.automaton

        var keymap: [Character: KeyOutput] = [:]
        for (key, output) in layout.keymap {
            guard key.count == 1, let char = key.first else { throw .invalidKey(key) }
            let scalars = Array(output.unicodeScalars)
            if scalars.count == 1, let role = Jamo.role(of: scalars[0]) {
                // 두벌식 consonants are written as initials; the automaton derives finals.
                if layout.automaton == .jamo, role == .jongseong {
                    throw .invalidKeyOutput(key: key, output: output)
                }
                keymap[char] = .jamo(scalars[0])
            } else if !output.isEmpty {
                keymap[char] = .text(output)
            } else {
                throw .invalidKeyOutput(key: key, output: output)
            }
        }
        self.keymap = keymap

        var combined: [Pair: Unicode.Scalar] = [:]
        var splits: [Unicode.Scalar: (Unicode.Scalar, Unicode.Scalar)] = [:]
        for (pair, result) in layout.combinations {
            let input = Array(pair.unicodeScalars)
            let output = Array(result.unicodeScalars)
            guard input.count == 2, output.count == 1,
                  let role = Jamo.role(of: output[0]),
                  Jamo.role(of: input[0]) == role, Jamo.role(of: input[1]) == role
            else { throw .invalidCombination(pair) }
            combined[Pair(first: input[0], second: input[1])] = output[0]
            splits[output[0]] = (input[0], input[1])
        }
        self.combined = combined
        self.splits = splits
    }

    func output(for key: Character) -> KeyOutput? {
        keymap[key]
    }

    func combine(_ first: Unicode.Scalar, _ second: Unicode.Scalar) -> Unicode.Scalar? {
        combined[Pair(first: first, second: second)]
    }

    /// Inverse of `combine`, used to split a final cluster when a vowel follows (도깨비불).
    func split(_ scalar: Unicode.Scalar) -> (Unicode.Scalar, Unicode.Scalar)? {
        splits[scalar]
    }
}
