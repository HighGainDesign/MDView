import Foundation
import QuickLookUI
import UniformTypeIdentifiers

final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        let source = try await MarkdownSource.readInBackground(url)
        let appearance = ReaderPreferences.appearance(in: ReaderPreferences.defaults)
        let rendered = try await MarkdownRenderer.shared.render(source, title: url.lastPathComponent, wide: true, appearance: appearance)
        let data = Data(rendered.html.utf8)
        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 850, height: 700)) { reply in
            reply.stringEncoding = .utf8
            return data
        }
    }
}
