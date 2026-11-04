import Foundation

public enum DocumentImport {
    public static let maxBytes = 64 * 1024
    public static let maxDocuments = 12

    public enum Failure: LocalizedError {
        case unsupported, tooLarge, notText, sensitive

        public var errorDescription: String? {
            switch self {
            case .unsupported: "Choose a regular Markdown or plain text file from a visible folder."
            case .tooLarge: "Choose a text file smaller than 64 KiB."
            case .notText: "Choose a nonempty UTF-8 text file."
            case .sensitive: "This file appears to contain credentials. Create a redacted copy before importing it."
            }
        }
    }

    public static func read(_ url: URL) throws -> ProjectDocument {
        let url = url.standardizedFileURL
        let name = url.lastPathComponent.lowercased()
        let sensitiveNames = ["secret", "credential", "password", "private-key", "private_key", "api-key", "api_key"]
        guard url.isFileURL,
              ["md", "markdown", "txt"].contains(url.pathExtension.lowercased()),
              !url.pathComponents.contains(where: { $0.hasPrefix(".") }),
              !sensitiveNames.contains(where: { name.contains($0) })
        else { throw Failure.unsupported }

        guard url.resolvingSymlinksInPath().pathComponents == url.pathComponents else { throw Failure.unsupported }
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true else { throw Failure.unsupported }
        guard let size = info.fileSize, size <= maxBytes else { throw Failure.tooLarge }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let data = try file.read(upToCount: maxBytes + 1) ?? Data()
        guard data.count <= maxBytes else { throw Failure.tooLarge }
        guard let text = String(data: data, encoding: .utf8), !text.contains("\0"),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw Failure.notText }

        let patterns = [
            #"-----BEGIN (?:[A-Z0-9]+ )*PRIVATE KEY-----"#,
            #"\b(?:sk-(?:ant-|proj-)?[A-Za-z0-9_-]{18,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[A-Z0-9]{16})\b"#,
            #"(?im)^\s*(?:export\s+)?(?:[A-Z_]*API_KEY|[A-Z_]*PASSWORD|[A-Z_]*SECRET|[A-Z_]*TOKEN)\s*=\s*["']?[A-Za-z0-9+/=_-]{12,}"#
        ]
        guard !patterns.contains(where: { text.range(of: $0, options: .regularExpression) != nil })
        else { throw Failure.sensitive }
        return ProjectDocument(name: url.lastPathComponent, text: text)
    }
}
