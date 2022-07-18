//
//  File.swift
//  
//
//  Created by Alex Kostenko on 17.07.2022.
//

import Foundation
import NIO
import NIOHTTP1
import Logging


final class HTTPChannelHandler<ChannelHandler: ChannelDuplexHandler & RemovableChannelHandler> where ChannelHandler.InboundIn == HTTPServerRequestPart, ChannelHandler.InboundOut == HTTPClientRequestPart, ChannelHandler.OutboundIn == HTTPClientResponsePart, ChannelHandler.OutboundOut == HTTPServerResponsePart {
    init(channelHandler: ChannelHandler, logger: Logger = .init(label: "http")) {
        self.state = .idle
        self.logger = logger
        self.channelHandler = channelHandler
    }

    private var state: State
    private var logger: Logger
    private let channelHandler: ChannelHandler
    private var bufferedBody: ByteBuffer?
    private var bufferedEnd: HTTPHeaders?
}

private extension HTTPChannelHandler {
    enum State {
        case idle
        case pendingConnection(head: HTTPRequestHead)
        case connected
    }
}

extension HTTPChannelHandler: ChannelCallbackHandler {}

extension HTTPChannelHandler {
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let unwrapped = channelHandler.unwrapInboundIn(data)
        switch state {
        case .idle:
            handleInitialMessage(context: context, data: unwrapped)
        case .pendingConnection(_), .connected:
            procedeChannelRead(of: unwrapped, in: context)
        }
    }
}

extension HTTPChannelHandler {
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        switch channelHandler.unwrapOutboundIn(data) {
        case .head(let head):
            context.write(channelHandler.wrapOutboundOut(.head(head)), promise: nil)
        case .body(let body):
            _ = context.write(channelHandler.wrapOutboundOut(.body(.byteBuffer(body))))
        case .end(let trailers):
            context.write(channelHandler.wrapOutboundOut(.end(trailers)), promise: nil)
        }
    }
}

extension HTTPChannelHandler: RemovableChannelHandler {
    func removeHandler(context: ChannelHandlerContext, removalToken: ChannelHandlerContext.RemovalToken) {
        removeHandler(context: context)
        context.leavePipeline(removalToken: removalToken)
    }

    private func removeHandler(context: ChannelHandlerContext) {
        if case let .pendingConnection(head) = self.state {
            self.state = .connected

            context.fireChannelRead(channelHandler.wrapInboundOut(.head(head)))

            if let bufferedBody = self.bufferedBody {
                context.fireChannelRead(channelHandler.wrapInboundOut(.body(.byteBuffer(bufferedBody))))
                self.bufferedBody = nil
            }

            if let bufferedEnd = self.bufferedEnd {
                context.fireChannelRead(channelHandler.wrapInboundOut(.end(bufferedEnd)))
                self.bufferedEnd = nil
            }

            context.fireChannelReadComplete()
        }
    }
}

private extension HTTPChannelHandler {
    private func connectTo(host: String, port: Int, context: ChannelHandlerContext) {
        self.logger.info("Connecting to \(host):\(port)")
        let channelFuture = ClientBootstrap(group: context.eventLoop)
            .channelInitializer { channel in
                channel.pipeline.addHandler(HTTPRequestEncoder()).flatMap {
                    channel.pipeline.addHandler(ByteToMessageHandler(HTTPResponseDecoder(leftOverBytesStrategy: .forwardBytes)))
                }
            }
            .connect(host: host, port: port)

        channelFuture.whenSuccess { channel in
            self.logger.info("Connected to \(String(describing: channel.remoteAddress?.ipAddress ?? "unknown")); state \(self.state)")
            self.glue(channel, context: context)
        }
        channelFuture.whenFailure { error in
            self.connectFailed(error: error, context: context)
        }
    }

    private func connectFailed(error: Error, context: ChannelHandlerContext) {
        self.logger.error("Connect failed: \(error)")
        if case .idle = state {
            httpErrorAndClose(context: context)
        }
        context.close(promise: nil)
        context.fireErrorCaught(error)
    }

    private func glue(_ peerChannel: Channel, context: ChannelHandlerContext) {
        // Now we need to glue our channel and the peer channel together.
        let (localGlue, peerGlue) = GlueHandler.matchedPair()
        context.channel.pipeline.addHandler(localGlue).and(peerChannel.pipeline.addHandler(peerGlue)).whenComplete { result in
            switch result {
            case .success(_):
                self.removeHandler(context: context)
            case .failure(_):
                // Close connected peer channel before closing our channel.
                peerChannel.close(mode: .all, promise: nil)
                context.close(promise: nil)
            }
        }
    }
}

// Helpers
private extension HTTPChannelHandler {
    func handleInitialMessage(context: ChannelHandlerContext, data: ChannelHandler.InboundIn) {
        guard case .head(var head) = data else {
            self.logger.error("Invalid HTTP message type \(data)")
            self.httpErrorAndClose(context: context)
            return
        }

        guard let url = URL(string: head.uri),
              url.scheme == "http",
              let host = head.headers.first(where: { $0.name.lowercased() == "host" })?.value,
              host == url.host
        else {
            httpErrorAndClose(context: context)
            return
        }

        if let query = url.query {
            head.uri = "\(url.path)?\(query)"
        } else {
            head.uri = url.path
        }

        state = .pendingConnection(head: head)
        connectTo(host: host, port: url.port ?? 80, context: context)
    }

    func procedeChannelRead(
        of request: HTTPServerRequestPart,
        in context: ChannelHandlerContext
    ) {
        switch request {
        case .body(let buffer):
            switch state {
            case .connected:
                context.fireChannelRead(channelHandler.wrapInboundOut(.body(.byteBuffer(buffer))))
            case .pendingConnection(_):
                self.bufferedBody = buffer
            default:
                break
            }

        case .end(let headers):
            switch state {
            case .connected:
                context.fireChannelRead(channelHandler.wrapInboundOut(.end(headers)))
            case .pendingConnection(_):
                self.bufferedEnd = headers
            default:
                break
            }

        case .head(_):
            logger.debug("invalid state \(state) in procedeChannelRead")
            break
        }
    }

    private func httpErrorAndClose(context: ChannelHandlerContext) {
        let headers = HTTPHeaders([("Content-Length", "0"), ("Connection", "close")])
        let head = HTTPResponseHead(version: .init(major: 1, minor: 1), status: .badRequest, headers: headers)
        context.write(channelHandler.wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(channelHandler.wrapOutboundOut(.end(nil))).whenComplete { (_: Result<Void, Error>) in
            context.close(mode: .output, promise: nil)
        }
    }
}
