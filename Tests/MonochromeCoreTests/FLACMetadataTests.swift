// FLACMetadataTests.swift: block rewriting rules on a synthetic minimal FLAC.
import Foundation
import Testing
@testable import MonochromeCore

/// Builds a valid-shaped FLAC: fLaC header, STREAMINFO, Vorbis comments,
/// optional SEEKTABLE/PICTURE, padding, then opaque frame bytes.
private func makeFLAC(
    vendor: String = "fixture",
    comments: [String: String] = [:],
    seekTable: Data? = nil,
    pictureJPEG: Data? = nil,
    padding: Int = 16,
    frames: Data = Data([0xFF, 0xF8, 0x35, 0xC4, 0x00, 0x01, 0x02, 0x03, 0x04])
) -> Data {
    func block(_ type: UInt8, _ payload: Data, isLast: Bool) -> Data {
        var header = Data([isLast ? UInt8(0x80 | type) : type])
        header.append(UInt8((payload.count >> 16) & 0xFF))
        header.append(UInt8((payload.count >> 8) & 0xFF))
        header.append(UInt8(payload.count & 0xFF))
        return header + payload
    }
    func littleEndian32(_ value: Int) -> Data {
        withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) }
    }

    var streamInfo = Data(count: 34)
    streamInfo[0] = 0x10 // synthetic but correctly sized
    var blocks = [block(0, streamInfo, isLast: false)]
    if let seekTable {
        blocks.append(block(3, seekTable, isLast: false))
    }

    var commentPayload = littleEndian32(vendor.utf8.count) + Data(vendor.utf8)
    let entries = comments.map { "\($0.key)=\($0.value)" }.sorted()
    commentPayload += littleEndian32(entries.count)
    for entry in entries {
        commentPayload += littleEndian32(entry.utf8.count) + Data(entry.utf8)
    }
    blocks.append(block(4, commentPayload, isLast: false))

    if let pictureJPEG {
        func bigEndian32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.bigEndian) { Data($0) } }
        var picture = bigEndian32(3)
        picture += bigEndian32(UInt32(10)) + Data("image/jpeg".utf8)
        picture += bigEndian32(0) + bigEndian32(0) + bigEndian32(0) + bigEndian32(0) + bigEndian32(0)
        picture += bigEndian32(UInt32(pictureJPEG.count)) + pictureJPEG
        blocks.append(block(6, picture, isLast: false))
    }

    if padding > 0 {
        blocks.append(block(1, Data(count: padding), isLast: true))
    } else if let last = blocks.indices.last {
        // Mark the final block when there is no padding.
        blocks[last][0] |= 0x80
    }

    let blockBytes = blocks.reduce(into: Data()) { $0.append($1) }
    return Data("fLaC".utf8) + blockBytes + frames
}

private func temporaryFLAC(_ data: Data) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("flac-\(UUID().uuidString).flac")
    try data.write(to: url)
    return url
}

private let fakeJPEG = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x11, 0x22, 0x33, 0xFF, 0xD9])

@Suite("FLACMetadata")
struct FLACMetadataTests {
    private let tags = FLACMetadata.Tags(
        title: "Song", artist: "Artist", album: "Album", albumArtist: "Album Artist",
        trackNumber: 7, date: "2026", isrc: "ABCDE2600001"
    )

    @Test("tags are embedded and audio frames are untouched")
    func embedAddsTags() throws {
        let frames = Data(repeating: 0xAB, count: 64)
        let url = try temporaryFLAC(makeFLAC(comments: ["VENDORKEY": "keep"], frames: frames))

        #expect(try FLACMetadata.embed(fileURL: url, tags: tags, artworkJPEG: fakeJPEG) == true)

        let comments = try FLACMetadata.readComments(fileURL: url)
        #expect(comments["TITLE"] == "Song")
        #expect(comments["ARTIST"] == "Artist")
        #expect(comments["ALBUM"] == "Album")
        #expect(comments["ALBUMARTIST"] == "Album Artist")
        #expect(comments["TRACKNUMBER"] == "7")
        #expect(comments["DATE"] == "2026")
        #expect(comments["ISRC"] == "ABCDE2600001")
        // Unknown existing comments survive the rewrite.
        #expect(comments["VENDORKEY"] == "keep")

        let written = try Data(contentsOf: url)
        #expect(written.suffix(frames.count) == frames)
        #expect(try FLACMetadata.readPicture(fileURL: url) == fakeJPEG)
    }

    @Test("existing fields are replaced, not duplicated")
    func embedReplacesFields() throws {
        let url = try temporaryFLAC(makeFLAC(comments: ["TITLE": "Old", "ARTIST": "Old Artist"]))
        let newTags = FLACMetadata.Tags(title: "New", artist: nil)

        #expect(try FLACMetadata.embed(fileURL: url, tags: newTags, artworkJPEG: nil) == true)

        let comments = try FLACMetadata.readComments(fileURL: url)
        #expect(comments["TITLE"] == "New")
        #expect(comments["ARTIST"] == "Old Artist")
    }

    @Test("padding is removed and STREAMINFO and SEEKTABLE are preserved")
    func structuralBlocks() throws {
        let seekTable = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12])
        let original = makeFLAC(seekTable: seekTable, padding: 64)
        let url = try temporaryFLAC(original)

        #expect(try FLACMetadata.embed(fileURL: url, tags: tags, artworkJPEG: fakeJPEG) == true)

        let written = try Data(contentsOf: url)
        // STREAMINFO payload (34 bytes after its 4-byte header) is byte-identical.
        let streamInfoStart = 8
        #expect(written.subdata(in: streamInfoStart..<streamInfoStart + 34) == original.subdata(in: streamInfoStart..<streamInfoStart + 34))
        // SEEKTABLE appears unchanged somewhere in the rewritten file.
        #expect(written.range(of: seekTable) != nil)
        // No padding block survives: a padding block's payload would be zeros
        // longer than the frames, and the block type 1 header is gone.
        var position = 4
        while true {
            let header = written[position]
            let type = header & 0x7F
            #expect(type != 1, "padding block must be dropped")
            let length = Int(written[position + 1]) << 16 | Int(written[position + 2]) << 8 | Int(written[position + 3])
            if header & 0x80 != 0 { break }
            position += 4 + length
        }
    }

    @Test("the audio region hash is unchanged after a rewrite")
    func audioRegionIntegrity() throws {
        let frames = Data((0..<128).map { UInt8($0 % 251) })
        let original = makeFLAC(frames: frames)
        let url = try temporaryFLAC(original)
        let originalData = try Data(contentsOf: url)
        let originalHash = SHA256.digest(originalData.suffix(frames.count))

        #expect(try FLACMetadata.embed(fileURL: url, tags: tags, artworkJPEG: fakeJPEG) == true)

        let rewritten = try Data(contentsOf: url)
        #expect(SHA256.digest(rewritten.suffix(frames.count)) == originalHash)
    }

    @Test("an oversize picture is rejected and the file is untouched")
    func oversizePicture() throws {
        let url = try temporaryFLAC(makeFLAC())
        let original = try Data(contentsOf: url)
        let oversize = fakeJPEG + Data(count: FLACMetadata.maxPictureBytes)

        #expect(throws: FLACMetadataError.pictureTooLarge) {
            try FLACMetadata.embed(fileURL: url, tags: nil, artworkJPEG: oversize)
        }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test("a non-JPEG picture is rejected")
    func nonJPEGPicture() throws {
        let url = try temporaryFLAC(makeFLAC())
        #expect(throws: FLACMetadataError.pictureNotJPEG) {
            try FLACMetadata.embed(fileURL: url, tags: nil, artworkJPEG: Data([0x89, 0x50, 0x4E, 0x47]))
        }
    }

    @Test("a picture replaces the previous cover")
    func pictureReplace() throws {
        let oldCover = fakeJPEG + Data([0x01])
        let url = try temporaryFLAC(makeFLAC(pictureJPEG: oldCover))

        #expect(try FLACMetadata.embed(fileURL: url, tags: nil, artworkJPEG: fakeJPEG) == true)
        #expect(try FLACMetadata.readPicture(fileURL: url) == fakeJPEG)
    }

    @Test("a corrupt header is rejected and the file is untouched")
    func corruptHeader() throws {
        var corrupt = makeFLAC()
        corrupt[2] = 0x58 // fLaX
        let url = try temporaryFLAC(corrupt)
        let original = try Data(contentsOf: url)

        #expect(!FLACMetadata.isFLAC(fileURL: url))
        #expect(try FLACMetadata.embed(fileURL: url, tags: tags, artworkJPEG: nil) == false)
        #expect(try Data(contentsOf: url) == original)
    }

    @Test("truncated metadata is rejected")
    func truncatedMetadata() throws {
        let full = makeFLAC()
        let url = try temporaryFLAC(full.prefix(full.count - 10))

        #expect(throws: FLACMetadataError.corrupt) {
            try FLACMetadata.embed(fileURL: url, tags: tags, artworkJPEG: nil)
        }
    }

    @Test("missing STREAMINFO is treated as corrupt")
    func missingStreamInfo() throws {
        var broken = makeFLAC()
        // Clear the first block type so it no longer reads as STREAMINFO.
        broken[4] = 0x80 | 2
        let url = try temporaryFLAC(broken)

        #expect(throws: FLACMetadataError.corrupt) {
            try FLACMetadata.readComments(fileURL: url)
        }
    }

    @Test("a non-FLAC file returns false and is left alone")
    func nonFLAC() throws {
        let url = try temporaryFLAC(Data([0x49, 0x44, 0x33, 0x03, 0x00, 0x00]))
        let original = try Data(contentsOf: url)

        #expect(!FLACMetadata.isFLAC(fileURL: url))
        #expect(try FLACMetadata.embed(fileURL: url, tags: tags, artworkJPEG: fakeJPEG) == false)
        #expect(try Data(contentsOf: url) == original)
    }
}

@Suite("SHA256")
struct SHA256Tests {
    @Test("known vectors")
    func vectors() {
        func hex(_ data: Data) -> String {
            data.map { String(format: "%02x", $0) }.joined()
        }
        #expect(hex(SHA256.digest(Data())) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(hex(SHA256.digest(Data("abc".utf8))) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(hex(SHA256.digest(Data(repeating: UInt8(0x61), count: 1_000_000)))
            == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }
}
