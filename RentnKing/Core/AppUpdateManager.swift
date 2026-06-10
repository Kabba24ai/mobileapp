//
//  AppUpdateManager.swift
//  Operations
//
//  Created by DEEPAK JAIN on 11/05/26.
//

import UIKit

final class AppUpdateManager {

    static let shared = AppUpdateManager()

    private init() {}

    // MARK: - Check App Update

    func checkForUpdate() {

        guard let bundleID = Bundle.main.bundleIdentifier else {
            return
        }

        let urlString = "https://itunes.apple.com/lookup?bundleId=\(bundleID)" //FOR TESTING ONLY// &country=sa

        guard let url = URL(string: urlString) else {
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in

            guard let data = data else {
                return
            }

            do {

                let result = try JSONDecoder().decode(AppStoreResult.self, from: data)

                guard let appStoreVersion = result.results.first?.version else {
                    return
                }

                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

                print("Current Version:", currentVersion)
                print("App Store Version:", appStoreVersion)

                if currentVersion.compareVersion(appStoreVersion) == .orderedAscending {

                    DispatchQueue.main.async {
                        self.showUpdateAlert()
                    }
                }

            } catch {
                print("Version Check Error:", error.localizedDescription)
            }

        }.resume()
    }

    // MARK: - Update Alert

    private func showUpdateAlert() {

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene, let rootVC = scene.windows.first?.rootViewController else {
            return
        }

        let alert = UIAlertController(title: "Update available", message: "Please update your application with a new version to continue.", preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: "Update", style: .default, handler: { _ in
            
            guard let url = URL(string: self.appStoreURL()) else {
                return
            }

            UIApplication.shared.open(url)
        }))

        rootVC.present(alert, animated: true)
    }

    // MARK: - App Store URL

    private func appStoreURL() -> String {
        return "https://apps.apple.com/us/app/kabba-ai/id6751110122"
    }
    
}

// MARK: - Models

struct AppStoreResult: Codable {
    let results: [AppInfo]
}

struct AppInfo: Codable {
    let version: String
}

// MARK: - Version Compare

extension String {

    func compareVersion(_ version: String) -> ComparisonResult {
        return self.compare(version, options: .numeric)
    }
}
