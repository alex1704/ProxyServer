//
//  File.swift
//  
//
//  Created by Alex Kostenko on 18.07.2022.
//

import Foundation
import NIO
import NIOHTTP1
import Logging
import Combine

public struct Request {
    public let method: String
    public let uri: String
}

public final class ProxyServer {
    public init() {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        serverBootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socket(SOL_SOCKET, SO_REUSEADDR), value: 1)
            .childChannelOption(ChannelOptions.socket(SOL_SOCKET, SO_REUSEADDR), value: 1)
            .childChannelInitializer { [weak self] channel in
                channel.pipeline.addHandler(ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes)))
                    .flatMap { channel.pipeline.addHandler(HTTPResponseEncoder()) }
                    .flatMap { channel.pipeline.addHandler( ConnectionHandler(requestSubject: self?.requestSubject)) }
            }
    }

    public func start(ipAddress: String, port: Int) async throws -> Void {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                serverBootstrap?.bind(to: try SocketAddress(ipAddress: ipAddress, port: port)).whenComplete { [weak self] result in
                    let logger = Logger(label: "ProxyServer")
                    switch result {
                    case .success(let channel):
                        self?.channel = channel
                        logger.info("Listening on \(String(describing: channel.localAddress))")
                        continuation.resume()
                    case .failure(let error):
                        logger.error("Failed to bind \(ipAddress):\(port), \(error)")
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    public func stop() async throws -> Void {
        return try await withCheckedThrowingContinuation { continuation in
            channel?.close().whenComplete({ [weak self] result in
                switch result {
                case .success:
                    self?.channel = nil
                    continuation.resume()
                case .failure(let error): continuation.resume(throwing: error)
                }
            })
        }
    }

    private let requestSubject = PassthroughSubject<Request, Never>()
    private var serverBootstrap: ServerBootstrap?
    private weak var channel: Channel?
}

public extension ProxyServer {
    var requestPublisher: AnyPublisher<Request, Never> {
        requestSubject.eraseToAnyPublisher()
    }
}
