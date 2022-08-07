//
//  File.swift
//  
//
//  Created by Alex Kostenko on 04.08.2022.
//

import Foundation

extension ProxyServer {
    public enum MiTM {}
}

extension ProxyServer.MiTM {
    public typealias RequestInfo = (request: Request, response: Response)

    public class Payload {
        public var headers = [String: String]()
        public var bodyContentURL: URL?
    }

    public class Request {
        public var url: String
        public var method: String
        public var payload: Payload

        public init(url: String, method: String, payload: Payload) {
            self.url = url
            self.method = method
            self.payload = payload
        }
    }

    public class Response {
        public var statusCode: UInt
        public var payload: Payload

        public init(statusCode: UInt, payload: Payload) {
            self.statusCode = statusCode
            self.payload = payload
        }
    }
}
