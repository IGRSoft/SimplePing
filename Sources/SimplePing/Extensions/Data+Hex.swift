//
//  Data+Hex.swift
//  SimplePing
//
//  Created by Vitalii Parovishnyk on 15.09.2026.
//

import Foundation

public extension Data {
    var hex: String {
        return self.map { String(format: "%02hhx", $0) }.joined()
    }
}
