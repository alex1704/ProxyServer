//
//  File.swift
//  
//
//  Created by Alex Kostenko on 06.08.2022.
//

import Foundation

final class HTTPBodyCache {
    let requestBodyURL: URL
    let responseBodyURL: URL
    var hasRequestData: Bool { FileManager.default.fileExists(atPath: requestBodyURL.path) }
    var hasResponseData: Bool { FileManager.default.fileExists(atPath: responseBodyURL.path) }

    public init(cacheFolderURL: URL) throws {
        let name = UUID().uuidString
        let requestBodyURL = cacheFolderURL.appendingPathComponent("req-\(name)")
        let responseBodyURL = cacheFolderURL.appendingPathComponent("resp-\(name)")
        self.requestBodyURL = requestBodyURL
        self.responseBodyURL = responseBodyURL
        guard let requestBodyStream = OutputStream(url: requestBodyURL, append: true),
              let responseBodyStream = OutputStream(url: responseBodyURL, append: true)
        else {
            throw CacheError.unableToOpenWritingStreamInCacheFolderURL
        }

        self.requestBodyStream = requestBodyStream
        self.responseBodyStream = responseBodyStream
    }

    deinit {
        requestBodyStream.close()
        responseBodyStream.close()
    }

    public func appendRequestBody(_ data: inout Data) {
        openStreamIfNeeded(requestBodyStream)
        _ = data.withUnsafeBytes { pointer in
            requestBodyStream.write(pointer, maxLength: data.count)
        }
    }

    public func appendResponseBody(_ data: inout Data) {
        openStreamIfNeeded(responseBodyStream)
        _ = data.withUnsafeBytes { pointer in
            responseBodyStream.write(pointer, maxLength: data.count)
        }
    }

    private func openStreamIfNeeded(_ stream: OutputStream) {
        if case .notOpen = stream.streamStatus  {
            stream.open()
        }
    }

    private var requestBodyStream: OutputStream
    private var responseBodyStream: OutputStream
}

extension HTTPBodyCache {
    public enum CacheError: Error {
        case unableToOpenWritingStreamInCacheFolderURL
    }
}
