//
//  File.swift
//  
//
//  Created by Alex Kostenko on 04.08.2022.
//

import Foundation

struct RequestInfoNotificationEmitter {
    let info: ProxyServer.MiTM.RequestInfo
    let sender: AnyObject

    func emit() {
        let notification = Notification(
            name: ProxyServer.Notification.DidEmitRequestInfo,
            object: sender,
            userInfo: [ProxyServer.Notification.requestInfoKey : info]
        )
        NotificationCenter.default.post(notification)
    }
}
