import Markdown
import MarkdownUI
import SwiftUI
import WebKit

// MARK: - Content Segment

struct ContentSegment: Identifiable {
    enum Kind {
        case markdown(String)
        case html(String)
    }
    let kind: Kind
    let id = UUID()
}

// MARK: - AST-Based Parser

struct SegmentCollector {
    var segments: [ContentSegment] = []
    private var pendingMarkup: [String] = []

    mutating func flushMarkdown() {
        let text = pendingMarkup.joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            segments.append(ContentSegment(kind: .markdown(text)))
        }
        pendingMarkup.removeAll()
    }

    mutating func addHTMLBlock(_ rawHTML: String) {
        let text = rawHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if text.hasPrefix("<!--") && text.hasSuffix("-->") { return }
        flushMarkdown()
        segments.append(ContentSegment(kind: .html(text)))
    }

    mutating func addMarkupBlock(_ markup: any Markup) {
        pendingMarkup.append(markup.format())
    }
}

enum ContentSegmentParser {
    static func parse(_ input: String) -> [ContentSegment] {
        let document = Document(parsing: input)
        var collector = SegmentCollector()

        for child in document.children {
            if let html = child as? HTMLBlock {
                collector.addHTMLBlock(html.rawHTML)
            } else if MarkupHTMLConverter.containsInlineHTML(child) {
                collector.addHTMLBlock(MarkupHTMLConverter.convert(child))
            } else {
                collector.addMarkupBlock(child)
            }
        }
        collector.flushMarkdown()
        return collector.segments
    }
}

// MARK: - Rich Content View

struct RichContentView: View {

    let content: String

    init(_ content: String) {
        self.content = content
    }

    var body: some View {
        let segments = ContentSegmentParser.parse(content)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(segments) { segment in
                switch segment.kind {
                case .markdown(let text):
                    MarkdownUI.Markdown(text)
                        .markdownTheme(.gitHub)
                        .textSelection(.enabled)
                case .html(let text):
                    HTMLSegmentView(html: text)
                }
            }
        }
    }
}

// MARK: - HTML Segment View

private struct HTMLSegmentView: View {
    let html: String
    @State private var height: CGFloat = 50

    var body: some View {
        HTMLBlockView(html: html, contentHeight: $height)
            .frame(height: height)
    }
}

// MARK: - Non-Scrolling WKWebView

private class NonScrollingWKWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}

// MARK: - HTML Block View (WKWebView)

struct HTMLBlockView: NSViewRepresentable {

    let html: String
    @Binding var contentHeight: CGFloat

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = NonScrollingWKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let document = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
            :root { color-scheme: light dark; }
            html, body {
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                font-size: 13px;
                margin: 0; padding: 0;
                background: transparent;
                overflow: hidden;
            }
            table { border-collapse: collapse; width: 100%; font-size: 12px; }
            th, td { border: 1px solid rgba(128,128,128,0.3); padding: 6px 8px; text-align: left; }
            th { font-weight: 600; }
            a { color: -apple-system-blue; }
            code {
                font-family: ui-monospace, SFMono-Regular, monospace;
                font-size: 12px;
                background: rgba(128,128,128,0.1);
                padding: 1px 4px; border-radius: 3px;
            }
            img { max-width: 100%; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
        webView.loadHTMLString(document, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: HTMLBlockView
        init(_ parent: HTMLBlockView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                if let height = result as? CGFloat {
                    DispatchQueue.main.async { self.parent.contentHeight = height }
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
