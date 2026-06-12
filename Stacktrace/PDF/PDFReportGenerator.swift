import AppKit
import WebKit
import PDFKit

/// Renders report HTML to a multi-page A4 PDF on disk.
///
/// We deliberately avoid `NSPrintOperation`, whose WKWebView print path hangs
/// (runaway pagination) on current macOS. Instead we load the HTML, measure its
/// full height, then capture fixed A4-height slices with `WKWebView.pdf(...)`
/// and stitch them into one document with PDFKit. Keep a strong reference to
/// the instance until the completion handler fires.
@MainActor
final class PDFReportGenerator: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var window: NSWindow?
    private var outputURL: URL?
    private var completion: ((Result<URL, Error>) -> Void)?

    // A4 at 72 dpi.
    private let pageWidth: CGFloat = 595
    private let pageHeight: CGFloat = 842

    enum GenerationError: LocalizedError {
        case renderFailed
        case writeFailed
        var errorDescription: String? {
            switch self {
            case .renderFailed: return "Could not render the report content."
            case .writeFailed: return "Could not write the PDF file."
            }
        }
    }

    func generate(
        html: String,
        to url: URL,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        self.outputURL = url
        self.completion = completion

        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
        webView.navigationDelegate = self
        self.webView = webView

        // Host in an invisible (alpha 0) window so WebKit lays the content out.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: pageWidth, height: pageHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.alphaValue = 0
        window.contentView = webView
        window.orderFront(nil)
        self.window = window

        webView.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { await render() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!,
                 withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        finish(.failure(error))
    }

    private func render() async {
        guard let webView, let outputURL else { return }

        // Let layout settle, then run pagination JS: it shifts any block that
        // would straddle a page boundary down to the next page, so the fixed
        // A4-height slices below break between entries instead of mid-text.
        // The script returns the resulting full document height.
        try? await Task.sleep(nanoseconds: 300_000_000)
        let measured = try? await webView.evaluateJavaScript(paginationScript)
        let contentHeight = (measured as? NSNumber)?.doubleValue ?? Double(pageHeight)
        let fullHeight = max(CGFloat(contentHeight), pageHeight)

        // Resize so every slice is laid out, then give it a beat to reflow.
        webView.frame = NSRect(x: 0, y: 0, width: pageWidth, height: fullHeight)
        try? await Task.sleep(nanoseconds: 200_000_000)

        let document = PDFDocument()
        var pageIndex = 0
        var y: CGFloat = 0
        while y < fullHeight {
            let sliceHeight = min(pageHeight, fullHeight - y)
            let config = WKPDFConfiguration()
            config.rect = CGRect(x: 0, y: y, width: pageWidth, height: sliceHeight)
            if let data = try? await webView.pdf(configuration: config),
               let slice = PDFDocument(data: data),
               let page = slice.page(at: 0) {
                document.insert(page, at: pageIndex)
                pageIndex += 1
            }
            y += pageHeight
        }

        guard pageIndex > 0 else {
            finish(.failure(GenerationError.renderFailed))
            return
        }
        if document.write(to: outputURL) {
            finish(.success(outputURL))
        } else {
            finish(.failure(GenerationError.writeFailed))
        }
    }

    /// Pushes breakable blocks (.day headers and .entry cards) onto the next
    /// page when they would cross a page boundary, leaving a top and bottom
    /// margin on every page. Reads live layout so each shift reflows the rest.
    private var paginationScript: String {
        """
        (function(){
          var PAGE = \(Int(pageHeight));
          var TOPGAP = 28;     // breathing room at top of pushed pages
          var BOTTOM = 40;     // min whitespace before a page break
          var nodes = Array.from(document.querySelectorAll('.day h2, .entry'));
          for (var i = 0; i < nodes.length; i++){
            var el = nodes[i];
            var r = el.getBoundingClientRect();
            var top = r.top + window.scrollY;
            var bottom = r.bottom + window.scrollY;
            var height = bottom - top;
            var pageOf = Math.floor(top / PAGE);
            var limit = pageOf * PAGE + (PAGE - BOTTOM);
            if (bottom > limit && height <= (PAGE - BOTTOM - TOPGAP)){
              var newTop = (pageOf + 1) * PAGE + TOPGAP;
              var cur = parseFloat(getComputedStyle(el).marginTop) || 0;
              el.style.marginTop = (cur + (newTop - top)) + 'px';
            }
          }
          return Math.max(document.body.scrollHeight, document.documentElement.scrollHeight);
        })()
        """
    }

    private func finish(_ result: Result<URL, Error>) {
        completion?(result)
        completion = nil
        webView?.navigationDelegate = nil
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil
        webView = nil
        outputURL = nil
    }
}
