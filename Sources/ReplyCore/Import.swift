import Foundation

public enum DocumentImport {
    public static let maxBytes = 64 * 1024
    public static let maxDocuments = 12

    public enum Failure: LocalizedError {
        case unsupported, wrongType, hidden, linked, sensitiveName, tooLarge, notText, sensitive

        public var errorDescription: String? {
            switch self {
            case .unsupported: "Choose a regular Markdown or plain text file from a visible folder."
            case .wrongType: "Choose a Markdown or plain text file (.md, .markdown or .txt)."
            case .hidden: "This file is hidden or inside a hidden folder. Copy it to a visible folder first."
            case .linked: "This file is reached through an alias or symbolic link. Choose the original file."
            case .sensitiveName: "The file name suggests it holds credentials. Rename a safe copy before importing it."
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
        guard url.isFileURL else { throw Failure.unsupported }
        guard ["md", "markdown", "txt"].contains(url.pathExtension.lowercased()) else { throw Failure.wrongType }
        guard !url.pathComponents.contains(where: { $0.hasPrefix(".") }) else { throw Failure.hidden }
        guard !sensitiveNames.contains(where: { name.contains($0) }) else { throw Failure.sensitiveName }

        guard url.resolvingSymlinksInPath().pathComponents == url.pathComponents else { throw Failure.linked }
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isSymbolicLink != true else { throw Failure.linked }
        guard info.isRegularFile == true else { throw Failure.unsupported }
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
