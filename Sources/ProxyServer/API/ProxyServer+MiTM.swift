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

    public struct Payload {
        public var headers = [String: String]()
        public var body = ""
    }

    public struct Request {
        public var url: String
        public var method: String
        public var payload: Payload
    }

    public struct Response {
        public var statusCode: UInt
        public var payload: Payload
    }
}
