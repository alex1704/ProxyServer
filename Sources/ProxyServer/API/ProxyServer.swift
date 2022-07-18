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


public final class ProxyServer {
    public init() {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        serverBootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socket(SOL_SOCKET, SO_REUSEADDR), value: 1)
            .childChannelOption(ChannelOptions.socket(SOL_SOCKET, SO_REUSEADDR), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(ByteToMessageHandler(HTTPRequestDecoder(leftOverBytesStrategy: .forwardBytes)))
                    .flatMap { channel.pipeline.addHandler(HTTPResponseEncoder()) }
                    .flatMap { channel.pipeline.addHandler( ConnectionHandler()) }
            }
    }

    public func start(ipAddress: String, port: Int) {
        serverBootstrap.bind(to: try! SocketAddress(ipAddress: ipAddress, port: port)).whenComplete { [weak self] result in
            // Need to create this here for thread-safety purposes
            let logger = Logger(label: "com.apple.nio-connect-proxy.main")

            switch result {
            case .success(let channel):
                self?.channel = channel
                logger.info("Listening on \(String(describing: channel.localAddress))")
            case .failure(let error):
                logger.error("Failed to bind 127.0.0.1:8080, \(error)")
            }
        }
    }

    private let serverBootstrap: ServerBootstrap
    private var channel: Channel?
}
