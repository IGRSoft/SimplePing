//
//  IPHeader.swift
//  SimplePing
//
//  Created by Vitalii Parovishnyk on 15.09.2026.
//

import Foundation

public struct IPHeader {
    public typealias IPAddress = (UInt8, UInt8, UInt8, UInt8)
    
    public var versionAndHeaderLength: UInt8
    public var differentiatedServices: UInt8
    public var totalLength: UInt16
    public var identification: UInt16
    public var flagsAndFragmentOffset: UInt16
    public var timeToLive: UInt8
    public var `protocol`: UInt8
    public var headerChecksum: UInt16
    public var sourceAddress: IPAddress
    public var destinationAddress: IPAddress
}


public struct ICMPHeader {
    public var type: UInt8      /* type of message*/
    public var code: UInt8      /* type sub code */
    public var checkSum: UInt16 /* ones complement cksum of struct */
    public var identifier: UInt16
    public var sequenceNumber: UInt16
}

public struct ICMPv4Type {
    public static let EchoReply: UInt8   = 0    // code is always 0
    public static let EchoRequest: UInt8 = 8    // code is always 0
}

public struct ICMPv6Type {
    public static let EchoReply: UInt8   = 129  // code is always 0
    public static let EchoRequest: UInt8 = 128  // code is always 0
}
