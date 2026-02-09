import Foundation
import Markdown

enum MarkupHTMLConverter {

    static func containsInlineHTML(_ node: any Markup) -> Bool {
        for child in node.children {
            if child is InlineHTML { return true }
            if containsInlineHTML(child) { return true }
        }
        return false
    }

    static func convert(_ node: any Markup) -> String {
        if let heading = node as? Heading {
            let level = heading.level
            let inner = heading.children.map { convert($0) }.joined()
            return "<h\(level)>\(inner)</h\(level)>\n"
        } else if let paragraph = node as? Paragraph {
            let inner = paragraph.children.map { convert($0) }.joined()
            return "<p>\(inner)</p>\n"
        } else if let text = node as? Text {
            return text.string
        } else if let strong = node as? Strong {
            let inner = strong.children.map { convert($0) }.joined()
            return "<strong>\(inner)</strong>"
        } else if let emphasis = node as? Emphasis {
            let inner = emphasis.children.map { convert($0) }.joined()
            return "<em>\(inner)</em>"
        } else if let code = node as? InlineCode {
            return "<code>\(code.code)</code>"
        } else if let link = node as? Link {
            let inner = link.children.map { convert($0) }.joined()
            return "<a href=\"\(link.destination ?? "")\">\(inner)</a>"
        } else if let image = node as? Image {
            return "<img src=\"\(image.source ?? "")\" alt=\"\(image.plainText)\">"
        } else if let inlineHTML = node as? InlineHTML {
            return inlineHTML.rawHTML
        } else if let htmlBlock = node as? HTMLBlock {
            return htmlBlock.rawHTML
        } else if let list = node as? UnorderedList {
            let items = list.children.map { convert($0) }.joined()
            return "<ul>\(items)</ul>\n"
        } else if let list = node as? OrderedList {
            let items = list.children.map { convert($0) }.joined()
            return "<ol>\(items)</ol>\n"
        } else if let item = node as? ListItem {
            let inner = item.children.map { convert($0) }.joined()
            return "<li>\(inner)</li>\n"
        } else if let quote = node as? BlockQuote {
            let inner = quote.children.map { convert($0) }.joined()
            return "<blockquote>\(inner)</blockquote>\n"
        } else if node is SoftBreak {
            return "\n"
        } else if node is LineBreak {
            return "<br>"
        } else if node is ThematicBreak {
            return "<hr>\n"
        } else if let codeBlock = node as? CodeBlock {
            let lang = codeBlock.language ?? ""
            return "<pre><code class=\"language-\(lang)\">\(codeBlock.code)</code></pre>\n"
        }
        return node.children.map { convert($0) }.joined()
    }
}
