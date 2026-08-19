//
//  MastodonRequestBuilder.swift
//  moro
//
//  Utility for creating URLRequests with base URL + endpoints.
//

import Foundation

struct MultipartFormPart {
    let fieldName: String
    let data: Data
    let fileName: String?
    let mimeType: String?

    init(fieldName: String, value: String) {
        self.fieldName = fieldName
        self.data = Data(value.utf8)
        self.fileName = nil
        self.mimeType = nil
    }

    init(fieldName: String, data: Data, fileName: String, mimeType: String) {
        self.fieldName = fieldName
        self.data = data
        self.fileName = fileName
        self.mimeType = mimeType
    }
}

struct MastodonRequestBuilder {
    let baseURL: URL

    func makeRequest(
        for endpoint: MastodonEndpoint,
        body: Encodable? = nil,
        formData: [String: String]? = nil,
        multipartData: (data: Data, fieldName: String, fileName: String, mimeType: String)? = nil,
        multipartParts: [MultipartFormPart]? = nil
    ) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.path = endpoint.path
        components.queryItems = endpoint.queryItems

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let hasMultipartParts = !(multipartParts?.isEmpty ?? true)
        if multipartData != nil || hasMultipartParts {
            let boundary = UUID().uuidString
            var encodedParts: [MultipartFormPart] = multipartParts ?? []

            if let multipartData {
                encodedParts.append(
                    MultipartFormPart(
                        fieldName: multipartData.fieldName,
                        data: multipartData.data,
                        fileName: multipartData.fileName,
                        mimeType: multipartData.mimeType
                    )
                )
            }

            if let formData {
                for (key, value) in formData.sorted(by: { $0.key < $1.key }) {
                    encodedParts.append(MultipartFormPart(fieldName: key, value: value))
                }
            }

            request.httpBody = encodeMultipartBody(parts: encodedParts, boundary: boundary)
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        } else if let formData {
            // Form-encoded body (for OAuth)
            let formString = formData.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
                .joined(separator: "&")
            request.httpBody = formString.data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        } else if let body {
            // JSON body
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private func encodeMultipartBody(parts: [MultipartFormPart], boundary: String) -> Data {
        var body = Data()

        for part in parts {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            if let fileName = part.fileName, let mimeType = part.mimeType {
                body.append(
                    "Content-Disposition: form-data; name=\"\(part.fieldName)\"; filename=\"\(fileName)\"\r\n"
                        .data(using: .utf8)!
                )
                body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
                body.append(part.data)
                body.append("\r\n".data(using: .utf8)!)
            } else {
                body.append(
                    "Content-Disposition: form-data; name=\"\(part.fieldName)\"\r\n\r\n".data(
                        using: .utf8)!
                )
                body.append(part.data)
                body.append("\r\n".data(using: .utf8)!)
            }
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}
