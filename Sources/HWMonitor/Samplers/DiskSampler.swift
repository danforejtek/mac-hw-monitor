import Foundation
import IOKit

struct VolumeInfo: Identifiable, Equatable {
    let name: String
    let path: String
    let total: UInt64
    let free: UInt64
    var id: String { path }
    var usedPercent: Double { total > 0 ? Double(total - free) / Double(total) * 100 : 0 }
}

struct DiskSample {
    var volumes: [VolumeInfo] = []
    var readPerSec: Double = 0
    var writePerSec: Double = 0
    var totalRead: UInt64 = 0
    var totalWritten: UInt64 = 0
    var volumeTotal: UInt64 = 0
    var volumeFree: UInt64 = 0
    var volumeUsedPercent: Double { volumeTotal > 0 ? Double(volumeTotal - volumeFree) / Double(volumeTotal) * 100 : 0 }
}

/// Aggregate throughput of all block storage drivers plus free space of the boot volume.
final class DiskSampler {
    private var lastRead: UInt64 = 0, lastWrite: UInt64 = 0
    private var lastTime: Date?
    private var volumeTick = 0
    private var cachedVolumes: [VolumeInfo] = []

    func sample() -> DiskSample {
        var out = DiskSample()
        var read: UInt64 = 0, write: UInt64 = 0
        var iter: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iter) == KERN_SUCCESS {
            defer { IOObjectRelease(iter) }
            var svc = IOIteratorNext(iter)
            while svc != 0 {
                defer { IOObjectRelease(svc); svc = IOIteratorNext(iter) }
                if let stats = IORegistryEntryCreateCFProperty(svc, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any] {
                    read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                    write += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
                }
            }
        }
        let now = Date()
        if let t = lastTime {
            let dt = now.timeIntervalSince(t)
            if dt > 0 {
                out.readPerSec = read >= lastRead ? Double(read - lastRead) / dt : 0
                out.writePerSec = write >= lastWrite ? Double(write - lastWrite) / dt : 0
            }
        }
        lastRead = read; lastWrite = write; lastTime = now
        out.totalRead = read; out.totalWritten = write

        // Volume space via statfs: cheap. (The "ForImportantUsage" resource key goes through the
        // CacheDelete framework and costs tens of milliseconds, so it is deliberately avoided.)
        volumeTick += 1
        if volumeTick % 15 == 1 || cachedVolumes.isEmpty {
            cachedVolumes = Self.mountedVolumes()
        }
        out.volumes = cachedVolumes
        if let root = cachedVolumes.first(where: { $0.path == "/" }) ?? cachedVolumes.first {
            out.volumeTotal = root.total; out.volumeFree = root.free
        }
        return out
    }

    private static func mountedVolumes() -> [VolumeInfo] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: [.skipHiddenVolumes]) ?? []
        var result: [VolumeInfo] = []
        for url in urls {
            var fs = statfs()
            guard statfs(url.path, &fs) == 0 else { continue }
            let total = UInt64(fs.f_blocks) * UInt64(fs.f_bsize)
            guard total > 0 else { continue }
            let name = (try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? url.lastPathComponent
            result.append(VolumeInfo(name: name, path: url.path, total: total, free: UInt64(fs.f_bavail) * UInt64(fs.f_bsize)))
        }
        return result.sorted { $0.path == "/" ? true : $1.path == "/" ? false : $0.name < $1.name }
    }
}
