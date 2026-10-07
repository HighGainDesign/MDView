import Foundation
import SwiftSoup

enum HTMLAdapter {
    private static let tags: Set<String> = [
        "html", "head", "body", "p", "h1", "h2", "h3", "h4", "h5", "h6", "a", "blockquote",
        "ul", "ol", "li", "dl", "dt", "dd", "pre", "code", "hr", "br", "table", "thead", "tbody",
        "tfoot", "tr", "th", "td", "caption", "details", "summary", "del", "ins", "sup", "sub",
        "strong", "em", "s", "mark", "figure", "figcaption", "span", "div", "section", "input", "img", "abbr"
    ]
    private static let attributes: Set<String> = [
        "href", "src", "alt", "title", "id", "class", "rowspan", "colspan", "align", "aria-label",
        "aria-hidden", "role", "type", "disabled", "checked", "start", "reversed", "scope", "style"
    ]

    static func prepare(_ document: Document, loadRemoteImages: Bool = false) throws {
        var ids: [String: Int] = [:]
        for element in try document.getAllElements().array() {
            let tag = element.tagName()
            if tag == "#root" { continue }
            if ["script", "style", "iframe", "object", "embed", "link", "meta"].contains(tag) {
                try element.remove()
                continue
            }
            guard tags.contains(tag) else { try element.unwrap(); continue }
            for attribute in element.getAttributes()?.asList() ?? [] {
                if !attributes.contains(attribute.getKey()) { try element.removeAttr(attribute.getKey()) }
            }
            if element.hasAttr("style") {
                let style = try element.attr("style").replacingOccurrences(of: " ", with: "").lowercased()
                if !["text-align:left", "text-align:right", "text-align:center", "text-align:left;", "text-align:right;", "text-align:center;"].contains(style) {
                    try element.removeAttr("style")
                }
            }
            if element.hasAttr("id") {
                let original = try element.attr("id")
                let count = ids[original, default: 0]
                ids[original] = count + 1
                try element.attr("id", "mdview-" + original + (count == 0 ? "" : "-\(count)"))
            }
            if element.hasAttr("href") {
                let href = try element.attr("href")
                if href.hasPrefix("#") { try element.attr("href", "#mdview-" + String(href.dropFirst())) }
                else if let scheme = URLComponents(string: href)?.scheme,
                        !["http", "https", "mailto"].contains(scheme.lowercased()) { try element.removeAttr("href") }
            }
            if tag == "input" {
                guard try element.attr("type") == "checkbox" else { try element.remove(); continue }
                try element.attr("disabled", "")
                try element.attr("aria-label", element.hasAttr("checked") ? "Completed task" : "Incomplete task")
            }
            if tag == "img" {
                let src = try element.attr("src")
                if !src.isEmpty, URLComponents(string: src)?.scheme == nil, !src.hasPrefix("/"),
                   let encoded = src.addingPercentEncoding(withAllowedCharacters: .alphanumerics) {
                    try element.attr("src", "mdview-resource://local/" + encoded)
                } else if loadRemoteImages, let remote = URLComponents(string: src),
                          remote.scheme?.lowercased() == "https", remote.host?.isEmpty == false,
                          remote.user == nil, remote.password == nil {
                    try element.attr("referrerpolicy", "no-referrer")
                } else if !src.lowercased().hasPrefix("data:image/png;base64,") &&
                            !src.lowercased().hasPrefix("data:image/jpeg;base64,") &&
                            !src.lowercased().hasPrefix("data:image/gif;base64,") &&
                            !src.lowercased().hasPrefix("data:image/webp;base64,") {
                    try element.removeAttr("src")
                }
            }
        }
        for table in try document.select("table").array() {
            try table.wrap("<div class=\"table-scroll\"></div>")
        }
    }
}
