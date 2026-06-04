import Foundation

struct CompanyEventStreamBackoff {
    private(set) var delaySeconds: Int = 1
    let maxDelaySeconds: Int = 15

    var sleepDuration: Duration {
        .seconds(delaySeconds)
    }

    mutating func reset() {
        delaySeconds = 1
    }

    mutating func advance() {
        delaySeconds = min(delaySeconds * 2, maxDelaySeconds)
    }
}

func isExpectedCompanyEventStreamInterruption(_ error: Error) -> Bool {
    if error is CancellationError {
        return true
    }
    if let urlError = error as? URLError {
        switch urlError.code {
        case .cancelled, .networkConnectionLost, .timedOut:
            return true
        default:
            return false
        }
    }
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain {
        switch nsError.code {
        case NSURLErrorCancelled, NSURLErrorNetworkConnectionLost, NSURLErrorTimedOut:
            return true
        default:
            return false
        }
    }
    let message = error.localizedDescription
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    return message == "cancelled"
        || message == "canceled"
        || message.contains("network connection was lost")
        || message.contains("request timed out")
}
