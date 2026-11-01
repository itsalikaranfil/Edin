//
//  LegalURLs.swift
//  One
//
//  Central URLs for Terms of Use and Privacy Policy (Guideline 3.1.2(c)).
//

import Foundation

enum LegalURLs {
    static let termsOfUse = URL(string: "https://www.notion.so/Terms-of-Service-for-One-31a84999cf38805fb589e188e1b7c0c1?source=copy_link")!
    static let privacyPolicy = URL(string: "https://www.notion.so/Privacy-Policy-for-One-31a84999cf38800383ebf9000759f3ce?source=copy_link")!

    /// Use in App Store Connect App Description or EULA field (same document as in-app Terms link).
    static let termsOfUseForAppStoreMetadata = "https://www.notion.so/Terms-of-Service-for-One-31a84999cf38805fb589e188e1b7c0c1"

    /// Use in App Store Connect Privacy Policy URL field (same as in-app Privacy link).
    static let privacyPolicyForAppStoreMetadata = "https://www.notion.so/Privacy-Policy-for-One-31a84999cf38800383ebf9000759f3ce"
}
