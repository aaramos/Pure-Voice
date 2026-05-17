import AppKit
import Foundation
import PureVoiceCore

enum GitHubUpdaterError: LocalizedError {
    case invalidResponse(Int)
    case missingDownloadedFile
    case unsupportedAsset(String)
    case missingMountedVolume
    case missingAppBundle
    case invalidBundleIdentifier(String?)
    case processFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let statusCode):
            return "GitHub update check failed with HTTP \(statusCode)."
        case .missingDownloadedFile:
            return "The update download did not produce a local file."
        case .unsupportedAsset(let name):
            return "Pure Voice can only install update assets packaged as a DMG or zip. The latest asset was \(name)."
        case .missingMountedVolume:
            return "Pure Voice could not mount the downloaded update disk image."
        case .missingAppBundle:
            return "Pure Voice could not find an app bundle inside the downloaded update."
        case .invalidBundleIdentifier(let identifier):
            return "The downloaded update is not a Pure Voice app bundle. Bundle identifier: \(identifier ?? "missing")."
        case .processFailed(let message):
            return message
        }
    }
}

struct GitHubReleaseClient {
    var owner = "aaramos"
    var repository = "Pure-Voice"

    func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.setValue("PureVoice-Updater", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw GitHubUpdaterError.invalidResponse(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }
}

struct GitHubUpdateInstaller {
    func downloadAndPrepareInstall(_ updateInfo: AppUpdateInfo) async throws {
        let downloadedAsset = try await download(updateInfo.assetURL, assetName: updateInfo.assetName)
        let stagedApp = try stageApp(from: downloadedAsset, assetName: updateInfo.assetName)
        let currentApp = Bundle.main.bundleURL
        let script = try writeInstallScript()
        try runDetachedInstaller(script: script, currentApp: currentApp, stagedApp: stagedApp)
    }

    private func download(_ url: URL, assetName: String) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("PureVoice-Updater", forHTTPHeaderField: "User-Agent")
        let (downloadURL, response) = try await URLSession.shared.download(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw GitHubUpdaterError.invalidResponse(httpResponse.statusCode)
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("PureVoiceUpdate-\(UUID().uuidString)")
            .appendingPathComponent(assetName)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: downloadURL, to: destination)
        return destination
    }

    private func stageApp(from assetURL: URL, assetName: String) throws -> URL {
        if assetName.localizedCaseInsensitiveContains(".dmg") {
            return try stageAppFromDMG(assetURL)
        }

        if assetName.localizedCaseInsensitiveContains(".zip") {
            return try stageAppFromZip(assetURL)
        }

        throw GitHubUpdaterError.unsupportedAsset(assetName)
    }

    private func stageAppFromDMG(_ dmgURL: URL) throws -> URL {
        let output = try runProcess(
            executable: "/usr/bin/hdiutil",
            arguments: ["attach", dmgURL.path, "-nobrowse", "-readonly", "-plist"]
        )
        let plist = try PropertyListSerialization.propertyList(from: output, options: [], format: nil)
        guard
            let dictionary = plist as? [String: Any],
            let entities = dictionary["system-entities"] as? [[String: Any]],
            let mountPoint = entities.compactMap({ $0["mount-point"] as? String }).first
        else {
            throw GitHubUpdaterError.missingMountedVolume
        }

        let mountedURL = URL(fileURLWithPath: mountPoint)
        defer {
            _ = try? runProcess(
                executable: "/usr/bin/hdiutil",
                arguments: ["detach", mountedURL.path, "-quiet"]
            )
        }

        let appURL = try findAppBundle(in: mountedURL)
        return try copyToStaging(appURL)
    }

    private func stageAppFromZip(_ zipURL: URL) throws -> URL {
        let extractionRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PureVoiceExtract-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: extractionRoot, withIntermediateDirectories: true)
        try runProcess(
            executable: "/usr/bin/ditto",
            arguments: ["-x", "-k", zipURL.path, extractionRoot.path]
        )

        let appURL = try findAppBundle(in: extractionRoot)
        return try copyToStaging(appURL)
    }

    private func findAppBundle(in root: URL) throws -> URL {
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .nameKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            throw GitHubUpdaterError.missingAppBundle
        }

        for case let candidate as URL in enumerator {
            if candidate.pathExtension == "app" {
                return candidate
            }
        }

        throw GitHubUpdaterError.missingAppBundle
    }

    private func copyToStaging(_ appURL: URL) throws -> URL {
        let stagingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PureVoiceStaged-\(UUID().uuidString)")
        let stagedApp = stagingRoot.appendingPathComponent(appURL.lastPathComponent)
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        try runProcess(
            executable: "/usr/bin/ditto",
            arguments: [appURL.path, stagedApp.path]
        )
        try validateStagedApp(stagedApp)
        return stagedApp
    }

    private func validateStagedApp(_ appURL: URL) throws {
        let bundle = Bundle(url: appURL)
        let bundleIdentifier = bundle?.bundleIdentifier
        guard bundleIdentifier == "com.adrian.purevoice" else {
            throw GitHubUpdaterError.invalidBundleIdentifier(bundleIdentifier)
        }

        try runProcess(
            executable: "/usr/bin/codesign",
            arguments: ["--verify", "--deep", "--strict", appURL.path]
        )
    }

    private func writeInstallScript() throws -> URL {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("purevoice-install-update-\(UUID().uuidString).zsh")
        let contents = """
        #!/bin/zsh
        set -euo pipefail

        CURRENT_PID="$1"
        CURRENT_APP="$2"
        STAGED_APP="$3"

        while kill -0 "$CURRENT_PID" 2>/dev/null; do
          sleep 0.2
        done

        rm -rf "$CURRENT_APP"
        /usr/bin/ditto "$STAGED_APP" "$CURRENT_APP"
        /usr/bin/xattr -dr com.apple.quarantine "$CURRENT_APP" 2>/dev/null || true
        /usr/bin/open -n "$CURRENT_APP"
        """

        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    private func runDetachedInstaller(script: URL, currentApp: URL, stagedApp: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            script.path,
            "\(ProcessInfo.processInfo.processIdentifier)",
            currentApp.path,
            stagedApp.path
        ]
        try process.run()
    }

    @discardableResult
    private func runProcess(executable: String, arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = error.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitHubUpdaterError.processFailed(message?.isEmpty == false ? message! : "\(executable) failed.")
        }

        return output.fileHandleForReading.readDataToEndOfFile()
    }
}
