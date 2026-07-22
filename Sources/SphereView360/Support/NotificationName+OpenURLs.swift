import Foundation

enum OpenURLNotification {
    static let urlsKey = "SphereView360.openURLs.urls"
}

extension Notification.Name {
    static let sphereViewOpenURLs = Notification.Name("SphereView360.openURLs")
    static let sphereViewPromptURL = Notification.Name("SphereView360.promptURL")
}

