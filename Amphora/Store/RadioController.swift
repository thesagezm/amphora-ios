import Foundation
import Observation
import PandoraCore

/// Discovery state for the Radio tab: every radio-browser directory fetch
/// goes through here (AGENTS.md: no networking in SwiftUI views — the
/// views render this controller's state and dispatch playback intents to
/// `AppStore`). Shares one `RadioBrowserClient` with the store, so the
/// mirror rotation and the play-click ping see the same servers.
@MainActor
@Observable
final class RadioController {
    /// What the current `results` list represents — set by `show(_:)`.
    enum Mode: Equatable, Sendable {
        case popular
        case search(String)
        case country(code: String, name: String)
        case tag(String)

        var title: String {
            switch self {
            case .popular: return "Popular"
            case .search: return "Search"
            case .country(_, let name): return name.isEmpty ? "Stations" : name
            case .tag(let tag): return tag
            }
        }
    }

    /// The station list currently shown (search results at the tab root,
    /// or the pushed popular/country/tag list).
    private(set) var results: [RadioStation] = []
    /// True once any station load completed — distinguishes the initial
    /// spinner from a real "no results".
    private(set) var didLoadResults = false
    private(set) var activeMode: Mode?
    /// True while any directory request is in flight.
    private(set) var isLoading = false
    /// User-facing copy for the last failed load; nil when healthy.
    private(set) var errorMessage: String?
    /// The countries / tags catalogs — nil until first fetched this
    /// session (same fetch-once caching as the genre browse sheet).
    private(set) var countries: [RadioCountry]?
    private(set) var tags: [RadioTag]?

    /// Bound to the Radio tab's search field. Non-empty text switches the
    /// tab to search results (debounced — never hammer the directory);
    /// clearing it returns to the recents / favorites / discovery home.
    var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            searchTask?.cancel()
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return }
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                show(.search(query))
            }
        }
    }

    private let client: RadioBrowserClient
    private var loadTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    init(client: RadioBrowserClient = RadioBrowserClient()) {
        self.client = client
    }

    // MARK: Station lists

    /// Loads the station list for `mode`, replacing any in-flight load.
    func show(_ mode: Mode) {
        activeMode = mode
        let client = client
        run {
            switch mode {
            case .popular:
                self.results = try await client.topStations()
            case .search(let query):
                self.results = try await client.searchStations(name: query)
            case .country(let code, _):
                self.results = try await client.stations(countryCode: code)
            case .tag(let tag):
                self.results = try await client.stations(tag: tag)
            }
            self.didLoadResults = true
        }
    }

    // MARK: Catalogs

    func loadCountries() {
        guard countries == nil else { return }
        let client = client
        run { self.countries = try await client.countries() }
    }

    /// Clears the cached catalog and refetches (the error state's Retry).
    func retryCountries() {
        countries = nil
        loadCountries()
    }

    func loadTags() {
        guard tags == nil else { return }
        let client = client
        run { self.tags = try await client.tags() }
    }

    func retryTags() {
        tags = nil
        loadTags()
    }

    // MARK: Internals

    /// Runs one directory request against the shared loading/error
    /// state; a newer call cancels the older one.
    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        loadTask?.cancel()
        isLoading = true
        errorMessage = nil
        loadTask = Task {
            do {
                try await work()
            } catch {
                guard !Task.isCancelled else { return }
                // The typed error carries no URL material (status code
                // only), so logging the raw case is safe.
                AppLog.info("radio: directory request failed — \(error)", .network)
                errorMessage = Self.userMessage(for: error)
            }
            guard !Task.isCancelled else { return }
            isLoading = false
        }
    }

    private static func userMessage(for error: Error) -> String {
        switch error {
        case RadioBrowserError.httpStatus(let code):
            return "The radio directory returned an error (\(code))."
        case RadioBrowserError.badResponse:
            return "The radio directory sent an unexpected reply."
        case RadioBrowserError.networkFailure:
            return "Couldn't reach the radio directory. Check your connection."
        default:
            return "Couldn't load from the radio directory."
        }
    }
}
