import CoreServices
import Foundation

enum OpenWithRegistrationService {
    static func registerCurrentAppBundle() throws {
        let status = LSRegisterURL(Bundle.main.bundleURL as NSURL, true)
        guard status == noErr else {
            throw OpenWithRegistrationError.registrationFailed(status: status)
        }
    }
}

private enum OpenWithRegistrationError: LocalizedError {
    case registrationFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let status):
            return "macOS could not register SphereView360 as an Open With option. Status: \(status)."
        }
    }
}

