import Foundation

enum ChatWireKind: String, Codable {
    case hello
    case message
    case system
    case image
    case video
    case file
}

struct ChatWireMessage: Codable, Identifiable, Hashable {
    let id: UUID
    let kind: ChatWireKind
    let senderID: UUID
    let senderName: String
    let text: String
    let sentAt: Date
    let attachment: Attachment?

    init(
        id: UUID = UUID(),
        kind: ChatWireKind,
        senderID: UUID,
        senderName: String,
        text: String,
        sentAt: Date = Date(),
        attachment: Attachment? = nil
    ) {
        self.id = id
        self.kind = kind
        self.senderID = senderID
        self.senderName = senderName
        self.text = text
        self.sentAt = sentAt
        self.attachment = attachment
    }
}

extension ChatWireMessage {
    /// A file carried inside the JSON frame (base64). The optional
    /// `attachment` decodes as nil for messages from older peers, keeping
    /// the wire format backward compatible.
    struct Attachment: Codable, Hashable {
        /// Base64 inflates payloads ~33%, so cap raw file size well below
        /// the 32 MB frame limit.
        static let maxSizeBytes = 15 * 1024 * 1024

        let fileName: String
        let mimeType: String
        let fileSize: Int
        let dataBase64: String

        init(fileName: String, mimeType: String, fileSize: Int, dataBase64: String) {
            self.fileName = fileName
            self.mimeType = mimeType
            self.fileSize = fileSize
            self.dataBase64 = dataBase64
        }
    }
}

struct JoinQRCode: Codable {
    static let scheme = "lanchat"
    static let version = 1

    let v: Int
    let serviceName: String
    let serviceType: String

    init(serviceName: String, serviceType: String) {
        self.v = Self.version
        self.serviceName = serviceName
        self.serviceType = serviceType
    }

    func encode() throws -> String {
        let data = try JSONEncoder().encode(self)
        return Self.scheme + "://join?data=" + data.base64URLEncodedString()
    }

    static func decode(_ string: String) throws -> JoinQRCode {
        guard let components = URLComponents(string: string),
              components.scheme == scheme,
              components.host == "join",
              let payload = components.queryItems?.first(where: { $0.name == "data" })?.value,
              let data = Data(base64URLEncoded: payload) else {
            throw ChatError.invalidQRCode
        }

        let value = try JSONDecoder().decode(JoinQRCode.self, from: data)
        guard value.v == version else { throw ChatError.unsupportedProtocol }
        return value
    }
}

enum ChatError: LocalizedError {
    case invalidQRCode
    case unsupportedProtocol
    case notConnected
    case serviceNotFound
    case malformedFrame

    var errorDescription: String? {
        switch self {
        case .invalidQRCode: "This QR code is not a LAN Chat invitation."
        case .unsupportedProtocol: "This invitation uses an unsupported protocol version."
        case .notConnected: "Not connected to a chat."
        case .serviceNotFound: "The chat server could not be found on this local network."
        case .malformedFrame: "Received a malformed network frame."
        }
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var value = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - value.count % 4) % 4
        value += String(repeating: "=", count: padding)
        self.init(base64Encoded: value)
    }
}
