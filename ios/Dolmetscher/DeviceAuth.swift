// DeviceAuth.swift – Face ID / Touch ID / Gerätecode für den gesperrten Verlauf.
import LocalAuthentication

enum DeviceAuth {
    /// Kann das Gerät überhaupt sperren (Code gesetzt)? Sonst bietet die App die Sperre nicht an.
    static var available: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// Face ID mit Rückfall auf den Gerätecode. Ohne Code gesetzt: nichts zu schützen – entsperrt.
    static func authenticate(reason: String) async -> Bool {
        let ctx = LAContext()
        var error: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }
        return (try? await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}
