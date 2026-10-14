import AppKit
import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let reader: ReaderState
    let html: String
    var checklistEnabled = false
    var checklistSaving = false
    var checklistRendering = false
    var checklistPromptPresented = false

    func makeCoordinator() -> Coordinator { Coordinator(reader: reader) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(context.coordinator.images, forURLScheme: "mdview-resource")
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.userContentController.add(context.coordinator, contentWorld: Coordinator.taskWorld, name: "taskToggle")
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
        webView.pageZoom = reader.zoom
        if coordinator.html != html || coordinator.imageReloadGeneration != reader.imageReloadGeneration {
            let resourcesChanged = coordinator.imageReloadGeneration != reader.imageReloadGeneration
            coordinator.html = html
            coordinator.imageReloadGeneration = reader.imageReloadGeneration
            coordinator.load(html, forceNavigation: resourcesChanged)
        }
        if coordinator.navigationGeneration != reader.navigationGeneration, let heading = reader.navigationTarget {
            coordinator.navigationGeneration = reader.navigationGeneration
            coordinator.navigate(to: heading)
        }
        coordinator.configureTasks()
        if coordinator.searchGeneration != reader.searchGeneration {
            coordinator.searchGeneration = reader.searchGeneration
            coordinator.find()
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "taskToggle", contentWorld: Coordinator.taskWorld)
        webView.navigationDelegate = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let taskWorld = WKContentWorld.world(name: "MDViewChecklist")
        let reader: ReaderState
        let images = ImageSchemeHandler()
        weak var webView: WKWebView?
        var html: String?
        var imageReloadGeneration = -1
        var navigationGeneration = -1
        var searchGeneration = -1
        private var scrollY = 0.0
        private var loadGeneration = 0
        private var activeLoadGeneration = 0
        private var activeNavigation: WKNavigation?
        private var contentReady = false
        private var pendingTarget: String?
        private var taskConfiguration: String?
        private var taskFocus: (file: URL, source: String, updated: String, task: MarkdownTask)?

        init(reader: ReaderState) {
            self.reader = reader
            images.loadFailed = { [weak reader] in reader?.localImageError = $0 }
        }

        func load(_ html: String, forceNavigation: Bool = false) {
            guard let webView else { return }
            let canUpdateContent = contentReady && !forceNavigation
            loadGeneration += 1
            contentReady = false
            taskConfiguration = nil
            let generation = loadGeneration
            Task { [weak self] in
                guard let self else { return }
                guard generation == loadGeneration else { return }
                if canUpdateContent {
                    // A content refresh stays in the existing page. DOM replacement
                    // and instant scroll restoration happen before its next paint,
                    // avoiding the top-of-page frame produced by a new navigation.
                    let updated = try? await webView.callAsyncJavaScript("""
                    const next = new DOMParser().parseFromString(html, 'text/html');
                    const main = document.getElementById('document');
                    const nextMain = next.getElementById('document');
                    if (!main || !nextMain || next.head.innerHTML !== document.head.innerHTML) return false;
                    const x = window.scrollX, y = window.scrollY;
                    function sameShape(a, b) {
                        if (a.nodeType !== b.nodeType || a.nodeName !== b.nodeName) return false;
                        if ((a.nodeType === Node.TEXT_NODE || a.nodeType === Node.COMMENT_NODE) && a.data !== b.data) return false;
                        const oldChildren = Array.from(a.childNodes), newChildren = Array.from(b.childNodes);
                        return oldChildren.length === newChildren.length && oldChildren.every((child, i) => sameShape(child, newChildren[i]));
                    }
                    function syncAttributes(a, b) {
                        if (a.nodeType === Node.ELEMENT_NODE) {
                            for (const attribute of Array.from(a.attributes)) {
                                if (!b.hasAttribute(attribute.name)) a.removeAttribute(attribute.name);
                            }
                            for (const attribute of Array.from(b.attributes)) {
                                if (a.getAttribute(attribute.name) !== attribute.value) a.setAttribute(attribute.name, attribute.value);
                            }
                        }
                        const newChildren = Array.from(b.childNodes);
                        Array.from(a.childNodes).forEach((child, i) => syncAttributes(child, newChildren[i]));
                    }
                    // Checkbox-only changes retain existing inputs, text and
                    // loaded images; do not reload an image above the viewport.
                    if (sameShape(main, nextMain)) syncAttributes(main, nextMain);
                    else main.replaceChildren(...Array.from(nextMain.childNodes));
                    document.body.className = next.body.className;
                    const previousScrollBehavior = document.documentElement.style.scrollBehavior;
                    document.documentElement.style.scrollBehavior = 'auto';
                    window.scrollTo(x, y);
                    document.documentElement.style.scrollBehavior = previousScrollBehavior;
                    return true;
                    """, arguments: ["html": html], in: nil, contentWorld: Self.taskWorld) as? Bool
                    guard generation == loadGeneration else { return }
                    if updated == true {
                        activeLoadGeneration = generation
                        activeNavigation = nil
                        contentReady = true
                        configureTasks()
                        if let target = pendingTarget { pendingTarget = nil; navigate(to: target) }
                        if !reader.searchText.isEmpty { find() }
                        return
                    }
                }
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
                _ = try? await webView.callAsyncJavaScript("""
                    const previous = document.documentElement.style.scrollBehavior;
                    document.documentElement.style.scrollBehavior = 'auto';
                    window.scrollTo(0, y);
                    document.documentElement.style.scrollBehavior = previous;
                    """, arguments: ["y": y], in: nil, contentWorld: .page)
                if let target { navigate(to: target) }
            }
            configureTasks()
            if !reader.searchText.isEmpty { find() }
        }

        func configureTasks() {
            guard contentReady, let webView else { return }
            let enabled = reader.fileURL != nil && !reader.isStreamingPreview && !reader.checklistSaving && !reader.isRendering && !reader.showChecklistConfirmation && html == reader.rendered?.html
            let canSave = reader.checklistMode
            let token = String(activeLoadGeneration)
            let configuration = "\(token):\(enabled):\(canSave):\(reader.checklistSaving):\(reader.isRendering):\(reader.showChecklistConfirmation)"
            guard taskConfiguration != configuration else { return }
            taskConfiguration = configuration
            var focusID = -1
            if enabled, let pending = taskFocus {
                if reader.fileURL == pending.file,
                   reader.source == pending.source || reader.source == pending.updated,
                   let task = reader.rendered?.tasks.first(where: { $0.id == pending.task.id }),
                   task.utf8Offset == pending.task.utf8Offset, task.label == pending.task.label {
                    focusID = task.id
                }
                taskFocus = nil
            }
            Task { [weak self] in
                guard let self, contentReady, String(activeLoadGeneration) == token, taskConfiguration == configuration else { return }
                do {
                    // DOM focus alone is insufficient after a native consent
                    // sheet: restore WebKit's responder so Tab/Space reach it.
                    // This does not activate the app or bring its window forward.
                    if focusID >= 0 { webView.window?.makeFirstResponder(webView) }
                    _ = try await webView.callAsyncJavaScript("""
                    window.mdviewTaskState = { enabled, canSave, token };
                    for (const input of document.querySelectorAll('input[data-mdview-task]')) {
                        input.disabled = !enabled;
                        if (!saving && !rendering) input.checked = input.defaultChecked;
                        input.title = canSave ? 'Save this checkbox change to the Markdown file' : 'Click to save checkmarks in this file';
                    }
                    if (enabled && focusID >= 0) {
                        document.querySelector(`input[data-mdview-task="${focusID}"]`)?.focus({preventScroll: true});
                    }
                    if (!window.mdviewTaskListener) {
                        window.mdviewTaskListener = true;
                        document.addEventListener('change', event => {
                            const input = event.target;
                            const state = window.mdviewTaskState;
                            if (!event.isTrusted || !state.enabled || !(input instanceof HTMLInputElement) || !input.hasAttribute('data-mdview-task')) return;
                            const checked = input.checked;
                            if (!state.canSave) input.checked = input.defaultChecked;
                            for (const box of document.querySelectorAll('input[data-mdview-task]')) box.disabled = true;
                            window.webkit.messageHandlers.taskToggle.postMessage({id: Number(input.dataset.mdviewTask), checked, token: state.token});
                        });
                    }
                    """, arguments: ["enabled": enabled, "canSave": canSave, "token": token, "saving": reader.checklistSaving, "rendering": reader.isRendering, "focusID": focusID], in: nil, contentWorld: Self.taskWorld)
                } catch {
                    if reader.checklistMode { reader.checklistError = "Could not activate checklist controls: \(error.localizedDescription)" }
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard contentReady, message.frameInfo.isMainFrame, message.name == "taskToggle",
                  let body = message.body as? [String: Any],
                  body["token"] as? String == String(activeLoadGeneration),
                  let id = body["id"] as? Int, let checked = body["checked"] as? Bool else { return }
            guard let file = reader.fileURL, let task = reader.rendered?.tasks.first(where: { $0.id == id }),
                  let patched = try? MarkdownTasks.patch(Data(reader.source.utf8), expectedSource: reader.source, task: task, checked: checked) else { return }
            let source = reader.source
            if reader.requestTaskChecked(id, checked: checked) {
                taskFocus = (file, source, String(decoding: patched, as: UTF8.self), task)
            }
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
            // An empty field has no search request. In particular, do not
            // queue unnecessary native Find work during initial loading.
            guard !reader.searchText.isEmpty else { reader.searchFound = true; return }
            guard contentReady else { return } // didFinish searches the latest query.
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
