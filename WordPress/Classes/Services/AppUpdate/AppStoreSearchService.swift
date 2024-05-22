import Foundation

struct AppStoreLookupResponse: Decodable {
    let results: [AppStoreInfo]

    struct AppStoreInfo: Decodable {
        let trackName: String
        let trackId: Int
        let trackViewUrl: String
        let version: String
        let releaseNotes: String
        let minimumOsVersion: String
        let currentVersionReleaseDate: Date

        func currentVersionHasBeenReleased(for days: Int) -> Bool {
            let secondsInDay: TimeInterval = 86_400
            let secondsSinceRelease = -currentVersionReleaseDate.timeIntervalSinceNow
            return secondsSinceRelease > Double(days) * secondsInDay
        }
    }
}

protocol AppStoreSearchProtocol {
    var appID: String { get }
    func lookup() async throws -> AppStoreLookupResponse
}

final class AppStoreSearchService: AppStoreSearchProtocol {
    private(set) var appID: String

    init(appID: String = AppConstants.itunesAppID) {
        self.appID = appID
    }

    func lookup() async throws -> AppStoreLookupResponse {
        guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(appID)") else {
            throw AppStoreSearchError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response: response)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AppStoreLookupResponse.self, from: data)
    }

    private func validate(response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else {
            return
        }
        guard (200..<400).contains(response.statusCode) else {
            throw AppStoreSearchError.unacceptableStatusCode(response.statusCode)
        }
    }
}

enum AppStoreSearchError: Error {
    case invalidURL
    case unacceptableStatusCode(_ statusCode: Int?)
}
