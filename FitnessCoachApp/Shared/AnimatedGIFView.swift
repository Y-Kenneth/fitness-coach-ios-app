import SwiftUI
import WebKit

/// Loads and animates a GIF from a URL.
///
/// SwiftUI's `AsyncImage` shows only the first frame of a GIF. To get actual
/// animation we wrap a `WKWebView` and load the GIF as an HTML img. This is
/// the standard approach for displaying GIFs in iOS apps without pulling in
/// a heavy dependency like SDWebImage.
struct AnimatedGIFView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.scrollView.isScrollEnabled = false
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let html = """
        <!doctype html>
        <html>
        <head>
          <meta name="viewport" content="width=device-width,initial-scale=1">
          <style>
            html, body { margin:0; padding:0; background:transparent; }
            body { display:flex; align-items:center; justify-content:center; height:100vh; }
            img { max-width:100%; max-height:100%; }
          </style>
        </head>
        <body>
          <img src="\(url.absoluteString)" />
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}
