//  FileReader.swift
//  Pique
//
//  Created by Henry Stamerjohann, Declarative IT GmbH, 07/03/2026

import Foundation

enum FileReader {
    static let maxFileSize: UInt64 = 10_000_000 // 10 MB

    static func read(url: URL) throws -> String {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        let size = attrs[.size] as? UInt64 ?? 0
        guard size <= maxFileSize else {
            throw FileReaderError.fileTooLarge(size)
        }

        let data = try Data(contentsOf: url)

        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return text
        }
        return String(decoding: data, as: UTF8.self)
    }

    enum FileReaderError: LocalizedError {
        case fileTooLarge(UInt64)

        var errorDescription: String? {
            switch self {
            case .fileTooLarge(let size):
                let mb = Double(size) / 1_000_000
                return String(format: "File too large (%.1f MB). Maximum is 10 MB.", mb)
            }
        }
    }
}
