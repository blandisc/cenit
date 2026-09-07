import Foundation

/// Every persisted `UserDefaults` key Cénit owns, in one place — and the one-time move off the
/// NOOP-era `noop.*` prefix (FER-398).
///
/// The keys used to be string literals scattered across nine files, frozen under `noop.` because
/// renaming them would have silently reset a live install: a new key reads as "never set", so the
/// user would land back on onboarding, re-accept the terms, lose their appearance choice and their
/// auto-backup folder. `PrefMigration` removes that risk by COPYING each legacy value onto the new
/// key at launch and only then deleting the old one, which is why the rename can finally happen.
///
/// Being an enum is the point: the migration iterates `allCases`, so a key added here can never be
/// forgotten by it. A literal in a view could.
enum PrefKey: String, CaseIterable {

    /// Which `UserDefaults` a key lives in.
    enum Suite: Equatable {
        /// The app's own defaults.
        case standard
        /// The shared App-Group suite (`AppGroup.sharedDefaults()`) — written by an extension and
        /// read by the app, or vice versa.
        case appGroup
    }

    // Onboarding + first-run gates.
    case onboarded = "cenit.onboarded"
    case acceptedTermsVersion = "cenit.acceptedTermsVersion"
    case apariencia = "cenit.apariencia"
    case didOfferRestore = "cenit.didOfferRestore"

    // Session comforts (FER-93).
    case sessionKeepScreenAwake = "cenit.session.keepScreenAwake"
    case sessionRestSound = "cenit.session.restSound"
    case sessionRestNotify = "cenit.session.restNotify"

    // Auto-backup to the user's own iCloud Drive folder.
    case autoBackupFolderBookmark = "cenit.autoBackup.folderBookmark"
    case autoBackupFolderName = "cenit.autoBackup.folderName"
    case autoBackupLastDate = "cenit.autoBackup.lastDate"

    // Feature state.
    case stressCalendarIDs = "cenit.stress.calendarIDs"
    case mirrorStrengthToWatch = "cenit.mirrorStrengthToWatch"

    // NO están aquí, a propósito: `exerciseMediaEnabled` / `exerciseMediaMissedIds`. La descarga de
    // animaciones se retiró de Ajustes (FER-398), así que migrar su valor dejaría una instalación que
    // la tenía ENCENDIDA con la red prendida y sin ningún control para apagarla. `PrefMigration`
    // BORRA sus claves heredadas en vez de copiarlas, y `MediaDownloadCoordinator.isEnabled` está
    // forzado a `false` hasta que FER-919 reviva la feature con otra fuente.

    /// Shortcuts' action inbox — written by the App Intents extension, drained by the app, so it
    /// lives in the shared suite rather than the app's own.
    case pendingIntents = "cenit.pendingIntents"

    /// The pre-FER-398 name of this key. Derived, never hand-written: the two prefixes are the only
    /// difference, so a new case cannot get its legacy name wrong.
    var legacyKey: String { "noop." + rawValue.dropFirst("cenit.".count) }

    var suite: Suite {
        switch self {
        case .pendingIntents: return .appGroup
        default:              return .standard
        }
    }
}

/// The one-time copy of every `noop.*` value onto its `cenit.*` name.
enum PrefMigration {

    /// Copy-then-delete, key by key. Call once at launch, BEFORE anything reads a preference.
    ///
    /// Idempotent with no flag of its own: after the first run there is no legacy key left, so every
    /// later run is 16 `object(forKey:)` misses. That matters — a flag is exactly the thing that goes
    /// out of sync (wiped defaults, a restored backup, a reinstall over the same container) and
    /// leaves the migration convinced it already ran.
    ///
    /// The new key WINS if both exist: it is the value the running app has been writing, and the
    /// legacy one is a stale leftover. The legacy key is removed in that case too, so the ambiguity
    /// does not survive to a third launch.
    static func migrateLegacyKeysIfNeeded(standard: UserDefaults = .standard,
                                          appGroup: UserDefaults = AppGroup.sharedDefaults()) {
        for key in PrefKey.allCases {
            let defaults = key.suite == .appGroup ? appGroup : standard
            // `object(forKey:)`, not a typed getter: the values are Bool / String / Double / Data /
            // [String], and an explicit `false` has to survive the copy exactly as it was written.
            guard let legacyValue = defaults.object(forKey: key.legacyKey) else { continue }
            if defaults.object(forKey: key.rawValue) == nil {
                defaults.set(legacyValue, forKey: key.rawValue)
            }
            defaults.removeObject(forKey: key.legacyKey)
        }
        // Retiradas del enum (FER-398): la descarga de animaciones ya no tiene control en Ajustes, así
        // que su preferencia no se migra — se BORRA. Copiarla dejaría un `true` heredado encendiendo
        // red que el usuario no podría apagar; borrarla deja la app en cero red por construcción.
        // Se borran los DOS nombres —el heredado y el `cenit.*` que una compilación intermedia de
        // FER-398 alcanzó a escribir—, así que para esta feature «migrado» significa «no queda rastro».
        for retired in ["exerciseMediaEnabled", "exerciseMediaMissedIds"] {
            standard.removeObject(forKey: "noop." + retired)
            standard.removeObject(forKey: "cenit." + retired)
        }
    }
}
