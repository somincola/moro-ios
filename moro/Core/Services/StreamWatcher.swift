//
//  StreamWatcher.swift
//  moro
//
//  WebSocket-based real-time streaming service for Mastodon updates.
//  Handles timeline updates, notifications, and direct messages.
//

import Combine
import Foundation
import OSLog

/// Observes real-time streaming events from Mastodon via WebSocket
@MainActor
@Observable
final class StreamWatcher {

    // MARK: - Stream Types

    enum Stream: String, Sendable {
        case federated = "public"
        case local = "public:local"
        case user = "user"
        case direct = "direct"
        case hashtag = "hashtag"
        case list = "list"
    }

    // MARK: - Connection State

    enum ConnectionState: Sendable, Equatable {
        case disconnected
        case connecting
        case connected
        case reconnecting(attempt: Int)
        case failed(Error)

        static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected),
                (.connecting, .connecting),
                (.connected, .connected):
                return true
            case (.reconnecting(let a), .reconnecting(let b)):
                return a == b
            case (.failed, .failed):
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Properties

    static let shared = StreamWatcher()

    /// Current connection state
    private(set) var connectionState: ConnectionState = .disconnected

    /// The most recent event (consumers observe this; we don't retain history).
    private(set) var latestEvent: StreamEvent?

    /// Lossless in-process event channel. Consumers that must handle every edit/delete/update
    /// subscribe here instead of observing `latestEvent`, whose value semantics may coalesce.
    let events = PassthroughSubject<StreamEvent, Never>()
    let sourcedEvents = PassthroughSubject<SourcedStreamEvent, Never>()

    func matchesCredentials(baseURL: URL, accessToken: String?) -> Bool {
        guard let accessToken else { return false }
        return self.baseURL == baseURL && self.accessToken == accessToken
    }

    /// Whether the watcher is actively watching
    var isWatching: Bool {
        task != nil && connectionState == .connected
    }

    /// Whether connection lifecycle is active (connecting/connected/reconnecting)
    var hasActiveConnection: Bool {
        switch connectionState {
        case .connecting, .connected, .reconnecting:
            return true
        case .disconnected, .failed:
            return false
        }
    }

    // MARK: - Private Properties

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var watchedStreams: Set<Stream> = []
    private var baseURL: URL?
    private var accessToken: String?

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        // NOTE: Do NOT use keyDecodingStrategy = .convertFromSnakeCase here!
        // The Status and Account models already define CodingKeys with explicit snake_case mappings.
        // Using both causes a conflict where the decoder looks for wrong keys.

        // Custom date decoding to handle both ISO8601 formats (with and without milliseconds)
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            if let date = DateFormatting.parseISO8601(dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date string: \(dateString)"
            )
        }
        return decoder
    }()

    private let encoder = JSONEncoder()
    private let logger = Logger(subsystem: "com.moro", category: "StreamWatcher")

    // Reconnection configuration
    private var reconnectAttempts = 0
    private let maxReconnectAttempts: Int
    private let baseReconnectDelay: TimeInterval
    private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var networkSubscription: AnyCancellable?

    // Keep-alive ping
    private var pingTask: Task<Void, Never>?
    private let pingInterval: TimeInterval = 30.0
    private let initialSubscriptionDelayNanoseconds: UInt64 = 180_000_000
    private static let enableVerboseStreamLogs: Bool = {
        #if DEBUG
            ProcessInfo.processInfo.arguments.contains("-moro.stream.logs")
        #else
            false
        #endif
    }()

    // MARK: - Initialization

    init(
        maxReconnectAttempts: Int = 5,
        baseReconnectDelay: TimeInterval = 2.0,
        observesNetworkRecovery: Bool = true
    ) {
        self.maxReconnectAttempts = maxReconnectAttempts
        self.baseReconnectDelay = baseReconnectDelay
        guard observesNetworkRecovery else { return }
        // Backoff gives up after ~1 minute offline. When the path comes back, revive the
        // socket right away instead of waiting for the next screen to ask for a stream.
        networkSubscription = NetworkMonitor.shared.$isConnected
            .removeDuplicates()
            .dropFirst()
            .filter { $0 }
            .sink { [weak self] _ in
                self?.ensureConnected(skipBackoff: true)
            }
    }

    /// Brings a watched socket back after it gave up (`.failed`) or was dropped.
    ///
    /// Cheap and idempotent: a connected or connecting socket is left alone. A socket waiting
    /// out its backoff is reconnected now only with `skipBackoff` (foreground, network back).
    func ensureConnected(skipBackoff: Bool = false) {
        guard !watchedStreams.isEmpty, baseURL != nil, accessToken != nil else { return }
        switch connectionState {
        case .connected, .connecting:
            return
        case .reconnecting:
            guard skipBackoff else { return }
        case .disconnected, .failed:
            break
        }
        reconnectAttempts = 0
        connect()
    }

    // MARK: - Public Methods

    /// Configure the stream watcher with server credentials
    /// - Parameters:
    ///   - baseURL: The Mastodon instance URL (will be converted to wss://)
    ///   - accessToken: OAuth access token for authentication
    func configure(baseURL: URL, accessToken: String) {
        // Idempotent: identical credentials should not reset socket state.
        guard self.baseURL != baseURL || self.accessToken != accessToken else {
            return
        }

        self.baseURL = baseURL
        self.accessToken = accessToken

        // Credentials changed while active: reconnect with existing watch list.
        if hasActiveConnection || reconnectTask != nil {
            disconnect(clearWatchedStreams: false)
            if !watchedStreams.isEmpty {
                connect()
            }
        } else if !watchedStreams.isEmpty {
            connect()
        }
    }

    /// Start watching specified streams
    /// - Parameter streams: Set of streams to subscribe to
    func watch(streams: Set<Stream>) {
        let previousStreams = watchedStreams

        guard !streams.isEmpty else {
            watchedStreams.removeAll()
            disconnect(clearWatchedStreams: false)
            reconnectAttempts = 0
            verboseInfo("Stopped stream watching because stream list is empty")
            return
        }

        watchedStreams = streams

        switch connectionState {
        case .connected:
            guard task != nil else {
                connect()
                return
            }
            syncSubscriptions(from: previousStreams, to: streams)

        case .connecting, .reconnecting:
            // Keep desired streams updated and let in-flight connection finish.
            break

        case .disconnected, .failed:
            connect()
        }
    }

    /// Add a stream to the current watch list
    /// - Parameter stream: Stream to add
    func addStream(_ stream: Stream) {
        let inserted = watchedStreams.insert(stream).inserted
        guard inserted else {
            // Already wanted: asking again means "make sure it is live". Without this a socket
            // that exhausted its retries stayed `.failed` until the app restarted.
            ensureConnected()
            return
        }

        switch connectionState {
        case .connected:
            subscribe(to: stream)
        case .disconnected, .failed:
            connect()
        case .connecting, .reconnecting:
            break
        }
    }

    /// Replace one stream with another without tearing down the socket.
    /// Useful for timeline tab switching where remove+add may create a transient empty set.
    func replaceStream(_ oldStream: Stream, with newStream: Stream) {
        guard oldStream != newStream else { return }

        let removedOld = watchedStreams.remove(oldStream) != nil
        let insertedNew = watchedStreams.insert(newStream).inserted

        guard removedOld || insertedNew else { return }

        switch connectionState {
        case .connected:
            if insertedNew {
                subscribe(to: newStream)
            }
            if removedOld {
                unsubscribe(from: oldStream)
            }
        case .disconnected, .failed:
            if !watchedStreams.isEmpty {
                connect()
            }
        case .connecting, .reconnecting:
            break
        }
    }

    /// Remove a stream from the current watch list
    /// - Parameter stream: Stream to remove
    func removeStream(_ stream: Stream) {
        guard watchedStreams.remove(stream) != nil else { return }

        if connectionState == .connected {
            unsubscribe(from: stream)
        }

        if watchedStreams.isEmpty {
            disconnect(clearWatchedStreams: false)
            reconnectAttempts = 0
        }
    }

    /// Stop watching all streams and disconnect
    func stopWatching() {
        disconnect(clearWatchedStreams: true)
        reconnectAttempts = 0

        verboseInfo("Stopped watching streams")
    }

    /// Clear the latest event.
    func clearEvents() {
        latestEvent = nil
    }

    // MARK: - Event Emitting (for local updates)

    /// Emit a delete event locally (e.g., when user deletes their own post)
    func emitDeleteEvent(for statusId: String) {
        let event: StreamEvent = .delete(statusId: statusId)
        appendEvent(event)
    }

    /// Emit an edit event locally
    func emitEditEvent(for status: Status) {
        let event: StreamEvent = .statusUpdate(status: status)
        appendEvent(event)
    }

    /// Emit a new post event locally
    func emitPostEvent(for status: Status) {
        let event: StreamEvent = .update(status: status)
        appendEvent(event)
    }

    // MARK: - Private Methods

    private func disconnect(clearWatchedStreams: Bool) {
        reconnectTask?.cancel()
        reconnectTask = nil
        pingTask?.cancel()
        pingTask = nil

        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil

        if clearWatchedStreams {
            watchedStreams.removeAll()
        }

        connectionState = .disconnected
    }

    private func syncSubscriptions(from oldStreams: Set<Stream>, to newStreams: Set<Stream>) {
        let removedStreams = oldStreams.subtracting(newStreams)
        let addedStreams = newStreams.subtracting(oldStreams)

        for stream in addedStreams.sorted(by: { $0.rawValue < $1.rawValue }) {
            subscribe(to: stream)
        }
        for stream in removedStreams.sorted(by: { $0.rawValue < $1.rawValue }) {
            unsubscribe(from: stream)
        }
    }

    private func connect() {
        guard !watchedStreams.isEmpty else {
            verboseDebug("Connect skipped: no streams to watch")
            return
        }

        guard let baseURL = baseURL, let accessToken = accessToken else {
            logger.error("StreamWatcher not configured - missing baseURL or accessToken")
            connectionState = .failed(URLError(.badURL))
            return
        }

        // Build WebSocket URL
        guard let streamingURL = buildStreamingURL(from: baseURL) else {
            logger.error("Failed to build streaming URL")
            connectionState = .failed(URLError(.badURL))
            return
        }

        if hasActiveConnection, task != nil {
            verboseDebug("Connect skipped: socket already active")
            return
        }

        reconnectTask?.cancel()
        reconnectTask = nil
        pingTask?.cancel()
        pingTask = nil
        session?.invalidateAndCancel()

        connectionState = .connecting

        // Create WebSocket task with authentication via subprotocol
        // Use access token as subprotocol for authentication (Mastodon's method)
        let session = URLSession(configuration: .default)
        self.session = session
        let webSocketTask = session.webSocketTask(with: streamingURL, protocols: [accessToken])
        task = webSocketTask

        webSocketTask.resume()

        // Start receiving messages
        receiveMessage(from: webSocketTask)

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.initialSubscriptionDelayNanoseconds ?? 0)
            await MainActor.run {
                guard let self, self.task === webSocketTask else { return }
                guard !self.watchedStreams.isEmpty else {
                    self.disconnect(clearWatchedStreams: false)
                    self.reconnectAttempts = 0
                    return
                }

                for stream in self.watchedStreams.sorted(by: { $0.rawValue < $1.rawValue }) {
                    self.subscribe(to: stream, task: webSocketTask)
                }

                self.startPingTask(for: webSocketTask)
                self.reconnectAttempts = 0
                self.connectionState = .connected
                self.verboseInfo("Connected to streaming API at \(streamingURL.host ?? "unknown")")
            }
        }
    }

    private func buildStreamingURL(from baseURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = baseURL.host
        components.port = baseURL.port
        components.path = "/api/v1/streaming"
        return components.url
    }

    private func subscribe(to stream: Stream, task: URLSessionWebSocketTask? = nil) {
        let message = StreamMessage(type: "subscribe", stream: stream.rawValue)
        if sendMessage(message, task: task) {
            verboseDebug("Subscribed to stream: \(stream.rawValue)")
        }
    }

    private func unsubscribe(from stream: Stream, task: URLSessionWebSocketTask? = nil) {
        let message = StreamMessage(type: "unsubscribe", stream: stream.rawValue)
        if sendMessage(message, task: task) {
            verboseDebug("Unsubscribed from stream: \(stream.rawValue)")
        }
    }

    @discardableResult
    private func sendMessage(_ message: StreamMessage, task targetTask: URLSessionWebSocketTask? = nil)
        -> Bool
    {
        guard let data = try? encoder.encode(message),
            let string = String(data: data, encoding: .utf8)
        else {
            return false
        }

        guard let targetTask = targetTask ?? task else {
            return false
        }

        targetTask.send(.string(string)) { [weak self] error in
            guard let self, let error else { return }

            Task { @MainActor in
                guard self.task === targetTask else { return }
                if self.isBenignSocketError(error) {
                    self.verboseDebug("Skipped benign send error: \(error.localizedDescription)")
                } else {
                    self.logger.error("Failed to send message: \(error.localizedDescription)")
                    self.handleConnectionError(error, from: targetTask)
                }
            }
        }

        return true
    }

    private func receiveMessage(from sourceTask: URLSessionWebSocketTask) {
        sourceTask.receive { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                guard self.task === sourceTask else { return }

                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    self.receiveMessage(from: sourceTask)  // Continue receiving

                case .failure(let error):
                    self.handleConnectionError(error, from: sourceTask)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let string):
            parseEvent(from: string)
        case .data(let data):
            if let string = String(data: data, encoding: .utf8) {
                parseEvent(from: string)
            }
        @unknown default:
            break
        }
    }

    private func parseEvent(from string: String) {
        guard let data = string.data(using: .utf8) else {
            logger.error("Failed to convert event string to data")
            return
        }

        do {
            let rawEvent = try decoder.decode(RawStreamEvent.self, from: data)

            if let event = convertRawEvent(rawEvent) {
                let streams = rawEvent.stream
                    ?? (watchedStreams.count == 1 ? watchedStreams.map(\.rawValue) : [])
                sourcedEvents.send(SourcedStreamEvent(event: event, streams: streams))
                appendEvent(event)
                verboseDebug("Received stream event: \(rawEvent.event)")
            }
        } catch {
            logger.error("Failed to decode stream event: \(error.localizedDescription)")
        }
    }

    private func convertRawEvent(_ rawEvent: RawStreamEvent) -> StreamEvent? {
        // Handle delete event - payload is just the status ID string
        if rawEvent.event == "delete" {
            guard let payload = rawEvent.payload, !payload.isEmpty else {
                verboseDebug("Delete event with empty payload")
                return nil
            }
            return .delete(statusId: payload)
        }

        // For other events, payload must be valid JSON
        guard let payload = rawEvent.payload,
            !payload.isEmpty,
            let payloadData = payload.data(using: .utf8)
        else {
            verboseDebug("Event '\(rawEvent.event)' has empty or invalid payload")
            return nil
        }

        do {
            switch rawEvent.event {
            case "update":
                let status = try decoder.decode(Status.self, from: payloadData)
                return .update(status: status)

            case "status.update":
                let status = try decoder.decode(Status.self, from: payloadData)
                return .statusUpdate(status: status)

            case "notification":
                let notification = try decoder.decode(NotificationItem.self, from: payloadData)
                return .notification(notification: notification)

            case "conversation":
                let conversation = try decoder.decode(StreamConversation.self, from: payloadData)
                return .conversation(
                    conversationId: conversation.id,
                    unread: conversation.unread,
                    lastStatus: conversation.lastStatus
                )

            default:
                verboseDebug("Unknown event type: \(rawEvent.event)")
                return nil
            }
        } catch let decodingError as DecodingError {
            // Log detailed decoding error info
            switch decodingError {
            case .keyNotFound(let key, let context):
                logger.error(
                    "Failed to decode '\(rawEvent.event)': Missing key '\(key.stringValue)' at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
                )
            case .typeMismatch(let type, let context):
                logger.error(
                    "Failed to decode '\(rawEvent.event)': Type mismatch for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
                )
            case .valueNotFound(let type, let context):
                logger.error(
                    "Failed to decode '\(rawEvent.event)': Value not found for \(type) at \(context.codingPath.map(\.stringValue).joined(separator: "."))"
                )
            case .dataCorrupted(let context):
                logger.error(
                    "Failed to decode '\(rawEvent.event)': Data corrupted at \(context.codingPath.map(\.stringValue).joined(separator: ".")) - \(context.debugDescription)"
                )
            @unknown default:
                logger.error(
                    "Failed to decode '\(rawEvent.event)': \(decodingError.localizedDescription)")
            }
            // Log the full payload in segments for debugging
            logger.error("Full payload length: \(payload.count) characters")
            // Log in 500-character segments
            var start = payload.startIndex
            var segmentIndex = 0
            while start < payload.endIndex {
                let end =
                    payload.index(start, offsetBy: 500, limitedBy: payload.endIndex)
                    ?? payload.endIndex
                let segment = String(payload[start..<end])
                logger.error("Payload segment \(segmentIndex): \(segment)")
                start = end
                segmentIndex += 1
            }
            return nil
        } catch {
            logger.error("Failed to decode '\(rawEvent.event)': \(error.localizedDescription)")
            return nil
        }
    }

    private func appendEvent(_ event: StreamEvent) {
        latestEvent = event
        events.send(event)
    }

    private func handleConnectionError(
        _ error: Error,
        from sourceTask: URLSessionWebSocketTask? = nil
    ) {
        if let sourceTask, task !== sourceTask {
            verboseDebug("Ignoring stale WebSocket error from inactive task")
            return
        }

        if isBenignSocketError(error) {
            verboseDebug("WebSocket benign error: \(error.localizedDescription)")
        } else {
            logger.error("WebSocket error: \(error.localizedDescription)")
        }

        task?.cancel()
        task = nil
        pingTask?.cancel()
        pingTask = nil

        guard !watchedStreams.isEmpty else {
            connectionState = .disconnected
            reconnectAttempts = 0
            return
        }

        // Attempt reconnection
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil

        guard baseURL != nil, accessToken != nil else {
            connectionState = .failed(URLError(.badURL))
            return
        }

        guard !watchedStreams.isEmpty else {
            connectionState = .disconnected
            reconnectAttempts = 0
            return
        }

        guard reconnectAttempts < maxReconnectAttempts else {
            logger.error("Max reconnection attempts reached")
            connectionState = .failed(URLError(.cannotConnectToHost))
            return
        }

        reconnectAttempts += 1
        let attempt = reconnectAttempts
        connectionState = .reconnecting(attempt: attempt)

        // Exponential backoff
        let delay = baseReconnectDelay * pow(2.0, Double(attempt - 1))

        verboseInfo("Scheduling reconnect attempt \(attempt) in \(delay)s")

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            if !Task.isCancelled {
                await MainActor.run {
                    guard let self else { return }
                    self.reconnectTask = nil

                    guard case .reconnecting(let currentAttempt) = self.connectionState,
                        currentAttempt == attempt
                    else { return }

                    self.connect()
                }
            }
        }
    }

    private func startPingTask(for sourceTask: URLSessionWebSocketTask) {
        pingTask?.cancel()
        let pingIntervalNanoseconds = UInt64(self.pingInterval * 1_000_000_000)

        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: pingIntervalNanoseconds)

                if !Task.isCancelled {
                    await MainActor.run {
                        guard let self, self.task === sourceTask else { return }

                        sourceTask.sendPing { [weak self] error in
                            guard let self, let error else { return }

                            Task { @MainActor in
                                guard self.task === sourceTask else { return }
                                if self.isBenignSocketError(error) {
                                    self.verboseDebug("Ping benign failure: \(error.localizedDescription)")
                                } else {
                                    self.logger.warning("Ping failed: \(error.localizedDescription)")
                                    self.handleConnectionError(error, from: sourceTask)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func verboseInfo(_ message: String) {
        guard Self.enableVerboseStreamLogs else { return }
        logger.info("\(message, privacy: .public)")
    }

    private func verboseDebug(_ message: String) {
        guard Self.enableVerboseStreamLogs else { return }
        logger.debug("\(message, privacy: .public)")
    }

    private func isBenignSocketError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                return true
            default:
                break
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == 57 {
            return true
        }
        let message = nsError.localizedDescription.lowercased()
        if message.contains("socket is not connected") || message == "cancelled" {
            return true
        }
        return false
    }
}

// MARK: - Convenience Extensions

extension StreamWatcher {
    /// Quick setup for typical user session (user stream + direct messages)
    /// The account-wide streams every signed-in screen relies on: home updates and
    /// notifications (`user`) plus direct messages. The single entry point for screens,
    /// so none of them configures its own subset or replaces another screen's streams.
    func ensureUserSession(accessToken: String?) {
        guard let accessToken else { return }
        configure(baseURL: AppEnvironment.apiBaseURL, accessToken: accessToken)
        addStream(.user)
        addStream(.direct)
    }

    /// Add timeline stream based on filter
    func watchTimeline(_ filter: TimelineFilter) {
        switch filter {
        case .home:
            addStream(.user)
        case .local:
            addStream(.local)
        case .federated:
            addStream(.federated)
        default:
            break
        }
    }
}

// MARK: - Timeline Filter Extension

extension TimelineFilter {
    /// The corresponding stream type for this filter, if applicable
    var streamType: StreamWatcher.Stream? {
        switch self {
        case .home:
            return .user
        case .local:
            return .local
        case .federated:
            return .federated
        default:
            return nil
        }
    }
}
