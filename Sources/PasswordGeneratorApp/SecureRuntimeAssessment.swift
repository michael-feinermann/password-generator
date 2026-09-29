import Darwin
import Foundation
import Security

/// Verifies the protections that must be active before secret generation is allowed.
/// This is a fail-closed runtime gate, not a claim that the host operating system is trusted.
struct SecureRuntimeAssessment: Equatable, Sendable {
    let appSandboxEnabled: Bool
    let entitlementsMinimized: Bool
    let codeSignatureValid: Bool
    let hardenedRuntimeEnabled: Bool
    let debuggerAbsent: Bool
    let coreDumpsDisabled: Bool

    var isEnforced: Bool {
        appSandboxEnabled
            && entitlementsMinimized
            && codeSignatureValid
            && hardenedRuntimeEnabled
            && debuggerAbsent
            && coreDumpsDisabled
    }

    static func current() -> SecureRuntimeAssessment {
        let coreDumpsDisabled = disableCoreDumps()

        guard let task = SecTaskCreateFromSelf(nil) else {
            return failedExceptForCoreDumpState(coreDumpsDisabled)
        }
        let effectiveSandbox = entitlementIsTrue(
            "com.apple.security.app-sandbox",
            task: task
        )

        var dynamicCode: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &dynamicCode) == errSecSuccess,
              let dynamicCode
        else {
            return SecureRuntimeAssessment(
                appSandboxEnabled: effectiveSandbox,
                entitlementsMinimized: false,
                codeSignatureValid: false,
                hardenedRuntimeEnabled: false,
                debuggerAbsent: false,
                coreDumpsDisabled: coreDumpsDisabled
            )
        }

        let signatureIsValid = SecCodeCheckValidity(
            dynamicCode,
            SecCSFlags(),
            nil
        ) == errSecSuccess

        // The C API explicitly accepts a dynamic SecCodeRef here. Swift imports the
        // parameter as SecStaticCode, so this bridge preserves the documented object.
        let signingInformationCode: SecStaticCode = unsafeBitCast(
            dynamicCode,
            to: SecStaticCode.self
        )
        var information: CFDictionary?
        let informationStatus = SecCodeCopySigningInformation(
            signingInformationCode,
            SecCSFlags(rawValue: kSecCSDynamicInformation),
            &information
        )
        guard informationStatus == errSecSuccess,
              let dictionary = information as NSDictionary?
        else {
            return SecureRuntimeAssessment(
                appSandboxEnabled: effectiveSandbox,
                entitlementsMinimized: false,
                codeSignatureValid: false,
                hardenedRuntimeEnabled: false,
                debuggerAbsent: false,
                coreDumpsDisabled: coreDumpsDisabled
            )
        }

        let signatureFlagsRaw = (dictionary[kSecCodeInfoFlags] as? NSNumber)?.uint32Value ?? 0
        let signatureFlags = SecCodeSignatureFlags(rawValue: signatureFlagsRaw)
        let statusRaw = (dictionary[kSecCodeInfoStatus] as? NSNumber)?.uint32Value ?? 0
        let dynamicStatus = SecCodeStatus(rawValue: statusRaw)
        let entitlements = dictionary[kSecCodeInfoEntitlementsDict] as? [String: Any]

        return SecureRuntimeAssessment(
            appSandboxEnabled: effectiveSandbox,
            entitlementsMinimized: hasOnlyAllowedEntitlements(entitlements),
            codeSignatureValid: signatureIsValid && dynamicStatus.contains(.valid),
            hardenedRuntimeEnabled: signatureFlags.contains(.runtime)
                && dynamicStatus.contains(.hard)
                && dynamicStatus.contains(.kill),
            debuggerAbsent: !dynamicStatus.contains(.debugged),
            coreDumpsDisabled: coreDumpsDisabled
        )
    }

    private static func entitlementIsTrue(_ name: String, task: SecTask) -> Bool {
        SecTaskCopyValueForEntitlement(task, name as CFString, nil) as? Bool == true
    }

    private static func hasOnlyAllowedEntitlements(_ entitlements: [String: Any]?) -> Bool {
        guard let entitlements,
              entitlements["com.apple.security.app-sandbox"] as? Bool == true
        else {
            return false
        }

        // The two identity keys may be added by a future Developer-ID distribution.
        // Every capability-bearing entitlement remains forbidden for this app.
        let allowedKeys: Set<String> = [
            "com.apple.security.app-sandbox",
            "com.apple.application-identifier",
            "com.apple.developer.team-identifier"
        ]
        return Set(entitlements.keys).isSubset(of: allowedKeys)
    }

    private static func disableCoreDumps() -> Bool {
        var zeroLimit = rlimit(rlim_cur: 0, rlim_max: 0)
        guard setrlimit(RLIMIT_CORE, &zeroLimit) == 0 else { return false }

        var verifiedLimit = rlimit()
        guard getrlimit(RLIMIT_CORE, &verifiedLimit) == 0 else { return false }
        return verifiedLimit.rlim_cur == 0 && verifiedLimit.rlim_max == 0
    }

    private static func failedExceptForCoreDumpState(
        _ coreDumpsDisabled: Bool
    ) -> SecureRuntimeAssessment {
        SecureRuntimeAssessment(
            appSandboxEnabled: false,
            entitlementsMinimized: false,
            codeSignatureValid: false,
            hardenedRuntimeEnabled: false,
            debuggerAbsent: false,
            coreDumpsDisabled: coreDumpsDisabled
        )
    }
}
