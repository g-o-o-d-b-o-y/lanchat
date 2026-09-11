import Foundation
import Network

/// Small LAN chat transport intended for foreground/local-network experiments.
/// All mutable network state lives on one serial queue.
final class LANChatEngine: @unchecked Sendable {
    static let serviceType = "_lanchat._tcp"

    /// Largest accepted wire frame (4-byte length + JSON payload). Raised for
    /// base64 attachments; the store already caps individual files at 15 MB
    /// (≈20 MB JSON).
    private static let maxFrameSize = 32 * 1024 * 1024

    enum Mode: Equatable {
        case idle
        case hosting(serviceName: String)
        case joining(serviceName: String)
        case connected
    }

    var onMessage: (@Sendable (ChatWireMessage) -> Void)?
    var onStatus: (@Sendable (String) -> Void)?
    var onMode: (@Sendable (Mode) -> Void)?
    var onError: (@Sendable (Error) -> Void)?

    private let queue = DispatchQueue(label: "LANChatEngine.network")
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var serverConnections: [ObjectIdentifier: NWConnection] = [:]
    private var receiveBuffers: [ObjectIdentifier: Data] = [:]
    private var clientConnection: NWConnection?

    private let localID: UUID
    private let displayName: String

    init(localID: UUID, displayName: String) {
        self.localID = localID
        self.displayName = displayName
    }

    func host(serviceName: String) {
        stop()
        queue.async { [weak self] in
            self?.startHost(serviceName: serviceName)
        }
    }

    func join(invitation: JoinQRCode) {
        stop()
        queue.async { [weak self] in
            self?.startBrowse(invitation: invitation)
        }
    }

    func send(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let message = ChatWireMessage(
                kind: .message,
                senderID: self.localID,
                senderName: self.displayName,
                text: trimmed
            )
            self.emit(message)

            if self.listener != nil {
                self.broadcast(message)
            } else if let connection = self.clientConnection {
                self.send(message, over: connection)
            } else {
                self.onError?(ChatError.notConnected)
            }
        }
    }

    func send(attachment: ChatWireMessage.Attachment) {
        queue.async { [weak self] in
            guard let self else { return }
            let message = ChatWireMessage(
                kind: Self.kind(for: attachment.mimeType),
                senderID: self.localID,
                senderName: self.displayName,
                text: "",
                attachment: attachment
            )
            self.emit(message)

            if self.listener != nil {
                self.broadcast(message)
            } else if let connection = self.clientConnection {
                self.send(message, over: connection)
            } else {
                self.onError?(ChatError.notConnected)
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.listener?.cancel()
            self.listener = nil
            self.browser?.cancel()
            self.browser = nil
            self.clientConnection?.cancel()
            self.clientConnection = nil
            self.serverConnections.values.forEach { $0.cancel() }
            self.serverConnections.removeAll()
            self.receiveBuffers.removeAll()
            self.onMode?(.idle)
            self.onStatus?("Not connected")
        }
    }

    private static func kind(for mimeType: String) -> ChatWireKind {
        if mimeType.hasPrefix("image/") { return .image }
        if mimeType.hasPrefix("video/") { return .video }
        return .file
    }

    private func startHost(serviceName: String) {
        do {
            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            let listener = try NWListener(using: parameters)
            listener.service = NWListener.Service(name: serviceName, type: Self.serviceType)

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    self.onMode?(.hosting(serviceName: serviceName))
                    self.onStatus?("Hosting as \(serviceName)")
                case .failed(let error):
                    self.onError?(error)
                    self.stop()
                case .cancelled:
                    break
                default:
                    self.onStatus?("Starting server…")
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }

            self.listener = listener
            listener.start(queue: queue)
        } catch {
            onError?(error)
        }
    }

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        serverConnections[id] = connection
        receiveBuffers[id] = Data()

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                self.onStatus?("Client connected")
                self.receiveLoop(connection)
                let hello = ChatWireMessage(
                    kind: .system,
                    senderID: self.localID,
                    senderName: self.displayName,
                    text: "Connected to \(self.displayName)’s chat"
                )
                self.send(hello, over: connection)
            case .failed(let error):
                self.onError?(error)
                self.remove(connection)
            case .cancelled:
                self.remove(connection)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func startBrowse(invitation: JoinQRCode) {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let descriptor = NWBrowser.Descriptor.bonjour(type: invitation.serviceType, domain: nil)
        let browser = NWBrowser(for: descriptor, using: parameters)

        browser.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.onMode?(.joining(serviceName: invitation.serviceName))
                self.onStatus?("Looking for \(invitation.serviceName)…")
            case .failed(let error):
                self.onError?(error)
                self.stop()
            default:
                break
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            for result in results {
                if case let .service(name, type, _, _) = result.endpoint,
                   name == invitation.serviceName,
                   type == invitation.serviceType {
                    self.browser?.cancel()
                    self.browser = nil
                    self.connect(to: result.endpoint)
                    return
                }
            }
        }

        self.browser = browser
        browser.start(queue: queue)
    }

    private func connect(to endpoint: NWEndpoint) {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        let connection = NWConnection(to: endpoint, using: parameters)
        clientConnection = connection
        receiveBuffers[ObjectIdentifier(connection)] = Data()

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                self.onMode?(.connected)
                self.onStatus?("Connected")
                self.receiveLoop(connection)
                let hello = ChatWireMessage(
                    kind: .hello,
                    senderID: self.localID,
                    senderName: self.displayName,
                    text: "joined"
                )
                self.send(hello, over: connection)
            case .failed(let error):
                self.onError?(error)
                self.stop()
            case .cancelled:
                self.onStatus?("Disconnected")
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func send(_ message: ChatWireMessage, over connection: NWConnection) {
        do {
            let payload = try encoder.encode(message)
            guard payload.count <= Int(UInt32.max) else { return }
            var length = UInt32(payload.count).bigEndian
            var frame = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
            frame.append(payload)
            connection.send(content: frame, completion: .contentProcessed { [weak self] error in
                if let error { self?.onError?(error) }
            })
        } catch {
            onError?(error)
        }
    }

    private func broadcast(_ message: ChatWireMessage, excluding excluded: NWConnection? = nil) {
        for connection in serverConnections.values where connection !== excluded {
            send(message, over: connection)
        }
    }

    private func receiveLoop(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }
            if let data, !data.isEmpty {
                self.consume(data, from: connection)
            }
            if let error {
                self.onError?(error)
                self.remove(connection)
                return
            }
            if isComplete {
                self.remove(connection)
                return
            }
            self.receiveLoop(connection)
        }
    }

    private func consume(_ data: Data, from connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        var buffer = receiveBuffers[id, default: Data()]
        buffer.append(data)

        while buffer.count >= 4 {
            let lengthData = buffer.prefix(4)
            let length = lengthData.withUnsafeBytes { raw -> UInt32 in
                raw.loadUnaligned(as: UInt32.self).bigEndian
            }
            let total = 4 + Int(length)
            guard length <= Self.maxFrameSize else {
                onError?(ChatError.malformedFrame)
                connection.cancel()
                return
            }
            guard buffer.count >= total else { break }

            let payload = buffer.subdata(in: 4..<total)
            buffer.removeSubrange(0..<total)

            do {
                let message = try decoder.decode(ChatWireMessage.self, from: payload)
                handle(message, from: connection)
            } catch {
                onError?(error)
            }
        }
        receiveBuffers[id] = buffer
    }

    private func handle(_ message: ChatWireMessage, from connection: NWConnection) {
        if message.kind == .hello {
            let notice = ChatWireMessage(
                kind: .system,
                senderID: message.senderID,
                senderName: message.senderName,
                text: "\(message.senderName) joined"
            )
            emit(notice)
            if listener != nil { broadcast(notice) }
            return
        }

        emit(message)
        if listener != nil { broadcast(message, excluding: connection) }
    }

    private func emit(_ message: ChatWireMessage) {
        onMessage?(message)
    }

    private func remove(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        serverConnections.removeValue(forKey: id)
        receiveBuffers.removeValue(forKey: id)
        if clientConnection === connection { clientConnection = nil }
    }
}
