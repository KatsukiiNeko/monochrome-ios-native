// FLACMetadata.swift: rewrite FLAC metadata blocks (Vorbis comments + front-cover
// PICTURE) without touching audio frames. Everything after the last metadata
// block is treated as opaque bytes and compared by hash after the write.
import Foundation

public enum FLACMetadataError: LocalizedError, Equatable {
    case corrupt
    case pictureTooLarge
    case pictureNotJPEG
    case verificationFailed

    public var errorDescription: String? {
        switch self {
        case .corrupt: "The FLAC file's metadata could not be read."
        case .pictureTooLarge: "The cover image exceeds the 1 MB metadata limit."
        case .pictureNotJPEG: "The cover image is not a JPEG."
        case .verificationFailed: "The rewritten FLAC failed its audio-integrity check."
        }
    }
}

public enum FLACMetadata {
    /// FLAC spec: PICTURE payloads should stay modest; the app allows 1 MB.
    public static let maxPictureBytes = 1_048_576

    public struct Tags: Sendable, Equatable {
        public var title: String?
        public var artist: String?
        public var album: String?
        public var albumArtist: String?
        public var trackNumber: Int?
        public var date: String?
        public var isrc: String?

        public init(
            title: String? = nil,
            artist: String? = nil,
            album: String? = nil,
            albumArtist: String? = nil,
            trackNumber: Int? = nil,
            date: String? = nil,
            isrc: String? = nil
        ) {
            self.title = title
            self.artist = artist
            self.album = album
            self.albumArtist = albumArtist
            self.trackNumber = trackNumber
            self.date = date
            self.isrc = isrc
        }

        var vorbisFields: [String: String] {
            var fields: [String: String] = [:]
            if let title, !title.isEmpty { fields["TITLE"] = title }
            if let artist, !artist.isEmpty { fields["ARTIST"] = artist }
            if let album, !album.isEmpty { fields["ALBUM"] = album }
            if let albumArtist, !albumArtist.isEmpty { fields["ALBUMARTIST"] = albumArtist }
            if let trackNumber, trackNumber > 0 { fields["TRACKNUMBER"] = String(trackNumber) }
            if let date, !date.isEmpty { fields["DATE"] = date }
            if let isrc, !isrc.isEmpty { fields["ISRC"] = isrc }
            return fields
        }
    }

    public static func isFLAC(fileURL: URL) -> Bool {
        guard let header = try? Data(contentsOf: fileURL), header.count >= 4 else { return false }
        return header.prefix(4) == Data("fLaC".utf8)
    }

    /// Returns false when the file is not FLAC (callers skip silently), throws on
    /// a corrupt structure or an unusable picture. Provided fields are merged into
    /// the existing comment block; unknown comments are preserved; padding is
    /// dropped and an existing cover is replaced.
    @discardableResult
    public static func embed(fileURL: URL, tags: Tags?, artworkJPEG: Data?) throws -> Bool {
        guard isFLAC(fileURL: fileURL) else { return false }
        if let artworkJPEG {
            guard artworkJPEG.count <= maxPictureBytes else { throw FLACMetadataError.pictureTooLarge }
            guard artworkJPEG.isJPEGData else { throw FLACMetadataError.pictureNotJPEG }
        }
        guard tags != nil || artworkJPEG != nil else { return true }

        let original = try Data(contentsOf: fileURL)
        let parsed = try parse(original)
        // The audio region is hashed before the rewrite and compared after, so a
        // copying mistake cannot slip through.
        let audioHash = SHA256.digest(original.suffix(from: parsed.audioStart))

        var blocks = parsed.blocks.filter { ![BlockType.padding, BlockType.vorbisComment, BlockType.picture].contains($0.type) }
        let existing = parsed.blocks.first { $0.type == BlockType.vorbisComment }
        let vendor = existing.flatMap { try? vorbisComments(from: $0.payload).vendor }
            ?? TracksAPIClient.userAgent
        var comments = existing.flatMap { try? vorbisComments(from: $0.payload).comments } ?? [:]
        if let tags {
            for (key, value) in tags.vorbisFields {
                comments[key.uppercased()] = value
            }
        }
        blocks.append(Block(type: BlockType.vorbisComment, payload: vorbisCommentPayload(vendor: vendor, comments: comments)))
        if let artworkJPEG {
            blocks.append(Block(type: BlockType.picture, payload: picturePayload(jpeg: artworkJPEG)))
        }

        var output = Data("fLaC".utf8)
        let blockCount = blocks.count
        for (index, block) in blocks.enumerated() {
            output.append(blockHeader(type: block.type, length: block.payload.count, isLast: index == blockCount - 1))
            output.append(block.payload)
        }
        output.append(original.suffix(from: parsed.audioStart))

        try output.write(to: fileURL, options: .atomic)

        // Re-parse the written file and prove the audio bytes are untouched.
        let rewritten = try Data(contentsOf: fileURL)
        let verified = try parse(rewritten)
        guard SHA256.digest(rewritten.suffix(from: verified.audioStart)) == audioHash else {
            throw FLACMetadataError.verificationFailed
        }
        return true
    }

    /// Existing comment fields, keyed uppercase, for callers that inspect or merge.
    public static func readComments(fileURL: URL) throws -> [String: String] {
        let data = try Data(contentsOf: fileURL)
        let parsed = try parse(data)
        guard let block = parsed.blocks.first(where: { $0.type == BlockType.vorbisComment }) else { return [:] }
        return try vorbisComments(from: block.payload).comments
    }

    /// The stored front-cover bytes, if any.
    public static func readPicture(fileURL: URL) throws -> Data? {
        let data = try Data(contentsOf: fileURL)
        let parsed = try parse(data)
        guard let block = parsed.blocks.first(where: { $0.type == BlockType.picture }) else { return nil }
        return try frontCoverJPEG(from: block.payload)
    }

    // MARK: - Container layout

    private struct BlockType {
        static let streamInfo = UInt8(0)
        static let padding = UInt8(1)
        static let seekTable = UInt8(3)
        static let vorbisComment = UInt8(4)
        static let picture = UInt8(6)
    }

    struct Block {
        var type: UInt8
        var payload: Data
    }

    struct Parsed {
        var blocks: [Block]
        /// Where the opaque audio frames begin.
        var audioStart: Int
    }

    private static func parse(_ data: Data) throws -> Parsed {
        guard data.count >= 4, data.prefix(4) == Data("fLaC".utf8) else { throw FLACMetadataError.corrupt }
        var position = 4
        var blocks: [Block] = []
        while true {
            guard position + 4 <= data.count else { throw FLACMetadataError.corrupt }
            let header = data[position]
            let type = header & 0x7F
            let isLast = header & 0x80 != 0
            let length = Int(bigEndian24(data, position + 1))
            let payloadStart = position + 4
            let payloadEnd = payloadStart + length
            guard payloadEnd <= data.count else { throw FLACMetadataError.corrupt }
            blocks.append(Block(type: type, payload: data.subdata(in: payloadStart..<payloadEnd)))
            position = payloadEnd
            if isLast { break }
        }
        // STREAMINFO must be the first block; without it the file is not playable.
        guard let first = blocks.first, first.type == BlockType.streamInfo, first.payload.count == 34 else {
            throw FLACMetadataError.corrupt
        }
        return Parsed(blocks: blocks, audioStart: position)
    }

    private static func blockHeader(type: UInt8, length: Int, isLast: Bool) -> Data {
        var header = Data(count: 4)
        header[0] = (isLast ? 0x80 : 0) | (type & 0x7F)
        header[1] = UInt8((length >> 16) & 0xFF)
        header[2] = UInt8((length >> 8) & 0xFF)
        header[3] = UInt8(length & 0xFF)
        return header
    }

    private static func bigEndian24(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset]) << 16 | UInt32(data[offset + 1]) << 8 | UInt32(data[offset + 2])
    }

    // MARK: - Vorbis comments (little-endian lengths)

    private static func vorbisComments(from payload: Data) throws -> (vendor: String, comments: [String: String]) {
        var offset = 0
        func readLE32() throws -> Int {
            guard offset + 4 <= payload.count else { throw FLACMetadataError.corrupt }
            let value = Int(payload[offset])
                | Int(payload[offset + 1]) << 8
                | Int(payload[offset + 2]) << 16
                | Int(payload[offset + 3]) << 24
            offset += 4
            return value
        }
        func readString(_ length: Int) throws -> String {
            guard length >= 0, offset + length <= payload.count else { throw FLACMetadataError.corrupt }
            let string = String(data: payload.subdata(in: offset..<offset + length), encoding: .utf8)
            offset += length
            guard let string else { throw FLACMetadataError.corrupt }
            return string
        }

        let vendorLength = try readLE32()
        let vendor = try readString(vendorLength)
        let count = try readLE32()
        var comments: [String: String] = [:]
        for _ in 0..<max(count, 0) {
            let entryLength = try readLE32()
            let entry = try readString(entryLength)
            guard let separator = entry.firstIndex(of: "=") else { continue }
            let key = String(entry[entry.startIndex..<separator]).uppercased()
            comments[key] = String(entry[entry.index(after: separator)...])
        }
        return (vendor, comments)
    }

    private static func vorbisCommentPayload(vendor: String, comments: [String: String]) -> Data {
        func littleEndian32(_ value: Int) -> Data {
            withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) }
        }
        var payload = Data()
        let vendorData = Data(vendor.utf8)
        payload.append(littleEndian32(vendorData.count))
        payload.append(vendorData)
        let entries = comments
            .filter { !$0.key.isEmpty }
            .map { "\($0.key)=\($0.value)" }
            .sorted()
        payload.append(littleEndian32(entries.count))
        for entry in entries {
            let entryData = Data(entry.utf8)
            payload.append(littleEndian32(entryData.count))
            payload.append(entryData)
        }
        return payload
    }

    // MARK: - PICTURE block (big-endian fields)

    private static func picturePayload(jpeg: Data) -> Data {
        func bigEndian32(_ value: UInt32) -> Data {
            withUnsafeBytes(of: value.bigEndian) { Data($0) }
        }
        var payload = Data()
        payload.append(bigEndian32(3)) // 3 = front cover
        let mime = Data("image/jpeg".utf8)
        payload.append(bigEndian32(UInt32(mime.count)))
        payload.append(mime)
        payload.append(bigEndian32(0)) // empty description
        payload.append(bigEndian32(0)) // width, 0 = unspecified
        payload.append(bigEndian32(0)) // height
        payload.append(bigEndian32(0)) // depth
        payload.append(bigEndian32(0)) // colors
        payload.append(bigEndian32(UInt32(jpeg.count)))
        payload.append(jpeg)
        return payload
    }

    private static func frontCoverJPEG(from payload: Data) throws -> Data? {
        // All fields big-endian: type(4) mimeLen(4) mime descLen(4) desc
        // width(4) height(4) depth(4) colors(4) dataLen(4) data
        func readBigEndian32(_ offset: Int) throws -> Int {
            guard offset + 4 <= payload.count else { throw FLACMetadataError.corrupt }
            return Int(payload[offset]) << 24
                | Int(payload[offset + 1]) << 16
                | Int(payload[offset + 2]) << 8
                | Int(payload[offset + 3])
        }

        var offset = 4 // picture type
        let mimeLength = try readBigEndian32(offset)
        offset += 4 + mimeLength // mime
        let mime = String(data: payload.subdata(in: offset - mimeLength..<offset), encoding: .ascii)
        let descriptionLength = try readBigEndian32(offset)
        offset += 4 + descriptionLength
        offset += 16 // width, height, depth, colors
        let dataLength = try readBigEndian32(offset)
        offset += 4
        guard mime == "image/jpeg", dataLength >= 0, offset + dataLength <= payload.count else {
            throw FLACMetadataError.corrupt
        }
        return payload.subdata(in: offset..<offset + dataLength)
    }
}

extension Data {
    /// JPEG SOI + marker magic: FF D8 FF.
    var isJPEGData: Bool {
        count >= 3 && self[startIndex] == 0xFF && self[startIndex + 1] == 0xD8 && self[startIndex + 2] == 0xFF
    }
}
