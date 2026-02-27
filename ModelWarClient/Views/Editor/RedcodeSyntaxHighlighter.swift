import AppKit
import Foundation

enum RedcodeSyntaxHighlighter {
    private static let opcodes = [
        "DAT", "MOV", "ADD", "SUB", "MUL", "DIV", "MOD",
        "JMP", "JMZ", "JMN", "DJN", "CMP", "SEQ", "SNE",
        "SLT", "SPL", "NOP", "LDP", "STP",
    ]

    private static let modifiers = [
        ".A", ".B", ".AB", ".BA", ".F", ".X", ".I",
    ]

    private static let directives = [
        "ORG", "END", "EQU", "FOR", "ROF", "PIN",
    ]

    static func highlight(_ textStorage: NSTextStorage) {
        let text = textStorage.string
        let fullRange = NSRange(location: 0, length: text.utf16.count)
        let defaultFont = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        // Reset to default
        textStorage.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)
        textStorage.addAttribute(.font, value: defaultFont, range: fullRange)

        let nsString = text as NSString

        // Comments (;)
        applyRegex(";.*$", to: textStorage, in: nsString, color: NSColor.systemGray)

        // Labels (word followed by colon, or word at start of non-blank line before opcode)
        applyRegex("^\\s*([A-Za-z_][A-Za-z0-9_]*)\\s", to: textStorage, in: nsString, color: NSColor.systemGreen, group: 1)

        // Opcodes
        let opcodePattern = "\\b(" + opcodes.joined(separator: "|") + ")\\b"
        applyRegex(opcodePattern, to: textStorage, in: nsString, color: NSColor.systemBlue, caseInsensitive: true)

        // Directives
        let directivePattern = "\\b(" + directives.joined(separator: "|") + ")\\b"
        applyRegex(directivePattern, to: textStorage, in: nsString, color: NSColor.systemBlue, caseInsensitive: true)

        // Modifiers
        let modifierPattern = "(\\.(?:A|B|AB|BA|F|X|I))\\b"
        applyRegex(modifierPattern, to: textStorage, in: nsString, color: NSColor.systemCyan)

        // Addressing modes
        applyRegex("[#$@<>{}*]", to: textStorage, in: nsString, color: NSColor.systemOrange)

        // Numbers
        applyRegex("\\b\\d+\\b", to: textStorage, in: nsString, color: NSColor.systemPurple)

        // Redcode directives (;name, ;author, ;strategy, ;redcode)
        applyRegex("^;(redcode|name|author|strategy|assert)\\b.*$", to: textStorage, in: nsString, color: NSColor.systemTeal)
    }

    private static func applyRegex(
        _ pattern: String,
        to textStorage: NSTextStorage,
        in nsString: NSString,
        color: NSColor,
        group: Int = 0,
        caseInsensitive: Bool = false
    ) {
        var options: NSRegularExpression.Options = [.anchorsMatchLines]
        if caseInsensitive {
            options.insert(.caseInsensitive)
        }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let fullRange = NSRange(location: 0, length: nsString.length)

        regex.enumerateMatches(in: nsString as String, range: fullRange) { match, _, _ in
            guard let match, group < match.numberOfRanges else { return }
            let range = match.range(at: group)
            if range.location != NSNotFound {
                textStorage.addAttribute(.foregroundColor, value: color, range: range)
            }
        }
    }
}
