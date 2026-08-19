//
//  NetworkLogger.swift
//  moro
//
//  Network request and response logging for debugging.
//  Uses OSLog for efficient logging with subsystem categorization.
//

import Foundation
import OSLog

/// Central app logger with conservative defaults.
enum AppLogger {
    private static let app = Logger(subsystem: "com.moro", category: "App")
    private static let performance = Logger(subsystem: "com.moro", category: "Performance")

    #if DEBUG
        static let isDebugEnabled: Bool =
            ProcessInfo.processInfo.arguments.contains("-moro.debug.logs")
        static let isPerformanceEnabled: Bool =
            ProcessInfo.processInfo.arguments.contains("-moro.perf.logs")
    #else
        static let isDebugEnabled = false
        static let isPerformanceEnabled = false
    #endif

    static func error(_ message: String) {
        app.error("\(message, privacy: .public)")
    }

    static func warning(_ message: String) {
        app.warning("\(message, privacy: .public)")
    }

    static func debug(_ message: String, enabled: Bool = isDebugEnabled) {
        guard enabled else { return }
        app.debug("\(message, privacy: .public)")
    }

    static func performanceLog(
        _ message: String,
        enabled: Bool = isPerformanceEnabled
    ) {
        guard enabled else { return }
        performance.info("\(message, privacy: .public)")
    }
}

/// Network logging configuration
struct NetworkLoggerConfiguration: Sendable {
    /// Whether logging is enabled
    var isEnabled: Bool

    /// Log request headers
    var logHeaders: Bool

    /// Log request body
    var logRequestBody: Bool

    /// Log response body
    var logResponseBody: Bool

    /// Maximum body size to log (to avoid logging large payloads)
    var maxBodySize: Int

    /// Whether to emit verbose diagnostics (decode cost, response snippets, etc.)
    var logDiagnostics: Bool

    /// Default configuration (enabled in DEBUG, minimal logging)
    static var `default`: NetworkLoggerConfiguration {
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            let isNetworkEnabled = arguments.contains("-moro.network.logs")
            let isNetworkDiagnosticsEnabled = arguments.contains("-moro.network.diagnostics")
            let logHeaders = arguments.contains("-moro.network.headers")
            let logBody = arguments.contains("-moro.network.body")
            let logBodyFull = arguments.contains("-moro.network.body.full")

            return NetworkLoggerConfiguration(
                isEnabled: isNetworkEnabled || isNetworkDiagnosticsEnabled,
                logHeaders: logHeaders,
                logRequestBody: logBody,
                logResponseBody: logBody,
                maxBodySize: logBodyFull ? 4096 : 1024,
                logDiagnostics: isNetworkDiagnosticsEnabled
            )
        #else
            return NetworkLoggerConfiguration(
                isEnabled: false,
                logHeaders: false,
                logRequestBody: false,
                logResponseBody: false,
                maxBodySize: 0,
                logDiagnostics: false
            )
        #endif
    }

    /// Verbose configuration for debugging
    static var verbose: NetworkLoggerConfiguration {
        NetworkLoggerConfiguration(
            isEnabled: true,
            logHeaders: true,
            logRequestBody: true,
            logResponseBody: true,
            maxBodySize: 4096,
            logDiagnostics: true
        )
    }
}

/// Network logger using OSLog for efficient, system-integrated logging
final class NetworkLogger: @unchecked Sendable {
    static let shared = NetworkLogger()

    private let logger = Logger(subsystem: "com.moro", category: "Network")
    private let signpostLog = OSLog(subsystem: "com.moro", category: .pointsOfInterest)

    var configuration: NetworkLoggerConfiguration = .default

    private init() {}

    /// Create a logger with custom configuration
    init(configuration: NetworkLoggerConfiguration) {
        self.configuration = configuration
    }

    // MARK: - Request Logging

    /// Log an outgoing request
    func logRequest(_ request: URLRequest) {
        guard configuration.isEnabled else { return }

        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? "unknown"

        logger.info("➡️ [\(method)] \(url)")

        if configuration.logHeaders, let headers = request.allHTTPHeaderFields {
            let sanitizedHeaders = sanitizeHeaders(headers)
            logger.debug("Headers: \(sanitizedHeaders)")
        }

        if configuration.logRequestBody, let body = request.httpBody {
            logBody(body, prefix: "Request Body")
        }
    }

    /// Log a response
    func logResponse(_ response: HTTPURLResponse, data: Data?, error: Error? = nil) {
        logResponse(response, data: data, for: nil, duration: nil, error: error)
    }

    /// Log a response with request context and duration
    func logResponse(
        _ response: HTTPURLResponse, data: Data?, for request: URLRequest?, duration: TimeInterval?,
        error: Error? = nil
    ) {
        guard configuration.isEnabled else { return }

        let url = response.url?.absoluteString ?? request?.url?.absoluteString ?? "unknown"
        let statusCode = response.statusCode
        let durationStr = duration.map { String(format: "%.0fms", $0 * 1000) } ?? ""

        if 200..<300 ~= statusCode {
            logger.info("⬅️ [\(statusCode)] \(url) \(durationStr)")
        } else {
            logger.warning("⬅️ [\(statusCode)] \(url) \(durationStr)")
        }

        if configuration.logHeaders {
            let headers = response.allHeaderFields as? [String: String] ?? [:]
            logger.debug("Response Headers: \(headers)")
        }

        if configuration.logResponseBody, let data = data {
            logBody(data, prefix: "Response Body")
        }

        if let error = error {
            logger.error("Error: \(error.localizedDescription)")
        }
    }

    /// Log an error that occurred during request
    func logError(_ error: Error, for request: URLRequest?) {
        guard configuration.isEnabled else { return }

        let url = request?.url?.absoluteString ?? "unknown"
        let method = request?.httpMethod ?? "GET"

        logger.error("❌ [\(method)] \(url) - Error: \(error.localizedDescription)")

        if let apiError = error as? APIError {
            logger.error("API Error Type: \(String(describing: apiError))")
        }
    }

    // MARK: - Performance Tracking

    /// Begin tracking a network request for performance monitoring
    func beginRequest(_ request: URLRequest) -> OSSignpostID {
        guard configuration.isEnabled else { return .exclusive }

        let signpostID = OSSignpostID(log: signpostLog)
        let url = request.url?.absoluteString ?? "unknown"

        os_signpost(
            .begin, log: signpostLog, name: "NetworkRequest", signpostID: signpostID, "%@", url)

        return signpostID
    }

    /// End tracking a network request
    func endRequest(signpostID: OSSignpostID, statusCode: Int) {
        guard configuration.isEnabled else { return }

        os_signpost(
            .end, log: signpostLog, name: "NetworkRequest", signpostID: signpostID, "Status: %d",
            statusCode)
    }

    // MARK: - Convenience Methods

    /// Log a successful API call
    func logSuccess<T>(_ type: T.Type, endpoint: String, duration: TimeInterval? = nil) {
        guard configuration.isEnabled else { return }

        if let duration = duration {
            logger.info(
                "✅ Decoded \(String(describing: type)) from \(endpoint) in \(String(format: "%.2f", duration * 1000))ms"
            )
        } else {
            logger.info("✅ Decoded \(String(describing: type)) from \(endpoint)")
        }
    }

    /// Log a decoding failure
    func logDecodingError(_ error: DecodingError, for type: Any.Type, endpoint: String) {
        guard configuration.isEnabled else { return }

        logger.error("🔴 Failed to decode \(String(describing: type)) from \(endpoint)")

        switch error {
        case .typeMismatch(let type, let context):
            logger.error(
                "Type mismatch: expected \(String(describing: type)) at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
            )
        case .valueNotFound(let type, let context):
            logger.error(
                "Value not found: \(String(describing: type)) at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
            )
        case .keyNotFound(let key, let context):
            logger.error(
                "Key not found: '\(key.stringValue)' at \(context.codingPath.map { $0.stringValue }.joined(separator: "."))"
            )
        case .dataCorrupted(let context):
            logger.error("Data corrupted: \(context.debugDescription)")
        @unknown default:
            logger.error("Unknown decoding error")
        }
    }

    // MARK: - Private Helpers

    private func logBody(_ data: Data, prefix: String) {
        let truncated = data.count > configuration.maxBodySize
        let logData = truncated ? data.prefix(configuration.maxBodySize) : data

        if let string = String(data: logData, encoding: .utf8) {
            let suffix = truncated ? "... (truncated)" : ""
            logger.debug("\(prefix): \(string)\(suffix)")
        } else {
            logger.debug("\(prefix): <binary data, \(data.count) bytes>")
        }
    }

    private func sanitizeHeaders(_ headers: [String: String]) -> String {
        var sanitized = headers
        // Remove sensitive headers from logs
        let sensitiveKeys = ["Authorization", "Cookie", "X-Auth-Token"]
        for key in sensitiveKeys where sanitized[key] != nil {
            sanitized[key] = "[REDACTED]"
        }
        return sanitized.description
    }
}

// MARK: - URLSession Extension for Logging

extension URLSession {
    /// Perform a data task with automatic logging
    func dataWithLogging(for request: URLRequest) async throws -> (Data, URLResponse) {
        let logger = NetworkLogger.shared

        logger.logRequest(request)
        let signpostID = logger.beginRequest(request)
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let (data, response) = try await data(for: request)

            let duration = CFAbsoluteTimeGetCurrent() - startTime

            if let httpResponse = response as? HTTPURLResponse {
                logger.endRequest(signpostID: signpostID, statusCode: httpResponse.statusCode)
                logger.logResponse(httpResponse, data: data)

                #if DEBUG
                    if httpResponse.statusCode >= 400, logger.configuration.logDiagnostics {
                        AppLogger.debug(
                            "⚠️ Request failed with status \(httpResponse.statusCode) in \(String(format: "%.2f", duration * 1000))ms"
                        )
                    }
                #endif
            }

            return (data, response)
        } catch {
            logger.logError(error, for: request)
            throw error
        }
    }
}
