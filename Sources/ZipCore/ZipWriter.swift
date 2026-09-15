import Foundation
import CZip
import Darwin

public struct ZipError: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}
public final class Cancellation: @unchecked Sendable {
    fileprivate let pointer = cz_cancel_create()!
    public init() {}
    deinit { cz_cancel_free(pointer) }
    public func cancel() { cz_cancel_set(pointer) }
    public var isCancelled: Bool { cz_cancelled(pointer) != 0 }
    fileprivate func check() throws { if isCancelled { throw ZipError("已取消压缩。") } }
}
public struct ZipProgress: Sendable {
    public let completed: Int
    public let total: Int
    public let name: String
}
public struct ZipResult: Sendable {
    public let entriesWritten: Int
    /// Paths relative to the archive roots. Links are not followed or archived.
    public let skippedSymbolicLinks: [String]
}
private struct Entry {
    let url: URL
    let name: String
    let directory: Bool
    let date: Date
}
private struct Record {
    let name: Data, extra: Data
    let directory: Bool
    let time: UInt16, date: UInt16
    let crc: UInt32, size: UInt32, packed: UInt32, offset: UInt32
}
private extension Data {
    mutating func u16(_ v: UInt16) { var x = v.littleEndian; Swift.withUnsafeBytes(of: &x) { append(contentsOf: $0) } }
    mutating func u32(_ v: UInt32) { var x = v.littleEndian; Swift.withUnsafeBytes(of: &x) { append(contentsOf: $0) } }
}
public enum ZipWriter {
    private static let fm = FileManager.default
    private static let limit = UInt64(UInt32.max)

    /// Creates a new ZIP without replacing an existing destination. Original files are never modified.
    /// Symbolic links are skipped without following their targets and returned in the result.
    @discardableResult
    public static func create(sources: [URL], destination: URL, cancellation: Cancellation = Cancellation(),
                              progress: @escaping (ZipProgress) -> Void = { _ in }) throws -> ZipResult {
        guard !sources.isEmpty else { throw ZipError("请先添加文件或文件夹。") }
        let output = destination.standardizedFileURL.resolvingSymlinksInPath()
        guard !fm.fileExists(atPath: output.path) else { throw ZipError("保存位置已有同名文件，请换一个名字。") }
        let roots = sources.map { $0.standardizedFileURL }
        for root in roots {
            if try isSymbolicLink(root) { continue }
            let actual = root.resolvingSymlinksInPath().path
            guard output.path != actual && !output.path.hasPrefix(actual + "/") else {
                throw ZipError("请将 ZIP 保存在所选文件夹之外，以免把压缩包自身打包。")
            }
        }
        var entries: [Entry] = [], names = Set<String>()
        var skippedLinks: [String] = []
        func visit(_ url: URL, prefix: String) throws {
            try cancellation.check()
            let raw = url.lastPathComponent
            if raw == ".DS_Store" || raw == "__MACOSX" || raw.hasPrefix("._") { return }
            // lstat examines the link itself, including broken and circular links.
            if try isSymbolicLink(url) {
                skippedLinks.append(prefix + raw)
                return
            }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey, .fileSizeKey])
            let directory = values.isDirectory == true
            guard directory || values.isRegularFile == true else { throw ZipError("不支持此文件类型：\(url.path)") }
            let component = raw.precomposedStringWithCanonicalMapping
            try validate(component)
            let name = prefix + component
            // Windows paths are case-insensitive; NFC also unifies macOS decomposed filenames.
            let key = name.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            guard names.insert(key).inserted else { throw ZipError("Windows 上可能重名：\(name)。请重命名或移除重复选择。") }
            guard (name + (directory ? "/" : "")).utf8.count <= 65000 else { throw ZipError("文件路径过长：\(name)") }
            guard directory || UInt64(values.fileSize ?? 0) < limit else { throw ZipError("当前版本支持小于 4 GiB 的单个文件。") }
            guard entries.count < 65534 else { throw ZipError("当前版本最多支持 65,534 个文件和目录。") }
            entries.append(Entry(url: url, name: name + (directory ? "/" : ""), directory: directory, date: values.contentModificationDate ?? Date()))
            if directory {
                for child in try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    try visit(child, prefix: name + "/")
                }
            }
        }
        for root in roots { try visit(root, prefix: "") }
        guard !entries.isEmpty else {
            if !skippedLinks.isEmpty {
                throw ZipError("没有可压缩的文件；已跳过 \(skippedLinks.count) 个符号链接。请添加普通文件或实际文件夹。")
            }
            throw ZipError("没有可压缩的文件；所选项目均为 macOS 元数据。")
        }
        let temp = output.deletingLastPathComponent().appendingPathComponent(".cleanzip-\(UUID().uuidString).tmp")
        let fd = open(temp.path, O_CREAT | O_EXCL | O_RDWR | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw ZipError("无法在所选位置创建 ZIP：\(String(cString: strerror(errno)))") }
        let file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? file.close(); try? fm.removeItem(at: temp) }
        var records: [Record] = []
        for (index, entry) in entries.enumerated() {
            try cancellation.check()
            progress(ZipProgress(completed: index, total: entries.count, name: entry.name))
            let offset = try file.offset()
            guard offset < limit else { throw ZipError("当前版本支持小于 4 GiB 的 ZIP，请分批压缩。") }
            let name = Data(entry.name.utf8)
            var extra = Data()
            extra.u16(0x7075); extra.u16(UInt16(name.count + 5)); extra.append(1)
            extra.u32(name.withUnsafeBytes { cz_crc($0.baseAddress, UInt32(name.count)) }); extra.append(name)
            let (time, date) = dosDate(entry.date)
            var header = Data()
            header.u32(0x04034b50); header.u16(20); header.u16(0x0800)
            header.u16(entry.directory ? 0 : 8); header.u16(time); header.u16(date)
            header.u32(0); header.u32(0); header.u32(0)
            header.u16(UInt16(name.count)); header.u16(UInt16(extra.count)); header.append(name); header.append(extra)
            try file.write(contentsOf: header)
            var crc: UInt32 = 0, size: UInt32 = 0, packed: UInt32 = 0
            if !entry.directory {
                let input = open(entry.url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
                guard input >= 0 else { throw ZipError("无法读取：\(entry.url.path)") }
                defer { close(input) }
                var statInfo = stat()
                guard fstat(input, &statInfo) == 0 && (statInfo.st_mode & S_IFMT) == S_IFREG else { throw ZipError("文件类型已改变：\(entry.name)") }
                let result = cz_deflate(input, fd, cancellation.pointer, &crc, &size, &packed)
                if result == 1 { throw ZipError("已取消压缩。") }
                if result == 2 { throw ZipError("当前版本支持小于 4 GiB 的文件，请分批压缩。") }
                guard result == 0 else { throw ZipError("读写或压缩失败：\(entry.name)。请检查文件权限和剩余空间。") }
                var after = stat()
                guard fstat(input, &after) == 0, after.st_size == statInfo.st_size,
                      after.st_mtimespec.tv_sec == statInfo.st_mtimespec.tv_sec,
                      after.st_mtimespec.tv_nsec == statInfo.st_mtimespec.tv_nsec,
                      UInt64(size) == UInt64(statInfo.st_size) else { throw ZipError("压缩期间文件发生变化，请重试：\(entry.name)") }
            }
            let end = try file.offset()
            guard end < limit else { throw ZipError("当前版本支持小于 4 GiB 的 ZIP，请分批压缩。") }
            try file.seek(toOffset: offset + 14)
            var sizes = Data(); sizes.u32(crc); sizes.u32(packed); sizes.u32(size)
            try file.write(contentsOf: sizes); try file.seek(toOffset: end)
            records.append(Record(name: name, extra: extra, directory: entry.directory, time: time, date: date, crc: crc, size: size, packed: packed, offset: UInt32(offset)))
        }
        let centralOffset = try file.offset()
        for r in records {
            try cancellation.check()
            var d = Data()
            d.u32(0x02014b50); d.u16(20); d.u16(20); d.u16(0x0800); d.u16(r.directory ? 0 : 8)
            d.u16(r.time); d.u16(r.date); d.u32(r.crc); d.u32(r.packed); d.u32(r.size)
            d.u16(UInt16(r.name.count)); d.u16(UInt16(r.extra.count)); d.u16(0); d.u16(0); d.u16(0)
            d.u32(r.directory ? 0x10 : 0x20); d.u32(r.offset); d.append(r.name); d.append(r.extra)
            try file.write(contentsOf: d)
        }
        let centralEnd = try file.offset()
        guard centralEnd + 22 < limit else { throw ZipError("当前版本支持小于 4 GiB 的 ZIP，请分批压缩。") }
        var end = Data(); end.u32(0x06054b50); end.u16(0); end.u16(0)
        end.u16(UInt16(records.count)); end.u16(UInt16(records.count)); end.u32(UInt32(centralEnd - centralOffset)); end.u32(UInt32(centralOffset)); end.u16(0)
        try file.write(contentsOf: end); try file.synchronize(); try cancellation.check()
        // link() publishes the completed archive atomically and fails if destination exists.
        guard link(temp.path, output.path) == 0 else { throw ZipError("无法保存 ZIP（可能已有同名文件）：\(String(cString: strerror(errno)))") }
        progress(ZipProgress(completed: entries.count, total: entries.count, name: output.lastPathComponent))
        return ZipResult(entriesWritten: entries.count, skippedSymbolicLinks: skippedLinks)
    }
    private static func isSymbolicLink(_ url: URL) throws -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw ZipError("无法读取：\(url.path)（\(String(cString: strerror(errno)))）")
        }
        return (info.st_mode & S_IFMT) == S_IFLNK
    }
    private static func validate(_ name: String) throws {
        let invalid = CharacterSet(charactersIn: "<>:\"/\\|?*").union(.controlCharacters)
        let base = name.components(separatedBy: ".")[0].trimmingCharacters(in: .whitespaces).uppercased()
        let reserved = ["CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$"] + (1...9).flatMap { ["COM\($0)", "LPT\($0)"] } + ["COM¹", "COM²", "COM³", "LPT¹", "LPT²", "LPT³"]
        guard name.utf16.count <= 255, name.rangeOfCharacter(from: invalid) == nil, !name.hasSuffix(" "), !name.hasSuffix("."), !reserved.contains(base) else {
            throw ZipError("Windows 不支持此文件名：\(name)。请先重命名后再压缩。")
        }
    }
    private static func dosDate(_ date: Date) -> (UInt16, UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let y = min(2107, max(1980, c.year ?? 1980))
        let hours = (c.hour ?? 0) << 11
        let minutes = (c.minute ?? 0) << 5
        let seconds = (c.second ?? 0) / 2
        let year = (y - 1980) << 9
        let month = (c.month ?? 1) << 5
        return (UInt16(hours | minutes | seconds), UInt16(year | month | (c.day ?? 1)))
    }
}
