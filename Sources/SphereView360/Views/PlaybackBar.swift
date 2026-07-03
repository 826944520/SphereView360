import SwiftUI

struct PlaybackBar: View {
    @ObservedObject var store: ViewerStore
    @State private var isScrubbing = false
    @State private var scrubTime: Double = 0

    var body: some View {
        HStack(spacing: 12) {
            Button {
                store.togglePlayback()
            } label: {
                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.white)
            .help(store.isPlaying ? "Pause" : "Play")

            Text(TimeFormatter.clockTime(isScrubbing ? scrubTime : store.currentTime))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 54, alignment: .trailing)

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

            Text(TimeFormatter.clockTime(store.duration))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 54, alignment: .leading)

            Button {
                store.isLooping.toggle()
            } label: {
                Image(systemName: "repeat")
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(store.isLooping ? .white : .white.opacity(0.38))
            .help("Loop")

            Image(systemName: "speaker.wave.2.fill")
                .foregroundStyle(.white.opacity(0.76))

            Slider(value: $store.volume, in: 0...1)
                .frame(width: 88)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 8))
    }
}

