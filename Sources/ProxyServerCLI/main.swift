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

let proxy = ProxyServer()
let logger = Logger(label: "main")
let cancellable = proxy.requestPublisher.sink { request in
    logger.info("\(request)")
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
