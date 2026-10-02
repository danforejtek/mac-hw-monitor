import Foundation
import Darwin

struct InterfaceInfo: Identifiable, Equatable {
    let name: String
    var address: String?
    var inPerSec: Double = 0
    var outPerSec: Double = 0
    var id: String { name }
}

struct NetworkSample {
    var interfaces: [InterfaceInfo] = []
    var inPerSec: Double = 0
    var outPerSec: Double = 0
    var totalIn: UInt64 = 0
    var totalOut: UInt64 = 0
}

/// Sum of all non-loopback interface counters from getifaddrs.
final class NetworkSampler {
    private var lastIn: UInt64 = 0, lastOut: UInt64 = 0
    private var lastPerIf: [String: (UInt64, UInt64)] = [:]
    private var lastTime: Date?

    func sample() -> NetworkSample {
        var out = NetworkSample()
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return out }
        defer { freeifaddrs(ifap) }

        var inBytes: UInt64 = 0, outBytes: UInt64 = 0
        var perIf: [String: (UInt64, UInt64)] = [:]
        var addresses: [String: String] = [:]
        var order: [String] = []
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = p {
            defer { p = ifa.pointee.ifa_next }
            guard let addr = ifa.pointee.ifa_addr else { continue }
            let name = String(cString: ifa.pointee.ifa_name)
            // Skip loopback and virtual/bridge-ish interfaces that double count.
            if name.hasPrefix("lo") || name.hasPrefix("awdl") || name.hasPrefix("llw") || name.hasPrefix("utun") || name.hasPrefix("bridge") { continue }
            guard (ifa.pointee.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
            if addr.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    addresses[name] = String(cString: host)
                }
            } else if addr.pointee.sa_family == UInt8(AF_LINK), let data = ifa.pointee.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                inBytes += UInt64(d.ifi_ibytes)
                outBytes += UInt64(d.ifi_obytes)
                perIf[name] = (UInt64(d.ifi_ibytes), UInt64(d.ifi_obytes))
                order.append(name)
            }
        }

        let now = Date()
        if let t = lastTime {
            let dt = now.timeIntervalSince(t)
            if dt > 0 {
                // 32-bit counters may wrap; treat a decrease as a wrap of the whole sum (good enough for a rate).
                let dIn = inBytes >= lastIn ? inBytes - lastIn : (inBytes &+ (1 << 32)) - lastIn
                let dOut = outBytes >= lastOut ? outBytes - lastOut : (outBytes &+ (1 << 32)) - lastOut
                out.inPerSec = Double(dIn) / dt
                out.outPerSec = Double(dOut) / dt
                for name in order {
                    guard let cur = perIf[name] else { continue }
                    var info = InterfaceInfo(name: name, address: addresses[name])
                    if let prev = lastPerIf[name] {
                        info.inPerSec = cur.0 >= prev.0 ? Double(cur.0 - prev.0) / dt : 0
                        info.outPerSec = cur.1 >= prev.1 ? Double(cur.1 - prev.1) / dt : 0
                    }
                    out.interfaces.append(info)
                }
            }
        }
        // Interfaces with an address or traffic first, then the rest by name.
        out.interfaces.sort { a, b in
            let aa = a.address != nil, bb = b.address != nil
            if aa != bb { return aa }
            return a.name < b.name
        }
        lastPerIf = perIf
        lastIn = inBytes; lastOut = outBytes; lastTime = now
        out.totalIn = inBytes; out.totalOut = outBytes
        return out
    }
}
