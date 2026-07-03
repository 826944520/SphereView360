import AppKit

enum VideoOpenPanel {
    @MainActor
    static func chooseVideo() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Open 360 Video"
        panel.message = "Choose an equirectangular 360 video."
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = SupportedVideoTypes.openPanelTypes

        return panel.runModal() == .OK ? panel.url : nil
    }
}

