import SwiftUI
import WebKit

struct DescriptionView: NSViewRepresentable {
    let html: String
    @Binding var height: CGFloat

    static func document(_ html: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
        <style>:root { color-scheme: light dark; overflow: hidden; } body { display: flow-root; font: -apple-system-body; margin: 0; padding: 8px; overflow-wrap: anywhere; } img, video, table { max-width: 100%; } a { color: inherit; pointer-events: none; }</style>
        </head><body>\(html)</body></html>
        """
    }

    func makeNSView(context: Context) -> DescriptionWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = DescriptionWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ view: DescriptionWebView, context: Context) {
        view.contentHeight = $height
        guard context.coordinator.html != html else { return }
        context.coordinator.html = html
        view.loadHTMLString(Self.document(html), baseURL: nil)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var html: String?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            (webView as? DescriptionWebView)?.measureHeight()
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
        }
    }
}

final class DescriptionWebView: WKWebView {
    var contentHeight: Binding<CGFloat>?
    private var measuredWidth: CGFloat = 0

    override func layout() {
        super.layout()
        guard bounds.width != measuredWidth else { return }
        measuredWidth = bounds.width
        measureHeight()
    }

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }

    func measureHeight() {
        guard !isLoading, bounds.width > 0 else { return }
        let width = bounds.width
        // Measure the body, not the viewport, so shorter descriptions can shrink too.
        evaluateJavaScript("Math.ceil(document.body.getBoundingClientRect().height)", in: nil, in: .defaultClient) { [weak self] result in
            guard let self, self.bounds.width == width, !self.isLoading,
                  case .success(let value) = result, let number = value as? NSNumber,
                  number.doubleValue.isFinite, number.doubleValue > 0,
                  let binding = self.contentHeight else { return }
            let height = CGFloat(number.doubleValue)
            if abs(binding.wrappedValue - height) > 0.5 { binding.wrappedValue = height }
        }
    }
}
