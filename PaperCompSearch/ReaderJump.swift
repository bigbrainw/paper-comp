import Foundation

/// Search-card → PDF hops. The reader’s `PDFView` observes this.
enum ReaderJump {
    static let notification = Notification.Name("papercomp.reader.jump")
    static let pageKey = "pageIndex"
    static let queryKey = "query"

    static func page(_ index: Int) {
        NotificationCenter.default.post(name: notification, object: nil, userInfo: [pageKey: index])
    }

    static func search(_ query: String) {
        NotificationCenter.default.post(name: notification, object: nil, userInfo: [queryKey: query])
    }

    static func referencesSection() {
        search("References")
    }
}
