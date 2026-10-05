import AppKit
import Observation
import WebKit

/// One browser page (a WKWebView plus the state the toolbar shows). Each tmux
/// window gets its own tab, so switching windows switches the page with it.
@Observable
final class BrowserTab: NSObject {
    let windowID: String
    @ObservationIgnored let webView: WKWebView

    private(set) var urlString = ""
    private(set) var title = ""
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isLoading = false
    private(set) var progress: Double = 0
    private(set) var hasPage = false
    /// Set to ask the panel to focus its address field (consumed by the panel).
    var wantsAddressFocus = false

    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored var onURLChange: ((String) -> Void)?

    private static let configuration: WKWebViewConfiguration = {
        let config = WKWebViewConfiguration()
        // Persistent cookies/storage shared by every tab, like a normal browser profile.
        config.websiteDataStore = .default()
        // Without a Safari token some sites serve degraded "unsupported browser" pages.
        config.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        config.preferences.isElementFullscreenEnabled = true
        return config
    }()

    init(windowID: String) {
        self.windowID = windowID
        webView = WKWebView(frame: .zero, configuration: Self.configuration)
        super.init()
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.isInspectable = true
        webView.navigationDelegate = self
        webView.uiDelegate = self
        observe()
    }

    private func observe() {
        observations = [
            webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                self?.update { tab in
                    tab.urlString = webView.url?.absoluteString ?? ""
                    tab.hasPage = webView.url != nil
                    if let url = webView.url?.absoluteString { tab.onURLChange?(url) }
                }
            },
            webView.observe(\.title, options: [.new]) { [weak self] webView, _ in
                self?.update { $0.title = webView.title ?? "" }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] webView, _ in
                self?.update { $0.canGoBack = webView.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] webView, _ in
                self?.update { $0.canGoForward = webView.canGoForward }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] webView, _ in
                self?.update { $0.isLoading = webView.isLoading }
            },
            webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
                self?.update { $0.progress = webView.estimatedProgress }
            },
        ]
    }

    private func update(_ change: @escaping (BrowserTab) -> Void) {
        if Thread.isMainThread {
            change(self)
        } else {
            DispatchQueue.main.async { [weak self] in self.map(change) }
        }
    }

    // MARK: - Navigation

    /// Loads whatever the user typed: a URL, a bare host, or a search query.
    func open(_ input: String) {
        guard let url = Omnibox.url(for: input) else { return }
        load(url)
    }

    func load(_ url: URL) {
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    func reloadOrStop() {
        if webView.isLoading { webView.stopLoading() } else { webView.reload() }
    }

    func openInDefaultBrowser() {
        guard let url = webView.url else { return }
        NSWorkspace.shared.open(url)
    }

    func copyURL() {
        guard let url = webView.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }
}

extension BrowserTab: WKNavigationDelegate, WKUIDelegate {
    /// target=_blank links and window.open load in place instead of vanishing.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        NSLog("muxify: browser loaded \(webView.url?.absoluteString ?? "-") (\(webView.title ?? ""))")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("muxify: browser failed \(webView.url?.absoluteString ?? "-"): \(error.localizedDescription)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("muxify: browser failed to start \(webView.url?.absoluteString ?? "-"): \(error.localizedDescription)")
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else {
            decisionHandler(.allow)
            return
        }
        // Hand mailto:, zoommtg:, etc. to the system.
        if !["http", "https", "file", "about", "data", "blob", "javascript"].contains(scheme) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

enum Omnibox {
    static func url(for rawInput: String) -> URL? {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        if let url = URL(string: input), let scheme = url.scheme?.lowercased(),
           ["http", "https", "file", "about"].contains(scheme) {
            return url
        }
        if input.hasPrefix("/") || input.hasPrefix("~/") {
            return URL(fileURLWithPath: (input as NSString).expandingTildeInPath)
        }
        if looksLikeHost(input) {
            let local = isLocal(input)
            return URL(string: (local ? "http://" : "https://") + input)
        }
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: input)]
        return components.url
    }

    private static func looksLikeHost(_ input: String) -> Bool {
        guard !input.contains(" ") else { return false }
        if isLocal(input) { return true }
        let host = input.split(whereSeparator: { "/:?#".contains($0) }).first.map(String.init) ?? input
        return host.contains(".") && !host.hasPrefix(".") && !host.hasSuffix(".")
    }

    private static func isLocal(_ input: String) -> Bool {
        let host = input.split(whereSeparator: { "/:?#".contains($0) }).first.map { $0.lowercased() } ?? ""
        return host == "localhost" || host == "127.0.0.1" || host == "0.0.0.0" || host == "[::1]"
            || host.hasSuffix(".localhost") || host.hasSuffix(".local") || host.hasSuffix(".test")
            || (input.first?.isNumber == true && input.contains(":"))
    }
}
