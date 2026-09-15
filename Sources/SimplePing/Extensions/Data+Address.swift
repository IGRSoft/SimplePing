//
//  Data+Address.swift
//  SimplePing
//
//  Created by Vitalii Parovishnyk on 15.09.2026.
//

import Foundation

extension Data {
    
    public func srcAddress() -> String? {
        var ipPtr: IPHeader? = nil
        var msg: String?

        if (self.count) >= (MemoryLayout<IPHeader>.size + MemoryLayout<ICMPHeader>.size) {
            ipPtr = self.to(IPHeader.self)
            if let sourceAddress = ipPtr?.sourceAddress.0, let aSourceAddress = ipPtr?.sourceAddress.1, let aASourceAddress = ipPtr?.sourceAddress.2, let aAASourceAddress = ipPtr?.sourceAddress.3 {
                msg = "\(sourceAddress).\(aSourceAddress).\(aASourceAddress).\(aAASourceAddress)"
            }
        }
        
        return msg
    }
    
    public func hostString() -> String {
        let maxHostLen = UInt32(NI_MAXHOST)
        let maxPortLen = UInt32(NI_MAXSERV)
        let hostStrRef = UnsafeMutablePointer<Int8>.allocate(capacity: Int(maxHostLen))
        defer {
            hostStrRef.deallocate()
        }
        let portStrRef = UnsafeMutablePointer<Int8>.allocate(capacity: Int(maxPortLen))
        defer {
            portStrRef.deallocate()
        }
        
        var addr = self.to(sockaddr.self)
        getnameinfo(&addr,
                    socklen_t(self.count),
                    hostStrRef,
                    maxHostLen,
                    portStrRef,
                    maxPortLen,
                    NI_NUMERICHOST | NI_NUMERICSERV)
        
        let hostStr = String(cString: hostStrRef, encoding: .ascii)
        let portStr = String(cString: portStrRef, encoding: .ascii)
        let addressString = "\(hostStr ?? "nil"):\(portStr ?? "nil")"
        return addressString
    }
}
