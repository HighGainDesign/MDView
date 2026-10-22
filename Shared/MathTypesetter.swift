import Foundation
import JavaScriptCore
import SwiftSoup

/// Actor-confined, lazy KaTeX instance. No DOM, network API, persistent macros or
/// author scripts. Generated MathML is inserted only after author HTML sanitizing.
final class MathTypesetter {
    private var context: JSContext?

    func render(_ tex: String, display: Bool) -> String? {
        guard tex.utf8.count <= 16_384 else { return nil }
        if context == nil {
            guard let url = Bundle(for: MathBundleMarker.self).url(forResource: "katex.min", withExtension: "js"),
                  let script = try? String(contentsOf: url, encoding: .utf8), let js = JSContext() else { return nil }
            js.evaluateScript(script)
            guard js.exception == nil else { return nil }
            context = js
        }
        guard let context else { return nil }
        context.exception = nil
        let options: [String: Any] = ["output": "mathml", "displayMode": display, "trust": false,
                                     "throwOnError": true, "maxExpand": 1_000, "maxSize": 20, "strict": "error"]
        let html = context.objectForKeyedSubscript("katex")?.invokeMethod("renderToString", withArguments: [tex, options])
        guard context.exception == nil, let result = html?.toString(), result.utf8.count <= 512_000,
              let doc = try? SwiftSoup.parseBodyFragment(result),
              let math = try? doc.select("math").first() else { return nil }
        // Defense in depth: only static MathML from the trusted typesetter.
        let tags: Set<String> = ["math", "semantics", "annotation", "mrow", "mi", "mn", "mo", "mtext", "mspace", "mfrac", "msqrt", "mroot", "msub", "msup", "msubsup", "munder", "mover", "munderover", "mtable", "mtr", "mtd", "mstyle", "mpadded", "mphantom", "menclose", "mmultiscripts", "mprescripts", "none"]
        guard let elements = try? math.getAllElements().array(), elements.allSatisfy({ tags.contains($0.tagName()) }) else { return nil }
        for element in elements {
            for attr in element.getAttributes()?.asList() ?? [] {
                let key = attr.getKey().lowercased()
                if key.hasPrefix("on") || ["href", "src", "style"].contains(key) { try? element.removeAttr(key) }
            }
        }
        return try? math.outerHtml()
    }
}
private final class MathBundleMarker: NSObject {}
