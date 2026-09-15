//
//  Data+Bytes.swift
//  SimplePing
//
//  Created by Vitalii Parovishnyk on 15.09.2026.
//

import Foundation

extension Data {
    public func to<T>(_ type: T.Type) -> T {
        self.withUnsafeBytes { (body: UnsafeRawBufferPointer) in
            body.baseAddress!.assumingMemoryBound(to: T.self).pointee
        }
    }
    
    public var unsafeBytes: UnsafeRawPointer {
        self.withUnsafeBytes { (body: UnsafeRawBufferPointer) in
            let bufferPointer = body.baseAddress!.assumingMemoryBound(to: UInt8.self)
            return UnsafeRawPointer(bufferPointer)
        }
    }
}
