import Foundation
import UniformTypeIdentifiers

enum SupportedVideoTypes {
    struct ContentType: Identifiable {
        let id: String
        let filenameExtension: String
        let displayName: String
    }

    static let filenameExtensions: Set<String> = [
        "mp4",
        "m4v",
        "mov",
        "insv"
    ]

    static let defaultOpenContentTypes: [ContentType] = [
        ContentType(id: "public.mpeg-4", filenameExtension: "mp4", displayName: "MP4"),
        ContentType(id: "com.apple.m4v-video", filenameExtension: "m4v", displayName: "M4V"),
        ContentType(id: "com.apple.quicktime-movie", filenameExtension: "mov", displayName: "MOV"),
        ContentType(id: "dev.local.insv", filenameExtension: "insv", displayName: "INSV")
    ]

    static var openPanelTypes: [UTType] {
        var types: [UTType] = [
            .movie,
            .mpeg4Movie,
            .quickTimeMovie
        ]

        if let m4v = UTType(filenameExtension: "m4v") {
            types.append(m4v)
        }

        if let insta360 = UTType(filenameExtension: "insv") {
            types.append(insta360)
        }

        return types
    }

    static var dropTypeIdentifiers: [String] {
        [
            UTType.fileURL.identifier
        ]
    }

    static func isHTTPVideoURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }

    static func isLikelyVideo(_ url: URL) -> Bool {
        if isHTTPVideoURL(url) {
            return true
        }

        let fileExtension = url.pathExtension.lowercased()
        guard !fileExtension.isEmpty else {
            return false
        }

        if filenameExtensions.contains(fileExtension) {
            return true
        }

        return UTType(filenameExtension: fileExtension)?.conforms(to: .movie) == true
    }
}
