import AppKit
import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let reader: ReaderState
    let html: String

    func makeCoordinator() -> Coordinator { Coordinator(reader: reader) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(context.coordinator.images, forURLScheme: "mdview-resource")
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setAccessibilityLabel("Markdown document")
        webView.allowsLinkPreview = false
        context.coordinator.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.images.documentURL = reader.fileURL
        coordinator.images.allowedRoot = reader.imageRoot
        webView.pageZoom = reader.zoom
        if coordinator.html != html || coordinator.imageRoot != reader.imageRoot ||
           coordinator.imageAccessGeneration != reader.imageAccessGeneration {
            coordinator.html = html
            coordinator.imageRoot = reader.imageRoot
            coordinator.imageAccessGeneration = reader.imageAccessGeneration
            coordinator.load(html)
        }
        if coordinator.navigationGeneration != reader.navigationGeneration, let heading = reader.navigationTarget {
            coordinator.navigationGeneration = reader.navigationGeneration
            coordinator.navigate(to: heading)
        }
        if coordinator.searchGeneration != reader.searchGeneration {
            coordinator.searchGeneration = reader.searchGeneration
            coordinator.find()
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let reader: ReaderState
        let images = ImageSchemeHandler()
        weak var webView: WKWebView?
        var html: String?
        var imageRoot: URL?
        var imageAccessGeneration = -1
        var navigationGeneration = -1
        var searchGeneration = -1
        private var scrollY = 0.0
        private var loadGeneration = 0
        private var activeLoadGeneration = 0
        private var activeNavigation: WKNavigation?
        private var contentReady = false
        private var pendingTarget: String?

        init(reader: ReaderState) {
            self.reader = reader
            images.permissionDenied = { [weak reader] in reader?.imagePermissionRequired = true }
        }

        func load(_ html: String) {
            guard let webView else { return }
            loadGeneration += 1
            contentReady = false
            let generation = loadGeneration
            Task { [weak self] in
                guard let self else { return }
                // JavaScript requested before the first navigation can wait for
                // a document to exist. Load the first page without that wait.
                if webView.url != nil,
                   let y = try? await webView.evaluateJavaScript("window.scrollY") as? Double { scrollY = y }
                guard generation == loadGeneration else { return }
                activeLoadGeneration = generation
                activeNavigation = webView.loadHTMLString(html, baseURL: reader.fileURL?.deletingLastPathComponent())
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard navigation === activeNavigation, activeLoadGeneration == loadGeneration else { return }
            contentReady = true
            let y = scrollY
            let target = pendingTarget
            pendingTarget = nil
            Task {
                _ = try? await webView.callAsyncJavaScript("window.scrollTo(0, y)", arguments: ["y": y], in: nil, contentWorld: .page)
                if let target { navigate(to: target) }
            }
            if !reader.searchText.isEmpty { find() }
        }

        func navigate(to id: String) {
            guard let webView else { return }
            guard contentReady else { pendingTarget = id; return }
            Task {
                _ = try? await webView.callAsyncJavaScript("document.getElementById(id)?.scrollIntoView()",
                    arguments: ["id": id], in: nil, contentWorld: .page)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
            if (error as NSError).code != NSURLErrorCancelled { reader.errorMessage = error.localizedDescription }
        }

        func find() {
            guard let webView else { return }
            let configuration = WKFindConfiguration()
            configuration.backwards = reader.searchBackwards
            configuration.caseSensitive = false
            configuration.wraps = true
            let query = reader.searchText
            let generation = reader.searchGeneration
            Task { [weak self] in
                let result = try? await webView.find(query, configuration: configuration)
                guard let self, generation == reader.searchGeneration else { return }
                reader.searchFound = result?.matchFound == true || query.isEmpty
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard navigationAction.navigationType == .linkActivated else {
                return ["about", "file"].contains(navigationAction.request.url?.scheme ?? "") ? .allow : .cancel
            }
            guard let url = navigationAction.request.url else { return .cancel }
            if url.fragment != nil && (url.scheme == "about" || url.deletingFragment == webView.url?.deletingFragment) {
                return .allow
            }
            switch url.scheme?.lowercased() {
            case "http", "https", "mailto": NSWorkspace.shared.open(url)
            case "file":
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
                    if let error { NSApp.presentError(error) }
                }
            default: break
            }
            return .cancel
        }
    }
}

private extension URL {
    var deletingFragment: URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return nil }
        components.fragment = nil
        return components.url
    }
}
