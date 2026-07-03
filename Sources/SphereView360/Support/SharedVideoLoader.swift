@preconcurrency import Foundation
import UniformTypeIdentifiers

enum SharedVideoLoader {
    typealias LoadCompletion = (Result<URL, Error>) -> Void

    private final class Candidate: @unchecked Sendable {
        let provider: NSItemProvider
        let typeIdentifier: String
        let suggestedName: String?

        init(provider: NSItemProvider, typeIdentifier: String) {
            self.provider = provider
            self.typeIdentifier = typeIdentifier
            suggestedName = provider.suggestedName
        }
    }

    private final class LoadState: @unchecked Sendable {
        let candidates: [Candidate]
        let completion: LoadCompletion

        init(candidates: [Candidate], completion: @escaping LoadCompletion) {
            self.candidates = candidates
            self.completion = completion
        }
    }

    enum LoaderError: LocalizedError {
        case noVideoAttachment
        case unsupportedItem

        var errorDescription: String? {
            switch self {
            case .noVideoAttachment:
                return "No shared video was found."
            case .unsupportedItem:
                return "The shared item could not be opened as a video file."
            }
        }
    }

    static var acceptedTypeIdentifiers: [String] {
        var identifiers = [
            UTType.movie.identifier,
            UTType.mpeg4Movie.identifier,
            UTType.quickTimeMovie.identifier,
            UTType.fileURL.identifier
        ]

        if let m4v = UTType(filenameExtension: "m4v")?.identifier {
            identifiers.append(m4v)
        }

        if let insta360 = UTType(filenameExtension: "insv")?.identifier {
            identifiers.append(insta360)
        }

        return identifiers
    }

    static func loadFirstVideoURL(
        from extensionContext: NSExtensionContext?,
        completion: @escaping LoadCompletion
    ) {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []

        loadFirstVideoURL(from: providers, completion: completion)
    }

    static func loadFirstVideoURL(
        from providers: [NSItemProvider],
        completion: @escaping LoadCompletion
    ) {
        let candidates: [Candidate] = providers.flatMap { provider in
            acceptedTypeIdentifiers.compactMap { identifier in
                provider.hasItemConformingToTypeIdentifier(identifier)
                    ? Candidate(provider: provider, typeIdentifier: identifier)
                    : nil
            }
        }

        guard !candidates.isEmpty else {
            completion(.failure(LoaderError.noVideoAttachment))
            return
        }

        loadFirstWorkingCandidate(LoadState(candidates: candidates, completion: completion), index: 0)
    }

    static func copyVideoToTemporaryLocation(_ sourceURL: URL, preferredFilename: String? = nil) throws -> URL {
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let rawBaseName = preferredFilename ?? sourceURL.deletingPathExtension().lastPathComponent
        let baseName = rawBaseName.isEmpty ? "SphereView360Video" : rawBaseName
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(baseName)-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)

        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        return destination
    }

    private static func loadFirstWorkingCandidate(
        _ state: LoadState,
        index: Int
    ) {
        guard index < state.candidates.count else {
            state.completion(.failure(LoaderError.unsupportedItem))
            return
        }

        let candidate = state.candidates[index]
        let provider = candidate.provider
        let typeIdentifier = candidate.typeIdentifier

        if typeIdentifier == UTType.fileURL.identifier {
            loadItemURL(from: candidate, state: state, index: index)
            return
        }

        provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
            if let url {
                do {
                    let copiedURL = try copyVideoToTemporaryLocation(url, preferredFilename: candidate.suggestedName)
                    state.completion(.success(copiedURL))
                } catch {
                    handleCandidateResult(
                        .failure(error),
                        state: state,
                        index: index,
                    )
                }
                return
            }

            if let error {
                handleCandidateResult(
                    .failure(error),
                    state: state,
                    index: index,
                )
                return
            }

            loadItemURL(from: candidate, state: state, index: index)
        }
    }

    private static func loadItemURL(
        from candidate: Candidate,
        state: LoadState,
        index: Int
    ) {
        candidate.provider.loadItem(forTypeIdentifier: candidate.typeIdentifier, options: nil) { item, error in
            if let error {
                handleCandidateResult(.failure(error), state: state, index: index)
                return
            }

            do {
                let url = try temporaryURL(from: item, suggestedName: candidate.suggestedName)
                handleCandidateResult(.success(url), state: state, index: index)
            } catch {
                handleCandidateResult(.failure(error), state: state, index: index)
            }
        }
    }

    private static func temporaryURL(from item: NSSecureCoding?, suggestedName: String?) throws -> URL {
        if let url = item as? URL {
            return try copyVideoToTemporaryLocation(url, preferredFilename: suggestedName)
        }

        if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
            return try copyVideoToTemporaryLocation(url, preferredFilename: suggestedName)
        }

        if let data = item as? Data {
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(suggestedName ?? "SphereView360Video")-\(UUID().uuidString)")
                .appendingPathExtension("mov")

            try data.write(to: destination, options: .atomic)
            return destination
        }

        throw LoaderError.unsupportedItem
    }

    private static func handleCandidateResult(
        _ result: Result<URL, Error>,
        state: LoadState,
        index: Int
    ) {
        switch result {
        case .success(let url):
            state.completion(.success(url))
        case .failure:
            loadFirstWorkingCandidate(state, index: index + 1)
        }
    }
}
