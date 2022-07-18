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

protocol ChannelCallbackHandler {
    func channelRead(context: ChannelHandlerContext, data: NIOAny)
    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?)
    func removeHandler(context: ChannelHandlerContext, removalToken: ChannelHandlerContext.RemovalToken)
}

extension ChannelCallbackHandler {
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.fireChannelRead(data)
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        context.write(data, promise: promise)
    }
    public func removeHandler(context: ChannelHandlerContext, removalToken: ChannelHandlerContext.RemovalToken) {
        context.leavePipeline(removalToken: removalToken)
    }
}

final class ConnectionHandler {
    init(logger: Logger = .init(label: "ConnectionHandler")) {
        self.logger = logger
    }

    private var logger: Logger
    private var callBackHandler: ChannelCallbackHandler?
}

extension ConnectionHandler: ChannelDuplexHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias InboundOut = HTTPClientRequestPart
    typealias OutboundIn = HTTPClientResponsePart
    typealias OutboundOut = HTTPServerResponsePart

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        if callBackHandler == nil {
            do {
                try setupCallBackHandler(context: context, data: self.unwrapInboundIn(data))
            } catch {
                httpErrorAndClose(context: context)
                return
            }
        }

        callBackHandler?.channelRead(context: context, data: data)
    }

    func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        callBackHandler?.write(context: context, data: data, promise: promise)
    }

    func handlerAdded(context: ChannelHandlerContext) {
        // Add logger metadata.
        let description = "\(context.channel.localAddress?.ipAddress ?? "unknown") -> \(context.channel.remoteAddress?.ipAddress ?? "unknown") ::: \(ObjectIdentifier(context.channel))"
        self.logger[metadataKey: "desc"] = "\(description)"
    }
}

extension ConnectionHandler: RemovableChannelHandler {
    func removeHandler(context: ChannelHandlerContext, removalToken: ChannelHandlerContext.RemovalToken) {
        callBackHandler?.removeHandler(context: context, removalToken: removalToken)
    }
}

private extension ConnectionHandler {
    private func isTLSConnection(context: ChannelHandlerContext, data: InboundIn) throws -> Bool  {
        guard case .head(let head) = data else {
            throw ConnectProxyError.invalidHTTPMessage
        }

        self.logger.info(">> \(head.method) \(head.uri) \(head.version)")

        return head.method == .CONNECT
    }

    private func setupCallBackHandler(context: ChannelHandlerContext, data: InboundIn) throws {
        if try isTLSConnection(context: context, data: data) {
            // TODO: weak dependency?
            callBackHandler = TLSChannelHandler(channelHandler: self)
        } else {
            callBackHandler = HTTPChannelHandler(channelHandler: self)
        }
    }

    private func httpErrorAndClose(context: ChannelHandlerContext) {
        let headers = HTTPHeaders([("Content-Length", "0"), ("Connection", "close")])
        let head = HTTPResponseHead(version: .init(major: 1, minor: 1), status: .badRequest, headers: headers)
        context.write(self.wrapOutboundOut(.head(head)), promise: nil)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil))).whenComplete { (_: Result<Void, Error>) in
            context.close(mode: .output, promise: nil)
        }
    }
}