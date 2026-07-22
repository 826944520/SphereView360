import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct MobileContentView: View {
    @ObservedObject var store: ViewerStore
    @State private var selectedVideoItem: PhotosPickerItem?
    @State private var isFileImporterPresented = false
    @State private var isImporting = false
    @State private var showURLSheet = false
    @State private var urlInput = ""

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if store.hasVideo {
                SceneKit360VideoView(player: store.player, resetID: store.viewResetID)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    MobileHeader(title: store.displayName, resetAction: store.requestViewReset)
                    Spacer()
                    MobilePlaybackBar(store: store)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            } else {
                MobileEmptyState(
                    selectedVideoItem: $selectedVideoItem,
                    openFilesAction: { isFileImporterPresented = true },
                    openURLAction: {
                        urlInput = ""
                        showURLSheet = true
                    }
                )
            }

            if isImporting || store.isBuffering {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .padding(18)
                    .background(.black.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .sheet(isPresented: $showURLSheet) {
            MobileURLInputSheet(urlInput: $urlInput) { input in
                openURL(input)
            }
        }
        .task(id: selectedVideoItem) {
            guard let selectedVideoItem else {
                return
            }

            await loadPhotosVideo(selectedVideoItem)
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: SupportedVideoTypes.openPanelTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .alert(
            "SphereView360",
            isPresented: Binding(
                get: { store.alertMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        store.alertMessage = nil
                    }
                }
            )
        ) {
            Button("OK") {
                store.alertMessage = nil
            }
        } message: {
            Text(store.alertMessage ?? "")
        }
    }

    @MainActor
    private func loadPhotosVideo(_ item: PhotosPickerItem) async {
        isImporting = true
        defer {
            isImporting = false
            selectedVideoItem = nil
        }

        do {
            guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                store.alertMessage = "Photos did not provide a playable video file."
                return
            }

            store.open(movie.url)
        } catch {
            store.alertMessage = error.localizedDescription
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else {
                return
            }

            let temporaryURL = try SharedVideoLoader.copyVideoToTemporaryLocation(url)
            store.open(temporaryURL)
        } catch {
            store.alertMessage = error.localizedDescription
        }
    }

    private func openURL(_ input: String) {
        showURLSheet = false
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        guard let url = URL(string: trimmed) else {
            store.alertMessage = "The URL \"\(trimmed)\" is not valid."
            return
        }
        store.open(url)
    }
}

private struct MobileHeader: View {
    let title: String
    let resetAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))

            Spacer()

            Button(action: resetAction) {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
    }
}

private struct MobileEmptyState: View {
    @Binding var selectedVideoItem: PhotosPickerItem?
    let openFilesAction: () -> Void
    let openURLAction: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "view.3d")
                .font(.system(size: 52, weight: .regular))
                .foregroundStyle(.white.opacity(0.92))

            VStack(spacing: 6) {
                Text("Open a 360 video")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Equirectangular MP4, MOV, M4V, INSV, or a remote URL")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.68))
            }

            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedVideoItem, matching: .videos) {
                    Label("Photos", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.borderedProminent)

                Button(action: openFilesAction) {
                    Label("Files", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }

            Button(action: openURLAction) {
                Label("URL", systemImage: "globe")
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
        .padding(26)
    }
}

private struct MobilePlaybackBar: View {
    @ObservedObject var store: ViewerStore
    @State private var isScrubbing = false
    @State private var scrubTime: Double = 0

    var body: some View {
        HStack(spacing: 10) {
            Button {
                store.togglePlayback()
            } label: {
                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .tint(.white)

            Text(TimeFormatter.clockTime(isScrubbing ? scrubTime : store.currentTime))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 48, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubTime : store.currentTime },
                    set: { newValue in
                        scrubTime = newValue
                    }
                ),
                in: 0...max(store.duration, 1),
                onEditingChanged: { editing in
                    isScrubbing = editing
                    if !editing {
                        store.seek(to: scrubTime)
                    }
                }
            )
            .tint(.white)

            Text(TimeFormatter.clockTime(store.duration))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 48, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copiedURL = try SharedVideoLoader.copyVideoToTemporaryLocation(received.file)
            return PickedMovie(url: copiedURL)
        }
    }
}

private struct MobileURLInputSheet: View {
    @Binding var urlInput: String
    let onOpen: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Enter a remote 360 video URL")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                TextField("https://example.com/video.mp4", text: $urlInput)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding(.horizontal)
            }
            .padding(.top, 28)
            .navigationTitle("Open URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open") {
                        onOpen(urlInput)
                        dismiss()
                    }
                    .disabled(urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
