/// Hangul jamo are handled in Unicode conjoining form (첫가끝, U+1100 block). Initial, medial and
/// final consonants are distinct code points, which role-explicit layouts (세벌식) and old Hangul
/// need. Compatibility jamo (U+3131 block) are only used for notation and for displaying
/// incomplete syllables.
public enum JamoRole: Sendable {
    case choseong
    case jungseong
    case jongseong
}

public enum Jamo {
    static let modernChoseong: ClosedRange<UInt32> = 0x1100...0x1112
    static let modernJungseong: ClosedRange<UInt32> = 0x1161...0x1175
    static let modernJongseong: ClosedRange<UInt32> = 0x11A8...0x11C2

    private static let choseongCompatibility = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ".unicodeScalars)
    private static let jongseongCompatibility = Array("ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ".unicodeScalars)
    private static let jungseongCompatibilityBase: UInt32 = 0x314F  // ㅏ; ㅏ…ㅣ are contiguous

    static func role(of scalar: Unicode.Scalar) -> JamoRole? {
        switch scalar.value {
        case 0x1100...0x115F, 0xA960...0xA97C: .choseong
        case 0x1160...0x11A7, 0xD7B0...0xD7C6: .jungseong
        case 0x11A8...0x11FF, 0xD7CB...0xD7FB: .jongseong
        default: nil
        }
    }

    // MARK: - Notation (compatibility jamo → conjoining)

    /// Initial consonant for a compatibility jamo, e.g. `cho("ㄱ")` → U+1100.
    public static func cho(_ compatibility: Unicode.Scalar) -> Unicode.Scalar {
        let index = choseongCompatibility.firstIndex(of: compatibility)!
        return Unicode.Scalar(modernChoseong.lowerBound + UInt32(index))!
    }

    /// Medial vowel for a compatibility jamo, e.g. `jung("ㅏ")` → U+1161.
    public static func jung(_ compatibility: Unicode.Scalar) -> Unicode.Scalar {
        let index = compatibility.value - jungseongCompatibilityBase
        precondition(index < 21, "not a modern vowel: \(compatibility)")
        return Unicode.Scalar(modernJungseong.lowerBound + index)!
    }

    /// Final consonant for a compatibility jamo, e.g. `jong("ㄱ")` → U+11A8.
    public static func jong(_ compatibility: Unicode.Scalar) -> Unicode.Scalar {
        let index = jongseongCompatibility.firstIndex(of: compatibility)!
        return Unicode.Scalar(modernJongseong.lowerBound + UInt32(index))!
    }

    // MARK: - Conversions

    /// Compatibility jamo for a modern conjoining jamo, used to display incomplete syllables.
    static func compatibility(_ scalar: Unicode.Scalar) -> Unicode.Scalar? {
        let v = scalar.value
        if modernChoseong.contains(v) {
            return choseongCompatibility[Int(v - modernChoseong.lowerBound)]
        }
        if modernJungseong.contains(v) {
            return Unicode.Scalar(jungseongCompatibilityBase + v - modernJungseong.lowerBound)
        }
        if modernJongseong.contains(v) {
            return jongseongCompatibility[Int(v - modernJongseong.lowerBound)]
        }
        return nil
    }

    /// Final form of an initial consonant (ㄱ → ᆨ); nil for ㄸ ㅃ ㅉ, which can't be finals.
    static func jongseong(fromChoseong scalar: Unicode.Scalar) -> Unicode.Scalar? {
        guard let compat = compatibility(scalar),
              let index = jongseongCompatibility.firstIndex(of: compat) else { return nil }
        return Unicode.Scalar(modernJongseong.lowerBound + UInt32(index))
    }

    /// Initial form of a final consonant (ᆨ → ㄱ); nil for clusters like ㄳ.
    static func choseong(fromJongseong scalar: Unicode.Scalar) -> Unicode.Scalar? {
        guard let compat = compatibility(scalar),
              let index = choseongCompatibility.firstIndex(of: compat) else { return nil }
        return Unicode.Scalar(modernChoseong.lowerBound + UInt32(index))
    }
}
