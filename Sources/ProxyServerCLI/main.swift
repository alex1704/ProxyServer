//===----------------------------------------------------------------------===//
//
// This source file is part of the SwiftNIO open source project
//
// Copyright (c) 2019 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of SwiftNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Dispatch
import Logging
import ProxyServer
import Combine
import Foundation

func getDocumentsDirectory() -> URL {
    // find all possible documents directories for this user
    let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)

    // just send back the first one, which ought to be the only one
    return paths[0]
}


let proxy = ProxyServer(httpBodyCacheFolderURL: getDocumentsDirectory())
let logger = Logger(label: "main")
let cancellable = NotificationCenter.default
    .publisher(for: ProxyServer.Notification.DidEmitRequestInfo)
    .sink { notification in
        let key = ProxyServer.Notification.requestInfoKey
        guard let info = notification.userInfo?[key] as? ProxyServer.MiTM.RequestInfo else {
            return
        }

        logger.info("\(info.request.url) \(info.response.statusCode) \nrequest: \(info.request.payload.bodyContentURL)\nresponse: \(info.response.payload.bodyContentURL)")
    }

Task {
    do {
        try await proxy.start(ipAddress: "127.0.0.1", port: 8080)
    } catch {
        logger.info("\(error)")
    }
}

// Run forever
dispatchMain()
