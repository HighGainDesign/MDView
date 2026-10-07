import Foundation
import WebKit

@MainActor
final class ImageSchemeHandler: NSObject, WKURLSchemeHandler {
    var documentURL: URL?
    var allowedRoot: URL?
    var permissionDenied: (() -> Void)?

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, url.host == "local",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let relativePath = String(components.percentEncodedPath.dropFirst()).removingPercentEncoding,
              let documentURL, let allowedRoot,
              let image = LocalImage.resolve(relativePath, documentURL: documentURL, allowedRoot: allowedRoot) else {
            urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile))
            return
        }
        do {
            let file = try FileHandle(forReadingFrom: image)
            defer { try? file.close() }
            let data = try file.read(upToCount: MarkdownSource.maximumBytes + 1) ?? Data()
            guard data.count <= MarkdownSource.maximumBytes else { throw ReaderError.tooLarge }
            urlSchemeTask.didReceive(URLResponse(url: url, mimeType: LocalImage.mimeType(for: image),
                                                expectedContentLength: data.count, textEncodingName: nil))
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            let failure = error as NSError
            let underlying = failure.userInfo[NSUnderlyingErrorKey] as? NSError
            if (failure.domain == NSCocoaErrorDomain && failure.code == NSFileReadNoPermissionError) ||
               (underlying?.domain == NSPOSIXErrorDomain && [1, 13].contains(underlying?.code ?? 0)) {
                permissionDenied?()
            }
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
