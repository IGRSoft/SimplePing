#if os(iOS) || os(watchOS) || os(tvOS)
import UIKit
#elseif os(macOS)
import Cocoa
#endif
import PlaygroundSupport

PlaygroundPage.current.needsIndefiniteExecution = true 

import SimplePing

class Main: NSObject {
    var forceIPv4 = false
    var forceIPv6 = false
    var pinger: Ping?
    var timer: Timer?
    
    override init() { }
    
    func runWithHostName(_ hostName: String) {
        let pinger = SimplePing(hostName: hostName)
        self.pinger = pinger
        
        if self.forceIPv4 && !self.forceIPv6 {
            pinger.addressStyle = .icmpv4
        } else if self.forceIPv6 && !self.forceIPv4 {
            pinger.addressStyle = .icmpv6
        } else {
            pinger.addressStyle = .any
        }
        
        pinger.delegate = self
        pinger.start()
        
        repeat {
            RunLoop.current.run(mode: .default, before: Date.distantFuture)
        } while self.pinger != nil
    }
    
    @objc func sendPing() {
        self.pinger?.sendPing(nil)
    }
}

extension Main: SimplePingDelegate {
    func pinger(_ pinger: Ping, didStartWithAddress address: String) {
        print("start \(address)")
        self.sendPing()
    }
    
    func pinger(_ pinger: Ping, didStartWithAddress address: Data) {
        print("pinging \(address.hostString())")
        self.sendPing()
        self.timer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(sendPing), userInfo: nil, repeats: true)
    }
    
    func pinger(_ pinger: Ping, didFailWithError error: Error) {
        print("failed: \(error.localizedDescription)")
        
        self.timer?.invalidate()
        self.timer = nil
        self.pinger = nil
    }
    
    func pinger(_ pinger: Ping, didSendPacket packet: Data, sequence: UInt16) {
        print("#\(sequence) sent, size \(packet.count)")
    }
    
    func pinger(_ pinger: Ping, didFailToSendPacket packet: Data, sequence: UInt16, error: Error) {
        print("#\(sequence) send failed: \(error.localizedDescription)")
    }
    
    func pinger(_ pinger: Ping, didReceivePingResponsePacket packet: Data, sequence: UInt16, from: String) {
        print("#\(sequence) received from \(from), size \(packet.count)")
    }
    
    func pinger(_ pinger: Ping, didReceiveUnexpectedPacket packet: Data, from: String) {
        print("unexpected packet from \(from), size \(packet.count)")
    }
}

func printUsage() {
    print("usage: %s [-4] [-6] host\n", getprogname() as Any)
}

let main = Main()
main.forceIPv4 = true
//main.forceIPv6 = true
main.runWithHostName("apple.com")
