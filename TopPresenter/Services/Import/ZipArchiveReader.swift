//
//  ZipArchiveReader.swift
//  TopPresenter
//
//  Created by Cosmin Calin on 11/06/2026.
//
//  Minimal in-process ZIP reader (PPTX, OpenDocument, …).
//  Why not /usr/bin/ditto: child processes of a sandboxed app do NOT inherit
//  the user's file-access grants, so shelling out fails on user-selected files.
//  This reads the archive entirely in memory: central directory → local
//  headers → stored (0) or deflate (8) entries via the Compression framework.
//

import Foundation
import Compression

struct ZipArchiveReader {
    struct Entry {
        let name: String
        let method: UInt16          // 0 = stored, 8 = deflate
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    enum ZipError: LocalizedError {
        case notAZip
        case unsupported(String)
        case corrupt(String)

        var errorDescription: String? {
            switch self {
            case .notAZip:
                return String(localized: "Fișierul nu este o arhivă ZIP validă.", comment: "Zip error")
            case .unsupported(let what):
                return String(localized: "Arhivă ZIP nesuportată: \(what)", comment: "Zip error")
            case .corrupt(let what):
                return String(localized: "Arhivă ZIP coruptă: \(what)", comment: "Zip error")
            }
        }
    }

    private let data: Data
    let entries: [Entry]

    init(data: Data) throws {
        self.data = data
        self.entries = try Self.readCentralDirectory(data)
    }

    func entry(named name: String) -> Entry? {
        entries.first { $0.name == name }
    }

    /// Extracts and (if needed) inflates one entry.
    func extract(_ entry: Entry) throws -> Data {
        // Local header: PK\3\4 … name length @26, extra length @28, data follows.
        let base = entry.localHeaderOffset
        guard base + 30 <= data.count,
              Self.u32(data, base) == 0x04034b50 else {
            throw ZipError.corrupt("local header")
        }
        let nameLen = Int(Self.u16(data, base + 26))
        let extraLen = Int(Self.u16(data, base + 28))
        let payloadStart = base + 30 + nameLen + extraLen
        guard payloadStart + entry.compressedSize <= data.count else {
            throw ZipError.corrupt("entry payload out of bounds")
        }
        let payload = data.subdata(in: payloadStart..<payloadStart + entry.compressedSize)

        switch entry.method {
        case 0: // stored
            return payload
        case 8: // deflate
            guard let inflated = Self.inflate(payload, uncompressedSize: entry.uncompressedSize) else {
                throw ZipError.corrupt("deflate stream")
            }
            return inflated
        default:
            throw ZipError.unsupported("compression method \(entry.method)")
        }
    }

    // MARK: - Central directory

    private static func readCentralDirectory(_ data: Data) throws -> [Entry] {
        // Find End Of Central Directory (PK\5\6) scanning back over the
        // maximum possible comment length.
        let eocdSig: UInt32 = 0x06054b50
        let minEOCD = 22
        guard data.count >= minEOCD else { throw ZipError.notAZip }

        var eocdOffset = -1
        let scanStart = max(0, data.count - minEOCD - 65_535)
        var i = data.count - minEOCD
        while i >= scanStart {
            if u32(data, i) == eocdSig {
                eocdOffset = i
                break
            }
            i -= 1
        }
        guard eocdOffset >= 0 else { throw ZipError.notAZip }

        let entryCount = Int(u16(data, eocdOffset + 10))
        let cdOffset = Int(u32(data, eocdOffset + 16))
        if cdOffset == 0xFFFFFFFF || entryCount == 0xFFFF {
            throw ZipError.unsupported("ZIP64")
        }
        guard cdOffset < data.count else { throw ZipError.corrupt("central directory offset") }

        // Walk the central directory (PK\1\2 entries).
        var entries: [Entry] = []
        var offset = cdOffset
        let cdSig: UInt32 = 0x02014b50
        for _ in 0..<entryCount {
            guard offset + 46 <= data.count, u32(data, offset) == cdSig else { break }
            let method = u16(data, offset + 10)
            let compressedSize = Int(u32(data, offset + 20))
            let uncompressedSize = Int(u32(data, offset + 24))
            let nameLen = Int(u16(data, offset + 28))
            let extraLen = Int(u16(data, offset + 30))
            let commentLen = Int(u16(data, offset + 32))
            let localOffset = Int(u32(data, offset + 42))

            guard offset + 46 + nameLen <= data.count else { break }
            if compressedSize == 0xFFFFFFFF || uncompressedSize == 0xFFFFFFFF || localOffset == 0xFFFFFFFF {
                throw ZipError.unsupported("ZIP64")
            }
            let nameData = data.subdata(in: offset + 46..<offset + 46 + nameLen)
            let name = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .windowsCP1252)
                ?? ""

            entries.append(Entry(
                name: name,
                method: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localOffset
            ))
            offset += 46 + nameLen + extraLen + commentLen
        }
        return entries
    }

    // MARK: - Inflate (raw DEFLATE via Compression framework)

    private static func inflate(_ input: Data, uncompressedSize: Int) -> Data? {
        guard uncompressedSize > 0 else { return Data() }
        var output = Data(count: uncompressedSize)
        let written = output.withUnsafeMutableBytes { dst -> Int in
            input.withUnsafeBytes { src -> Int in
                guard let dstPtr = dst.bindMemory(to: UInt8.self).baseAddress,
                      let srcPtr = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                // COMPRESSION_ZLIB == raw DEFLATE (no zlib header) — exactly
                // what ZIP method 8 stores.
                return compression_decode_buffer(
                    dstPtr, uncompressedSize,
                    srcPtr, input.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == uncompressedSize else { return nil }
        return output
    }

    // MARK: - Little-endian readers

    private static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return UInt16(data[data.startIndex + offset])
            | (UInt16(data[data.startIndex + offset + 1]) << 8)
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset + 4 <= data.count else { return 0 }
        return UInt32(data[data.startIndex + offset])
            | (UInt32(data[data.startIndex + offset + 1]) << 8)
            | (UInt32(data[data.startIndex + offset + 2]) << 16)
            | (UInt32(data[data.startIndex + offset + 3]) << 24)
    }
}
