import Foundation

public protocol FormattableContentRange {
    typealias Shift = Int
    var kind: FormattableRangeKind { get }
    var range: NSRange { get }

    /// Apply the given styles to the given attributed string.
    /// Some ranges can insert element to the string, this generates a shift on the range's location
    /// that needs to be taken into account by other ranges opearing over the same string.
    /// For this we use the `shift` type alias
    ///
    /// - Parameters:
    ///   - styles: The styles to apply
    ///   - string: The attributed string where to apply the styles
    ///   - shift: The shift to be applied on the range's location
    /// - Returns: The shift on the range's location generated by processing this range
    ///.
    func apply(_ styles: FormattableContentStyles, to string: NSMutableAttributedString, withShift shift: Int) -> Shift
}

extension FormattableContentRange {
    func rangeShifted(by shift: Int) -> NSRange {
        return NSMakeRange(range.location + shift, range.length)
    }

    func apply(_ styles: FormattableContentStyles, to string: NSMutableAttributedString, at shiftedRange: NSRange) {

        var shiftedRange = shiftedRange

        // Don't attempt to apply styles past the end of a string – it will cause a crash
        if shiftedRange.upperBound > string.length {
            shiftedRange = NSRange(location: shiftedRange.location, length: string.length - shiftedRange.location)
        }

        if let rangeStyle = styles.rangeStylesMap?[kind] {
            string.addAttributes(rangeStyle, range: shiftedRange)
        }
    }
}

public extension FormattableContentRange where Self: LinkContentRange {
    func apply(_ styles: FormattableContentStyles, to string: NSMutableAttributedString, withShift shift: Int) -> Shift {
        let shiftedRange = rangeShifted(by: shift)

        apply(styles, to: string, at: shiftedRange)
        applyURLStyles(styles, to: string, shiftedRange: shiftedRange)

        return 0
    }
}

public protocol LinkContentRange {
    var url: URL? { get }
    func applyURLStyles(_ styles: FormattableContentStyles, to string: NSMutableAttributedString, shiftedRange: NSRange)
}

extension LinkContentRange where Self: FormattableContentRange {
    public func applyURLStyles(_ styles: FormattableContentStyles, to string: NSMutableAttributedString, shiftedRange: NSRange) {
        if let url, let linksColor = styles.linksColor {
            string.addAttribute(.link, value: url, range: shiftedRange)
            string.addAttribute(.foregroundColor, value: linksColor, range: shiftedRange)
        }
    }
}

public struct FormattableRangeKind: Hashable, Sendable {
    let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

extension FormattableRangeKind {
    public static let user       = FormattableRangeKind("user")
    public static let post       = FormattableRangeKind("post")
    public static let comment    = FormattableRangeKind("comment")
    public static let stats      = FormattableRangeKind("stat")
    public static let follow     = FormattableRangeKind("follow")
    public static let blockquote = FormattableRangeKind("blockquote")
    public static let noticon    = FormattableRangeKind("noticon")
    public static let site       = FormattableRangeKind("site")
    public static let match      = FormattableRangeKind("match")
    public static let link       = FormattableRangeKind("link")
    public static let italic     = FormattableRangeKind("i")
    public static let scan       = FormattableRangeKind("scan")
    public static let strong     = FormattableRangeKind("b")
}
