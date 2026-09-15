//: Playground - noun: a place where people can play

import Foundation


public protocol SimplePingDelegate: AnyObject {
    func pinger(_ pinger: Ping, didStartWithAddress address: String)
    func pinger(_ pinger: Ping, didFailWithError error: Error)
    func pinger(_ pinger: Ping, didSendPacket packet: Data, sequence: UInt16)
    func pinger(_ pinger: Ping, didFailToSendPacket packet: Data, sequence: UInt16, error: Error)
    func pinger(_ pinger: Ping, didReceivePingResponsePacket packet: Data, sequence: UInt16, from: String)
    func pinger(_ pinger: Ping, didReceiveUnexpectedPacket packet: Data, from: String)
}

public protocol Ping {
    var hostName: String { get }
    var delegate: SimplePingDelegate? { get set }
    var hostAddress: Data? { get }
    var hostAddressFamily: sa_family_t { get }
    var identifier: UInt16 { get }
    var nextSequenceNumber: UInt16 { get }
    
    func start()
    func stop()
    
    func sendPing(_ data: Data?)
    func setTTL(_ ttl: Int)
}

public class SimplePing: Ping {
    public enum AddressStyle: Int {
        case any
        case icmpv4
        case icmpv6
    }
    
    public enum PingError: LocalizedError {
        case networkError(type: String, code: Int)
        case posixError(type: String, code: Int)
        case hostNotFound
        
        public var errorDescription: String? {
            switch self {
            case .networkError(let type, let code):
                "Network error occured: \(type): \(code)"
            case .posixError(let type, let code):
                "POSIX error occured: \(type): \(code)"
            case .hostNotFound:
                "Host not found"
            }
        }
    }
    
    public var hostName: String
    public weak var delegate: SimplePingDelegate?
    public var hostAddress: Data?
    public var identifier: UInt16
    public var nextSequenceNumber: UInt16
    
    public var addressStyle: AddressStyle
    
    private var sequenceOverflowFlag: Bool
    private var host: CFHost?
    private var _socket: CFSocket?
    private let lock: NSLock
    
    public init(hostName: String) {
        self.hostName = hostName
        self.identifier = UInt16(arc4random_uniform(UInt32(UInt16.max)))
        
        self.nextSequenceNumber = 0
        self.sequenceOverflowFlag = false
        self.addressStyle = .any
        self.lock = NSLock()
    }
    
    deinit {
        self.stop()
    }
    
    public var hostAddressFamily: sa_family_t {
        return if let address = hostAddress,
            address.count >= MemoryLayout<sockaddr>.size {
            address.to(sockaddr.self).sa_family
        } else {
            sa_family_t(AF_UNSPEC)
        }
    }
    
    public func start() {
        guard hostAddress == nil else {
            return
        }
        
        let hostNameRef = CFStringCreateCopy(kCFAllocatorDefault, hostName as CFString)
        let host = CFHostCreateWithName(kCFAllocatorDefault, hostNameRef!).takeUnretainedValue()
        var streamError = CFStreamError()
        let success = CFHostStartInfoResolution(host, CFHostInfoType.addresses, &streamError)
        if success {
            self.hostResolutionDone(host)
        } else {
            self.didFailWithHostStreamError(streamError)
        }
    }
    
    public func stop() {
        self.stopSocket()
        self.hostAddress = nil
    }
    
    public func sendPing(_ data: Data? = nil) {
        guard let hostAddress = self.hostAddress else {
            print("Host address is nil")
            return
        }
        var payload = Data()
        if let data = data {
            payload = data
        } else {
            payload = String(format: "%28zd bottles of beer on the wall", ssize_t(99) - size_t(self.nextSequenceNumber % 100)).data(using: .ascii)!
        }
        
        var packet = Data()
        switch self.hostAddressFamily {
        case UInt8(AF_INET):
            packet = self.pingPacketWithType(ICMPv4Type.EchoRequest, payload: payload, requiresChecksum: true)
        case UInt8(AF_INET6):
            packet = self.pingPacketWithType(ICMPv6Type.EchoRequest, payload: payload, requiresChecksum: false)
        default:
            fatalError("hostAddressFamily has incorrect value")
        }
        
        let repatCount = data == nil ? 3 : 1
        var bytesSent = 0
        var err: Int32 = 0
        if self._socket == nil {
            bytesSent = -1
            err = EBADF
        } else {
            for _ in 0..<repatCount {
                bytesSent = sendto(CFSocketGetNative(self._socket),
                                   packet.unsafeBytes,
                                   packet.count,
                                   0,
                                   hostAddress.unsafeBytes.assumingMemoryBound(to: sockaddr.self),
                                   socklen_t(hostAddress.count))
            }
            
            err = 0
            if bytesSent < 0 {
                err = errno
            }
        }
        
        if bytesSent > 0 && bytesSent == packet.count {
            delegate?.pinger(self, didSendPacket: packet, sequence: self.nextSequenceNumber)
        } else {
            if err == 0 {
                err = ENOBUFS
            }
            let error = PingError.posixError(type: "Could not send bytes", code: Int(err))
            delegate?.pinger(self, didFailToSendPacket: packet, sequence: self.nextSequenceNumber, error: error)
        }
        
        if nextSequenceNumber < UInt16.max {
            nextSequenceNumber += 1
            if sequenceOverflowFlag && nextSequenceNumber >= 120 {
                sequenceOverflowFlag = false
            }
        } else {
            sequenceOverflowFlag = true
            nextSequenceNumber = 0
        }
    }
    
    public func setTTL(_ ttl: Int) {
        var internalTtl = ttl
        setTimeout(3)
        setsockopt(CFSocketGetNative(self._socket), IPPROTO_IP, IP_TTL, &internalTtl, socklen_t(MemoryLayout.size(ofValue: internalTtl)))
    }
    
    private func setTimeout(_ sec: Int) {
        var tv = timeval()
        tv.tv_sec = sec
        tv.tv_usec = 0 //1000000 * sec; // 0.1 sec
        setsockopt(CFSocketGetNative(self._socket), SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout.size(ofValue: tv)))
        let ret = setsockopt(CFSocketGetNative(self._socket), SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout.size(ofValue: tv)))
        print("set recv timeout \(ret) err \(errno)")
    }
    
    private func didFailWithError(_ error: Error) {
        self.stop()
        delegate?.pinger(self, didFailWithError: error)
    }
    
    private func didFailWithHostStreamError(_ error: CFStreamError) {
        if error.domain == kCFStreamErrorDomainNetDB {
            let err = PingError.networkError(type: kCFGetAddrInfoFailureKey as String, code: Int(error.error))
            self.didFailWithError(err)
            return
        }
        let err = PingError.networkError(type: "StreamError(\(error.domain))", code: Int(error.error))
        self.didFailWithError(err)
    }
    
    private func pingPacketWithType(_ type: UInt8, payload: Data, requiresChecksum: Bool) -> Data {
        let icmpHeaderRef = UnsafeMutablePointer<ICMPHeader>.allocate(capacity: 1)
        defer {
            icmpHeaderRef.deallocate()
        }
        memset(icmpHeaderRef, 0, MemoryLayout<ICMPHeader>.stride)
        
        icmpHeaderRef.pointee.type = type
        icmpHeaderRef.pointee.code = 0
        icmpHeaderRef.pointee.checkSum = 0
        icmpHeaderRef.pointee.identifier = CFSwapInt16HostToBig(self.identifier)
        icmpHeaderRef.pointee.sequenceNumber = CFSwapInt16HostToBig(self.nextSequenceNumber)
        
        let packetSize = MemoryLayout<ICMPHeader>.size + payload.count
        let packet = UnsafeMutablePointer<UInt8>.allocate(capacity: packetSize)
        defer {
            packet.deallocate()
        }
        memcpy(packet, icmpHeaderRef, MemoryLayout<ICMPHeader>.size)
        memcpy(packet.advanced(by: MemoryLayout<ICMPHeader>.size), payload.unsafeBytes, payload.count)
        
        if requiresChecksum {
            icmpHeaderRef.pointee.checkSum = checksum(packet, packetSize)
        }
        memcpy(packet, icmpHeaderRef, MemoryLayout<ICMPHeader>.size)
        
        let result = Data(bytes: packet, count: packetSize)
        return result
    }
    
    private func icmpHeaderOffsetInIPv4Packet(_ packet: Data) -> Int {
        guard packet.count >= MemoryLayout<IPHeader>.size + MemoryLayout<ICMPHeader>.size else {
            return -1
        }
        let ipHeaderRef = UnsafeMutablePointer<IPHeader>.allocate(capacity: 1)
        defer {
            ipHeaderRef.deallocate()
        }
        memcpy(ipHeaderRef, packet.unsafeBytes, MemoryLayout<IPHeader>.size)
        guard (ipHeaderRef.pointee.versionAndHeaderLength & 0xf0) == 0x40 &&
            ipHeaderRef.pointee.protocol == IPPROTO_ICMP else {
                return -1
        }
        let ipHeaderLength = Int(ipHeaderRef.pointee.versionAndHeaderLength & 0x0f) * MemoryLayout<UInt32>.size
        guard packet.count >= ipHeaderLength + MemoryLayout<ICMPHeader>.size else {
            return -1
        }
        return ipHeaderLength
    }
    
    private func validateSequence(_ sequence: UInt16) -> Bool {
        let maxTravelTime: UInt32 = 120
        if sequenceOverflowFlag {
            return UInt32(UInt16.max - sequence) + UInt32(nextSequenceNumber) < maxTravelTime
        } else {
            return sequence < nextSequenceNumber
        }
    }
    
    private func validatePing4ResponsePacket(_ packet: inout Data, sequence: inout UInt16) -> Bool {
        let icmpHeaderOffset = self.icmpHeaderOffsetInIPv4Packet(packet)
        guard icmpHeaderOffset != -1 else {
            print("[WARNING] ICMP header offset cannot be determined")
            return false
        }
        let icmpHeaderRef = UnsafeMutablePointer<ICMPHeader>.allocate(capacity: 1)
        defer {
            icmpHeaderRef.deallocate()
        }
        memcpy(icmpHeaderRef, packet.unsafeBytes.advanced(by: icmpHeaderOffset), MemoryLayout<ICMPHeader>.size)
        
        let receivedChecksum = icmpHeaderRef.pointee.checkSum
        icmpHeaderRef.pointee.checkSum = 0
        let icmpDataSize = packet.count - icmpHeaderOffset
        let icmpDataRef = UnsafeMutablePointer<UInt8>.allocate(capacity: icmpDataSize)
        defer {
            icmpDataRef.deallocate()
        }
        memcpy(icmpDataRef, icmpHeaderRef, MemoryLayout<ICMPHeader>.size)
        memcpy(icmpDataRef.advanced(by: MemoryLayout<ICMPHeader>.size), packet.unsafeBytes.advanced(by: icmpHeaderOffset + MemoryLayout<ICMPHeader>.size), icmpDataSize - MemoryLayout<ICMPHeader>.size)
        let calculatedChecksum = checksum(icmpDataRef, icmpDataSize)
        guard receivedChecksum == calculatedChecksum else {
            print("[WARNING] packet checksum doesn't match \(String(receivedChecksum, radix: 16)) != \(String(calculatedChecksum, radix: 16)), data: \(packet.advanced(by: icmpHeaderOffset).hex)")
            return false
        }
        icmpHeaderRef.pointee.checkSum = receivedChecksum
        guard icmpHeaderRef.pointee.type == ICMPv4Type.EchoReply
            && icmpHeaderRef.pointee.code == 0 else {
                print("[WARNING] packet type/code doesn't match exepected \(icmpHeaderRef.pointee.type)/\(icmpHeaderRef.pointee.code) != \(ICMPv4Type.EchoReply)/0")
                return false
        }
        guard self.identifier == CFSwapInt16BigToHost(icmpHeaderRef.pointee.identifier)
            else {
                print("[WARNING] identifier in header doesn't match")
                return false
        }
        
        let sequenceNumber = CFSwapInt16BigToHost(icmpHeaderRef.pointee.sequenceNumber)
        guard self.validateSequence(sequenceNumber) else {
            print("[WARNING] sequence validation failed, \(sequenceNumber) too far from \(self.nextSequenceNumber)")
            return false
        }
        packet.replaceSubrange((0..<icmpHeaderOffset), with: [])
        sequence = sequenceNumber
        
        return true
    }
    
    private func validatePing6ResponsePacket(_ packet: inout Data, sequence: inout UInt16) -> Bool {
        guard packet.count >= MemoryLayout<ICMPHeader>.size else {
            print("[ERROR] packet size too low")
            return false
        }
        let icmpHeaderRef = UnsafeMutablePointer<ICMPHeader>.allocate(capacity: 1)
        defer {
            icmpHeaderRef.deallocate()
        }
        memcpy(icmpHeaderRef, packet.unsafeBytes, MemoryLayout<ICMPHeader>.size)
        
        guard icmpHeaderRef.pointee.type == ICMPv6Type.EchoReply
            && icmpHeaderRef.pointee.code == 0 else {
                print("[ERROR] unexpected type/code pair: \(icmpHeaderRef.pointee.type)/\(icmpHeaderRef.pointee.code) != \(ICMPv6Type.EchoReply)/0")
                return false
        }
        guard self.identifier == CFSwapInt16BigToHost(icmpHeaderRef.pointee.identifier) else {
            print("[ERROR] wrong identifier")
            return false
        }
        
        let sequenceNumber = CFSwapInt16BigToHost(icmpHeaderRef.pointee.sequenceNumber)
        guard self.validateSequence(sequenceNumber) else {
            print("[ERROR] sequence verification failed")
            return false
        }
        sequence = sequenceNumber
        return true
    }
    
    private func validatePingResponsePacket(_ packet: inout Data, sequence: inout UInt16) -> Bool {
        var result = false
        switch self.hostAddressFamily {
        case UInt8(AF_INET):
            result = self.validatePing4ResponsePacket(&packet, sequence: &sequence)
        case UInt8(AF_INET6):
            result = self.validatePing6ResponsePacket(&packet, sequence: &sequence)
        default:
            fatalError("hostAddressFamily has incorrect value")
        }
        return result
    }
    
    private func readData() {
        let bufferSize = 65535
        let addrRef = UnsafeMutablePointer<sockaddr_storage>.allocate(capacity: 1)
        defer {
            addrRef.deallocate()
        }
        var bytesRead = 0
        
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer {
            buffer.deallocate()
        }
        var addrLen = socklen_t(MemoryLayout<sockaddr_storage>.size)
        
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
        
        addrRef.withMemoryRebound(to: sockaddr.self, capacity: 1, {
            bytesRead = recvfrom(CFSocketGetNative(self._socket),
                                 buffer,
                                 bufferSize,
                                 0,
                                 $0,
                                 &addrLen)
            getnameinfo($0,
                        addrLen,
                        hostStrRef,
                        maxHostLen,
                        portStrRef,
                        maxPortLen,
                        NI_NUMERICHOST | NI_NUMERICSERV)
        })
        
        let hostStr = String(cString: hostStrRef, encoding: .ascii)
        let sourceAddressString = "\(hostStr ?? "nil")"
        
        var err = 0
        if bytesRead < 0 {
            err = Int(errno)
        }
        
        if bytesRead > 0 {
            var sequenceNumber: UInt16 = 0
            var packet = Data(bytes: buffer, count: bytesRead)
            if self.validatePingResponsePacket(&packet, sequence: &sequenceNumber) {
                self.delegate?.pinger(self, didReceivePingResponsePacket: packet, sequence: sequenceNumber, from: sourceAddressString)
            } else {
                self.delegate?.pinger(self, didReceiveUnexpectedPacket: packet, from: sourceAddressString)
            }
        } else {
            if err == 0 {
                err = Int(EPIPE)
            }
            
            let error = PingError.posixError(type: "Could not receive bytes", code: err)
            self.didFailWithError(error)
        }
    }
    
    private func startwithHostAddress() {
        guard let hostAddress = self.hostAddress else {
            return
        }
        
        var fd: CFSocketNativeHandle = -1
        var err: Int32 = 0
        switch self.hostAddressFamily {
        case UInt8(AF_INET):
            fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
            if fd < 0 {
                err = errno
            }
        case UInt8(AF_INET6):
            fd = socket(AF_INET6, SOCK_DGRAM, IPPROTO_ICMPV6)
            if fd < 0 {
                err = errno
            }
        default:
            fatalError("hostAddressFamily has incorrect value")
        }
        guard err == 0 else {
            let error = PingError.posixError(type: "Could not open socket", code: Int(err))
            self.didFailWithError(error)
            return
        }
        
        let info = Unmanaged.passUnretained(self).toOpaque()
        var context = CFSocketContext(version: 0, info: info, retain: nil, release: nil, copyDescription: nil)
        self._socket = CFSocketCreateWithNative(kCFAllocatorDefault,
                                                fd,
                                                CFSocketCallBackType.readCallBack.rawValue,
                                                { (_, _, _, _, info) in
                                                    let pingObj = Unmanaged<SimplePing>.fromOpaque(info!).takeUnretainedValue()
                                                    pingObj.readData()
        },
                                                &context)
        guard (CFSocketGetSocketFlags(self._socket) & kCFSocketCloseOnInvalidate) != 0 else {
            fatalError("Socket setup error")
        }
        fd = -1
        
        let source = CFSocketCreateRunLoopSource(kCFAllocatorDefault, self._socket, 0)
        CFRunLoopAddSource(RunLoop.current.getCFRunLoop(), source, CFRunLoopMode.defaultMode)
        
        self.delegate?.pinger(self, didStartWithAddress: hostAddress.hostString())
    }
    
    private func hostResolutionDone(_ host: CFHost) {
        var resolved: DarwinBoolean = false
        let addresses = CFHostGetAddressing(host, &resolved)
        var success = false
        if let addresses = addresses,
            resolved.boolValue {
            for address in addresses.takeRetainedValue() as NSArray {
                if let addressData = address as? NSData as Data? {
                    let addr = addressData.to(sockaddr.self)
                    if addressData.count >= MemoryLayout<sockaddr>.size {
                        switch addr.sa_family {
                        case UInt8(AF_INET):
                            if self.addressStyle != AddressStyle.icmpv6 {
                                self.hostAddress = addressData
                                success = true
                            }
                        case UInt8(AF_INET6):
                            if self.addressStyle != AddressStyle.icmpv4 {
                                self.hostAddress = addressData
                                success = true
                            }
                        default:
                            continue
                        }
                    }
                }
                if success {
                    break
                }
            }
        }
        
        CFHostCancelInfoResolution(host, .addresses)
        
        if success {
            self.startwithHostAddress()
        } else {
            let error = PingError.hostNotFound
            self.didFailWithError(error)
        }
    }
    
    private func stopSocket() {
        if let socket = self._socket {
            CFSocketInvalidate(socket)
            self._socket = nil
        }
    }
    
    private func checksum(_ buf: UnsafeRawPointer, _ bufLen: Int) -> UInt16 {
        var bytesLeft: Int = bufLen
        var sum: UInt32 = 0
        var cursor: UnsafePointer<UInt16> = buf.assumingMemoryBound(to: UInt16.self)
        
        while bytesLeft > 1 {
            sum += UInt32(cursor.pointee)
            cursor = cursor.advanced(by: 1)
            bytesLeft -= 2
        }
        
        if bytesLeft == 1 {
            sum += UInt32(cursor.pointee & 0xff00)
        }
        
        sum = (sum >> 16) + (sum & 0xffff)
        sum += (sum >> 16)
        sum &= 0x0000ffff
        let answer: UInt16 = ~UInt16(sum)
        return answer
    }
}
