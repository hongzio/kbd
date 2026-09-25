extension Layout {
    public static let builtIns: [Layout] = [.dubeolsik]
    public static var builtInIDs: [String] { builtIns.map(\.id) }

    public static func builtIn(_ id: String) -> Layout? {
        builtIns.first { $0.id == id }
    }

    /// KS X 5002 두벌식.
    public static let dubeolsik = Layout(
        id: "dubeolsik",
        name: "두벌식",
        automaton: .jamo,
        keymap: dubeolsikKeymap(
            lower: [
                "q": "ㅂ", "w": "ㅈ", "e": "ㄷ", "r": "ㄱ", "t": "ㅅ",
                "y": "ㅛ", "u": "ㅕ", "i": "ㅑ", "o": "ㅐ", "p": "ㅔ",
                "a": "ㅁ", "s": "ㄴ", "d": "ㅇ", "f": "ㄹ", "g": "ㅎ",
                "h": "ㅗ", "j": "ㅓ", "k": "ㅏ", "l": "ㅣ",
                "z": "ㅋ", "x": "ㅌ", "c": "ㅊ", "v": "ㅍ",
                "b": "ㅠ", "n": "ㅜ", "m": "ㅡ",
            ],
            shifted: ["Q": "ㅃ", "W": "ㅉ", "E": "ㄸ", "R": "ㄲ", "T": "ㅆ", "O": "ㅒ", "P": "ㅖ"]
        ),
        combinations: combinations(jungseong: standardVowelClusters, jongseong: standardFinalClusters)
    )

    /// ㅘ ㅙ ㅚ ㅝ ㅞ ㅟ ㅢ
    static let standardVowelClusters: [String: String] = [
        "ㅗㅏ": "ㅘ", "ㅗㅐ": "ㅙ", "ㅗㅣ": "ㅚ",
        "ㅜㅓ": "ㅝ", "ㅜㅔ": "ㅞ", "ㅜㅣ": "ㅟ",
        "ㅡㅣ": "ㅢ",
    ]

    /// ㄳ ㄵ ㄶ ㄺ ㄻ ㄼ ㄽ ㄾ ㄿ ㅀ ㅄ
    static let standardFinalClusters: [String: String] = [
        "ㄱㅅ": "ㄳ", "ㄴㅈ": "ㄵ", "ㄴㅎ": "ㄶ",
        "ㄹㄱ": "ㄺ", "ㄹㅁ": "ㄻ", "ㄹㅂ": "ㄼ", "ㄹㅅ": "ㄽ", "ㄹㅌ": "ㄾ", "ㄹㅍ": "ㄿ", "ㄹㅎ": "ㅀ",
        "ㅂㅅ": "ㅄ",
    ]

    /// Unshifted letters map as given; shifted letters default to their unshifted jamo.
    /// Consonants are stored as initials, vowels as medials.
    private static func dubeolsikKeymap(lower: [Character: Unicode.Scalar],
                                        shifted: [Character: Unicode.Scalar]) -> [String: String] {
        var keymap: [String: String] = [:]
        for (key, compat) in lower {
            keymap[String(key)] = String(conjoiningForTwoSet(compat))
            keymap[key.uppercased()] = String(conjoiningForTwoSet(compat))
        }
        for (key, compat) in shifted {
            keymap[String(key)] = String(conjoiningForTwoSet(compat))
        }
        return keymap
    }

    private static func conjoiningForTwoSet(_ compat: Unicode.Scalar) -> Unicode.Scalar {
        (0x314F...0x3163).contains(compat.value) ? Jamo.jung(compat) : Jamo.cho(compat)
    }

    /// Converts compatibility-jamo notation ("ㅗㅏ": "ㅘ") into conjoining combination entries.
    static func combinations(choseong: [String: String] = [:],
                             jungseong: [String: String] = [:],
                             jongseong: [String: String] = [:]) -> [String: String] {
        var result: [String: String] = [:]
        func add(_ table: [String: String], _ convert: (Unicode.Scalar) -> Unicode.Scalar) {
            for (pair, combined) in table {
                let converted = String(String.UnicodeScalarView(pair.unicodeScalars.map(convert)))
                result[converted] = String(convert(combined.unicodeScalars.first!))
            }
        }
        add(choseong, Jamo.cho)
        add(jungseong, Jamo.jung)
        add(jongseong, Jamo.jong)
        return result
    }
}
