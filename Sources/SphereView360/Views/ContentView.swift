import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: ViewerStore
    @State private var isDropTargeted = false
    @State private var showURLSheet = false
    @State private var urlInput = ""

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if store.hasVideo {
                SceneKit360VideoView(player: store.player, resetID: store.viewResetID)
                    .ignoresSafeArea()
            } else {
                EmptyStateView {
                    store.presentOpenPanel()
                } makeDefaultAction: {
                    store.registerOpenWithOption()
                }
            }

            if store.hasVideo {
                VStack(spacing: 0) {
                    HeaderOverlay(title: store.displayName)
                    Spacer()
                    PlaybackBar(store: store)
                }
                .padding(16)
            }

            if isDropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                    .background(.black.opacity(0.18))
                    .padding(18)
            }

            if store.isBuffering {
                ProgressView()
                    .scaleEffect(1.2)
                    .frame(width: 64, height: 64)
                    .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    store.presentOpenPanel()
                } label: {
                    Label("Open Video", systemImage: "folder")
                }

                Button {
                    store.requestViewReset()
                } label: {
                    Label("Reset View", systemImage: "arrow.counterclockwise")
                }
                .disabled(!store.hasVideo)

                Button {
                    store.registerOpenWithOption()
                } label: {
                    Label("Add to Open With", systemImage: "doc.badge.gearshape")
                }

                Button {
                    urlInput = ""
                    showURLSheet = true
                } label: {
                    Label("Open URL", systemImage: "globe")
                }
            }
        }
        .onDrop(
            of: SupportedVideoTypes.dropTypeIdentifiers,
            isTargeted: $isDropTargeted,
            perform: handleDrop(providers:)
        )
        .onReceive(NotificationCenter.default.publisher(for: .sphereViewPromptURL)) { _ in
            urlInput = ""
            showURLSheet = true
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
        .sheet(isPresented: $showURLSheet) {
            URLInputSheet(urlInput: $urlInput) { input in
                openURL(input)
            }
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

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { provider in
            provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?

            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = item as? URL
            }

            guard let url else {
                return
            }

            Task { @MainActor in
                store.open(url)
            }
        }

        return true
    }
}

private struct HeaderOverlay: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))

            Spacer()
        }
    }
}

private struct EmptyStateView: View {
    let openAction: () -> Void
    let makeDefaultAction: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "view.3d")
                .font(.system(size: 48, weight: .regular))
                .foregroundStyle(.white.opacity(0.92))

            VStack(spacing: 5) {
                Text("Drop a 360 video")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                Text("Equirectangular MP4, MOV, M4V, and compatible INSV files")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.68))
            }

            HStack(spacing: 10) {
                Button {
                    openAction()
                } label: {
                    Label("Open Video", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    makeDefaultAction()
                } label: {
                    Label("Add to Open With", systemImage: "doc.badge.gearshape")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(28)
    }
}

private struct URLInputSheet: View {
    @Binding var urlInput: String
    let onOpen: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Open Remote Video")
                .font(.headline)

            TextField("https://example.com/video.mp4", text: $urlInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 420)
                .onSubmit {
                    onOpen(urlInput)
                    dismiss()
                }

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }

                Button("Open") {
                    onOpen(urlInput)
                    dismiss()
                }
                .keyboardShortcut(.return)
                .disabled(urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(28)
        .frame(width: 480)
    }
}
