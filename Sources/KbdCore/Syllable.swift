/// One syllable being composed. Each slot holds a single (possibly combined) conjoining jamo.
struct Syllable: Equatable {
    var cho: Unicode.Scalar?
    var jung: Unicode.Scalar?
    var jong: Unicode.Scalar?

    var isEmpty: Bool { cho == nil && jung == nil && jong == nil }

    /// Precomposed syllable when possible (modern cho + jung [+ jong]); otherwise compatibility
    /// jamo for display, falling back to a conjoining sequence for jamo without one (old Hangul).
    func render() -> String {
        if let cho, let jung,
           Jamo.modernChoseong.contains(cho.value), Jamo.modernJungseong.contains(jung.value),
           jong.map({ Jamo.modernJongseong.contains($0.value) }) ?? true {
            let c = cho.value - Jamo.modernChoseong.lowerBound
            let j = jung.value - Jamo.modernJungseong.lowerBound
            let t = jong.map { $0.value - Jamo.modernJongseong.lowerBound + 1 } ?? 0
            return String(Unicode.Scalar(0xAC00 + (c * 21 + j) * 28 + t)!)
        }
        let parts = [cho, jung, jong].compactMap { $0 }
        let compatibility = parts.compactMap(Jamo.compatibility)
        if compatibility.count == parts.count {
            return String(String.UnicodeScalarView(compatibility))
        }
        var scalars = String.UnicodeScalarView()
        scalars.append(cho ?? "\u{115F}")   // choseong filler
        scalars.append(jung ?? "\u{1160}")  // jungseong filler
        if let jong { scalars.append(jong) }
        return String(scalars)
    }
}
