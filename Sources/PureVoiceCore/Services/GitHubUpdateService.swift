import Foundation

public struct AppVersion: Comparable, Equatable, Sendable {
    public var rawValue: String
    private var components: [Int]

    public init(_ rawValue: String) {
        self.rawValue = rawValue
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
            ? String(trimmed.dropFirst())
            : trimmed
        self.components = normalized
            .split { character in
                character == "." || character == "-" || character == "+"
            }
            .map { Int($0) ?? 0 }
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }
}

public struct GitHubReleaseAsset: Decodable, Equatable, Sendable {
    public var name: String
    public var browserDownloadURL: URL
    public var contentType: String?

    public init(name: String, browserDownloadURL: URL, contentType: String? = nil) {
        self.name = name
        self.browserDownloadURL = browserDownloadURL
        self.contentType = contentType
    }

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case contentType = "content_type"
    }
}

public struct GitHubRelease: Decodable, Equatable, Sendable {
    public var tagName: String
    public var name: String?
    public var htmlURL: URL
    public var assets: [GitHubReleaseAsset]
    public var draft: Bool
    public var prerelease: Bool

    public init(
        tagName: String,
        name: String? = nil,
        htmlURL: URL,
        assets: [GitHubReleaseAsset],
        draft: Bool = false,
        prerelease: Bool = false
    ) {
        self.tagName = tagName
        self.name = name
        self.htmlURL = htmlURL
        self.assets = assets
        self.draft = draft
        self.prerelease = prerelease
    }

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case htmlURL = "html_url"
        case assets
        case draft
        case prerelease
    }
}

public struct AppUpdateInfo: Equatable, Sendable {
    public var currentVersion: String
    public var latestVersion: String
    public var releaseName: String
    public var releaseURL: URL
    public var assetName: String
    public var assetURL: URL

    public init(
        currentVersion: String,
        latestVersion: String,
        releaseName: String,
        releaseURL: URL,
        assetName: String,
        assetURL: URL
    ) {
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.releaseName = releaseName
        self.releaseURL = releaseURL
        self.assetName = assetName
        self.assetURL = assetURL
    }
}

public enum GitHubUpdateService {
    public static func updateInfo(currentVersion: String, latestRelease: GitHubRelease) -> AppUpdateInfo? {
        guard !latestRelease.draft, !latestRelease.prerelease else {
            return nil
        }

        let latestVersion = latestRelease.tagName
        guard AppVersion(currentVersion) < AppVersion(latestVersion) else {
            return nil
        }

        guard let asset = preferredInstallAsset(from: latestRelease.assets) else {
            return nil
        }

        return AppUpdateInfo(
            currentVersion: currentVersion,
            latestVersion: latestVersion,
            releaseName: latestRelease.name ?? latestRelease.tagName,
            releaseURL: latestRelease.htmlURL,
            assetName: asset.name,
            assetURL: asset.browserDownloadURL
        )
    }

    public static func preferredInstallAsset(from assets: [GitHubReleaseAsset]) -> GitHubReleaseAsset? {
        assets.first { asset in
            asset.name.localizedCaseInsensitiveContains(".dmg")
        } ?? assets.first { asset in
            asset.name.localizedCaseInsensitiveContains(".zip")
        }
    }
}
