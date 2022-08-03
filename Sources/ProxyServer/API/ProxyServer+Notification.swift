//
//  File.swift
//  
//
//  Created by Alex Kostenko on 04.08.2022.
//

import Foundation

extension ProxyServer {
    public enum Notification {}
}

extension ProxyServer.Notification {
    public static let DidEmitRequestInfo = Notification.Name("ProxyServer.Notification.DidEmitRequestInfo")
    public static let requestInfoKey = "requestInfo"
}
