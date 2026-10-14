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
        if coordinator.navigationGeneration != reader.navigationGeneration, let request = reader.navigationRequest {
            coordinator.navigationGeneration = reader.navigationGeneration
            coordinator.navigate(request)
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
        private var readingPosition: [String: Any]?
        private static let documentScript: String = {
            guard let url = Bundle.main.url(forResource: "reader-document", withExtension: "js"),
                  let script = try? String(contentsOf: url, encoding: .utf8) else { return "return false;" }
            return script
        }()
        private var loadGeneration = 0
        private var activeLoadGeneration = 0
        private var activeNavigation: WKNavigation?
        private var contentReady = false
        private var pendingTarget: ReaderNavigation?
        private var taskConfiguration: String?
        private var taskFocus: (file: URL, source: String, updated: String, task: MarkdownTask, focusIntent: Int)?

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
                    // Reconcile sanitized nodes and preserve the visible reading
                    // anchor in the same page, before the next paint.
                    let updated = try? await webView.callAsyncJavaScript(Self.documentScript,
                        arguments: ["operation": "update", "html": html,
                                    "restoreFocus": Self.hasDocumentFocus(webView)],
                        in: nil, contentWorld: Self.taskWorld) as? Bool
                    guard generation == loadGeneration else { return }
                    if updated == true {
                        activeLoadGeneration = generation
                        activeNavigation = nil
                        contentReady = true
                        configureTasks()
                        if let target = pendingTarget { pendingTarget = nil; navigate(target) }
                        if !reader.searchText.isEmpty { find() }
                        return
                    }
                }
                // JavaScript requested before the first navigation can wait for
                // a document to exist. Load the first page without that wait.
                if webView.url != nil {
                    readingPosition = try? await webView.callAsyncJavaScript(Self.documentScript,
                        arguments: ["operation": "capture"], in: nil, contentWorld: Self.taskWorld) as? [String: Any]
                }
                guard generation == loadGeneration else { return }
                activeLoadGeneration = generation
                activeNavigation = webView.loadHTMLString(html, baseURL: reader.fileURL?.deletingLastPathComponent())
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard navigation === activeNavigation, activeLoadGeneration == loadGeneration else { return }
            contentReady = true
            let position = readingPosition
            let target = pendingTarget
            pendingTarget = nil
            Task {
                if let position {
                    _ = try? await webView.callAsyncJavaScript(Self.documentScript,
                        arguments: ["operation": "restore", "position": position], in: nil, contentWorld: Self.taskWorld)
                }
                if let target { navigate(target) }
            }
            configureTasks()
            if !reader.searchText.isEmpty { find() }
        }

        func configureTasks() {
            guard contentReady, let webView else { return }
            let enabled = reader.fileURL != nil && !reader.isStreamingPreview && !reader.hasPendingFileUpdate && !reader.checklistSaving && !reader.isRendering && !reader.showChecklistConfirmation && html == reader.rendered?.html
            let canSave = reader.checklistMode
            let token = String(activeLoadGeneration)
            let focusIntent = reader.focusIntentGeneration
            let configuration = "\(focusIntent):\(token):\(enabled):\(canSave):\(reader.checklistSaving):\(reader.isRendering):\(reader.showChecklistConfirmation)"
            guard taskConfiguration != configuration else { return }
            taskConfiguration = configuration
            var focusID = -1
            if enabled, let pending = taskFocus {
                if reader.focusIntentGeneration == pending.focusIntent,
                   !(webView.window?.firstResponder is NSTextView),
                   reader.fileURL == pending.file,
                   reader.source == pending.source || reader.source == pending.updated,
                   let task = reader.rendered?.tasks.first(where: { $0.id == pending.task.id }),
                   task.utf8Offset == pending.task.utf8Offset, task.label == pending.task.label {
                    focusID = task.id
                }
                taskFocus = nil
            }
            Task { [weak self] in
                guard let self, contentReady, String(activeLoadGeneration) == token, taskConfiguration == configuration, reader.focusIntentGeneration == focusIntent else { return }
                do {
                    // DOM focus alone is insufficient after a native consent
                    // sheet: restore WebKit's responder so Tab/Space reach it.
                    // This does not activate the app or bring its window forward.
                    if focusID >= 0 { webView.window?.makeFirstResponder(webView) }
                    _ = try await webView.callAsyncJavaScript("""
                    if (!enabled && document.activeElement instanceof HTMLInputElement && document.activeElement.hasAttribute('data-mdview-task')) {
                        const selection = getSelection();
                        window.mdviewPendingTaskFocus = {node:document.activeElement, intent:focusIntent,
                            selection:selection?.rangeCount ? {anchor:selection.anchorNode, anchorOffset:selection.anchorOffset,
                                focus:selection.focusNode, focusOffset:selection.focusOffset} : null};
                    }
                    window.mdviewTaskState = { enabled, canSave, token };
                    for (const input of document.querySelectorAll('input[data-mdview-task]')) {
                        input.disabled = !enabled;
                        if (!saving && !rendering) input.checked = input.defaultChecked;
                        input.title = canSave ? 'Save this checkbox change to the Markdown file' : 'Click to save checkmarks in this file';
                    }
                    if (enabled) {
                        if (focusID >= 0) {
                            document.querySelector(`input[data-mdview-task="${focusID}"]`)?.focus({preventScroll: true});
                        } else if (restoreFocus && window.mdviewPendingTaskFocus?.intent === focusIntent && window.mdviewPendingTaskFocus.node.isConnected) {
                            const pending = window.mdviewPendingTaskFocus;
                            pending.node.focus({preventScroll:true});
                            const selection = pending.selection;
                            if (selection?.anchor?.isConnected && selection?.focus?.isConnected) {
                                const limit = node => node.nodeType === Node.TEXT_NODE ? node.length : node.childNodes.length;
                                getSelection().setBaseAndExtent(selection.anchor, Math.min(selection.anchorOffset,limit(selection.anchor)),
                                    selection.focus, Math.min(selection.focusOffset,limit(selection.focus)));
                            }
                        }
                        window.mdviewPendingTaskFocus = null;
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
                    """, arguments: ["enabled": enabled, "canSave": canSave, "token": token, "saving": reader.checklistSaving, "rendering": reader.isRendering, "focusID": focusID, "focusIntent": focusIntent, "restoreFocus": Self.hasDocumentFocus(webView)], in: nil, contentWorld: Self.taskWorld)
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
                taskFocus = (file, source, String(decoding: patched, as: UTF8.self), task, reader.focusIntentGeneration)
            }
        }

        private static func hasDocumentFocus(_ webView: WKWebView) -> Bool {
            guard let responder = webView.window?.firstResponder else { return false }
            return responder === webView || (responder as? NSView)?.isDescendant(of: webView) == true
        }

        func navigate(_ request: ReaderNavigation) {
            guard let webView else { return }
            guard contentReady else { pendingTarget = request; return }
            Task { [weak self] in
                guard let self, reader.navigationRequest == request else { return }
                let focus = request.focus && reader.focusIntentGeneration == request.focusIntent
                if focus { webView.window?.makeFirstResponder(webView) }
                var arguments: [String: Any] = ["operation": "navigate", "focus": focus]
                switch request.destination {
                case .element(let id): arguments["kind"] = "element"; arguments["id"] = id
                case .uncheckedTask(let backwards): arguments["kind"] = "unchecked"; arguments["backwards"] = backwards
                case .readingPosition: arguments["kind"] = "reading"
                }
                _ = try? await webView.callAsyncJavaScript(Self.documentScript,
                    arguments: arguments, in: nil, contentWorld: Self.taskWorld)
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
