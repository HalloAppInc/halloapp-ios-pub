//
//  HalloApp
//
//  Created by Tony Jiang on 9/24/21.
//  Copyright © 2021 HalloApp, Inc. All rights reserved.
//

import MarkdownKit
import UIKit

fileprivate struct Constants {
    static let italicRegex = "(\\s|^)(_)(?![_\\s])(.+?)(?<![_\\s])(\\2)"
    static let strikethroughRegex = "(.?|^)(?<!\\@)(\\~)(?=\\S)(.+?)(?<=\\S)(\\2)" // do not match if @ precedes ~ to account for pushnames
    static let boldRegex = "(.?|^)(\\*)(?=\\S)(.+?)(?<=\\S)(\\2)"
}

public class HAMarkdown {

    open var font: MarkdownFont
    open var color: MarkdownColor

    public init(font: MarkdownFont, color: MarkdownColor) {
        self.font = font
        self.color = color
    }

    public func parse(_ str: String) -> NSAttributedString {
        let attStr = NSAttributedString(string: str)
        return parse(attStr)
    }

    public func parse(_ attributedString: NSAttributedString) -> NSAttributedString {
        let markdownParser = HAMarkdownParser(font: font, color: color, customElements: [
            HAMarkdownItalic(font: font, color: color),
            HAMarkdownBold(font: font, color: color),
            HAMarkdownStrikethrough(font: font, color: color)
        ])
        markdownParser.enabledElements = []
        return markdownParser.parse(attributedString)
    }

    public func parseInPlace(_ str: String) -> NSAttributedString {
        let attStr = NSAttributedString(string: str)
        return parseInPlace(attStr)
    }

    public func parseInPlace(_ attributedString: NSAttributedString) -> NSAttributedString {
        let markdownParser = HAMarkdownParser(font: font, color: color, customElements: [
            HAInPlaceMarkdownItalic(font: font, color: color),
            HAInPlaceMarkdownBold(font: font, color: color),
            HAInPlaceMarkdownStrikethrough(font: font, color: color)
        ])
        markdownParser.enabledElements = []
        return markdownParser.parse(attributedString)
    }

}

fileprivate class HAMarkdownParser: MarkdownParser {

    // overriding parse to remove escaping of strings so that \ can be entered
    override open func parse(_ markdown: NSAttributedString) -> NSAttributedString {
        let attributedString = NSMutableAttributedString(attributedString: markdown)
        attributedString.addAttribute(.font, value: font, range: NSRange(location: 0, length: attributedString.length))
        attributedString.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: attributedString.length))
        var elements: [MarkdownElement] = []
        elements.append(contentsOf: customElements)
        elements.forEach { element in
            element.parse(attributedString)
        }
        return attributedString
    }

}

// _single underscore_
fileprivate class HAMarkdownItalic: MarkdownItalic {
    private static let regex = Constants.italicRegex
    override var regex: String { return HAMarkdownItalic.regex }
}

// ~strikethrough~
fileprivate class HAMarkdownStrikethrough: MarkdownStrikethrough {
    private static let regex = Constants.strikethroughRegex
    override var regex: String { return HAMarkdownStrikethrough.regex }
}

// *bold*
fileprivate class HAMarkdownBold: MarkdownBold {
    private static let regex = Constants.boldRegex
    override var regex: String { return HAMarkdownBold.regex }
}

fileprivate class HAInPlaceMarkdownItalic: HAInPlaceMarkdownCommonElement {
    fileprivate static let regex = Constants.italicRegex
    open var font: MarkdownFont?
    open var color: MarkdownColor?
    public var attributes: [NSAttributedString.Key : AnyObject] = [ .obliqueness: NSNumber.init(value: 0.3) ]

    open var regex: String {
        return HAInPlaceMarkdownItalic.regex
    }
    public init(font: MarkdownFont? = nil, color: MarkdownColor? = nil) {
        self.font = font
        self.color = color
    }
}

private class HAInPlaceMarkdownStrikethrough: HAInPlaceMarkdownCommonElement {
    fileprivate static let regex = Constants.strikethroughRegex
    open var font: MarkdownFont?
    open var color: MarkdownColor?
    public var attributes: [NSAttributedString.Key : AnyObject] = [ .strikethroughStyle: NSNumber.init(value: NSUnderlineStyle.single.rawValue) ]
    
    open var regex: String {
        return HAInPlaceMarkdownStrikethrough.regex
    }
    public init(font: MarkdownFont? = nil, color: MarkdownColor? = nil) {
        self.font = font
        self.color = color
    }
}

fileprivate class HAInPlaceMarkdownBold: HAInPlaceMarkdownCommonElement {
    fileprivate static let regex = Constants.boldRegex
    open var font: MarkdownFont?
    open var color: MarkdownColor?
    public var attributes: [NSAttributedString.Key : AnyObject] = [ .strokeWidth: NSNumber.init(value: -3.0) ]

    open var regex: String {
        return HAInPlaceMarkdownBold.regex
    }
    public init(font: MarkdownFont? = nil, color: MarkdownColor? = nil) {
        self.font = font
        self.color = color
    }
}

fileprivate protocol HAInPlaceMarkdownCommonElement: MarkdownElement, MarkdownStyle {
    func addAttributes(_ attributedString: NSMutableAttributedString, range: NSRange)
}

fileprivate extension HAInPlaceMarkdownCommonElement {

    func regularExpression() throws -> NSRegularExpression {
        return try NSRegularExpression(pattern: regex, options: [])
    }

    func addAttributes(_ attributedString: NSMutableAttributedString, range: NSRange) {
        attributedString.addAttributes(attributes, range: range)
    }

    func match(_ match: NSTextCheckingResult, attributedString: NSMutableAttributedString) {
        attributedString.addAttributes([ .foregroundColor: UIColor.systemGray ], range: match.range(at: 2))
        addAttributes(attributedString, range: match.range(at: 3))
        attributedString.addAttributes([ .foregroundColor: UIColor.systemGray ], range: match.range(at: 4))
    }

}
