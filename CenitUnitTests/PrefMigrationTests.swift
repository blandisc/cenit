import XCTest
@testable import Cenit

/// FER-398 — the one-time move of every persisted preference off the `noop.` prefix.
///
/// The risk this covers is not "the string changed": it is that a botched rename resets a live
/// install. A new key reads as *never set*, so the user lands back on onboarding, re-accepts the
/// terms, loses their appearance choice and their auto-backup folder. Every test below is a way that
/// could happen.
///
/// Same suite pattern as `SessionComfortTests`: a named `UserDefaults` wiped in `setUp`, so nothing
/// touches the real defaults.
final class PrefMigrationTests: XCTestCase {

    private var standard: UserDefaults!
    private var group: UserDefaults!
    private let standardSuite = "PrefMigrationTests.standard"
    private let groupSuite = "PrefMigrationTests.group"

    override func setUp() {
        super.setUp()
        standard = UserDefaults(suiteName: standardSuite)!
        group = UserDefaults(suiteName: groupSuite)!
        standard.removePersistentDomain(forName: standardSuite)
        group.removePersistentDomain(forName: groupSuite)
    }

    override func tearDown() {
        standard.removePersistentDomain(forName: standardSuite)
        group.removePersistentDomain(forName: groupSuite)
        super.tearDown()
    }

    private func migrate() {
        PrefMigration.migrateLegacyKeysIfNeeded(standard: standard, appGroup: group)
    }

    // MARK: - The enum itself

    /// The migration derives every legacy name from the raw value, so a case that doesn't carry the
    /// prefix would silently migrate the wrong key. And a duplicate raw value wouldn't compile, but a
    /// duplicate *legacy* name would — and would make two preferences fight over one old value.
    func testEveryKeyIsPrefixedAndUnique() {
        for key in PrefKey.allCases {
            XCTAssertTrue(key.rawValue.hasPrefix("cenit."), "\(key.rawValue) is not under the cenit. prefix")
            XCTAssertTrue(key.legacyKey.hasPrefix("noop."), "\(key.legacyKey) is not under the noop. prefix")
            XCTAssertEqual(key.legacyKey.dropFirst("noop.".count), key.rawValue.dropFirst("cenit.".count),
                           "the two names must differ ONLY in the prefix")
        }
        let raws = Set(PrefKey.allCases.map(\.rawValue))
        let legacies = Set(PrefKey.allCases.map(\.legacyKey))
        XCTAssertEqual(raws.count, PrefKey.allCases.count, "duplicate raw value")
        XCTAssertEqual(legacies.count, PrefKey.allCases.count, "duplicate legacy key")
    }

    /// Shortcuts' inbox is written by the extension and drained by the app, so it lives in the shared
    /// suite. If it migrated in `.standard`, the queue would look empty forever after the rename.
    func testOnlyPendingIntentsLivesInTheAppGroup() {
        for key in PrefKey.allCases {
            XCTAssertEqual(key.suite, key == .pendingIntents ? .appGroup : .standard,
                           "\(key.rawValue) is in the wrong suite")
        }
    }

    // MARK: - The copy

    /// Every type the app actually stores has to survive the copy unchanged — including an explicit
    /// `false`, which is NOT the same as an absent key (that is the whole reason the migration copies
    /// `object(forKey:)` rather than reading through a typed getter with a default).
    func testCopiesEveryStoredTypeIncludingAnExplicitFalse() {
        standard.set(true, forKey: PrefKey.onboarded.legacyKey)
        standard.set(false, forKey: PrefKey.sessionRestNotify.legacyKey)          // explicit OFF
        standard.set("oscuro", forKey: PrefKey.apariencia.legacyKey)
        standard.set(1_725_000_000.0, forKey: PrefKey.autoBackupLastDate.legacyKey)
        standard.set(Data("bookmark".utf8), forKey: PrefKey.autoBackupFolderBookmark.legacyKey)
        standard.set(["cal-1", "cal-2"], forKey: PrefKey.stressCalendarIDs.legacyKey)

        migrate()

        XCTAssertEqual(standard.bool(forKey: PrefKey.onboarded.rawValue), true)
        XCTAssertNotNil(standard.object(forKey: PrefKey.sessionRestNotify.rawValue),
                        "an explicit false must survive as a REAL stored value, not as an absent key")
        XCTAssertEqual(standard.bool(forKey: PrefKey.sessionRestNotify.rawValue), false)
        XCTAssertEqual(standard.string(forKey: PrefKey.apariencia.rawValue), "oscuro")
        XCTAssertEqual(standard.double(forKey: PrefKey.autoBackupLastDate.rawValue), 1_725_000_000.0)
        XCTAssertEqual(standard.data(forKey: PrefKey.autoBackupFolderBookmark.rawValue), Data("bookmark".utf8))
        XCTAssertEqual(standard.stringArray(forKey: PrefKey.stressCalendarIDs.rawValue), ["cal-1", "cal-2"])
    }

    /// The consent record is the one value where a reset is a legal problem, not a cosmetic one: the
    /// terms gate re-appears unless the stored version still equals `Terms.currentVersion`.
    func testAcceptedTermsVersionSurvivesSoTheGateStaysClosed() {
        standard.set(Terms.currentVersion, forKey: PrefKey.acceptedTermsVersion.legacyKey)

        migrate()

        XCTAssertEqual(standard.string(forKey: PrefKey.acceptedTermsVersion.rawValue), Terms.currentVersion)
    }

    /// The legacy key is removed, so the next launch has nothing left to find.
    func testLegacyKeysAreDeleted() {
        standard.set(true, forKey: PrefKey.onboarded.legacyKey)

        migrate()

        XCTAssertNil(standard.object(forKey: PrefKey.onboarded.legacyKey))
    }

    /// If both exist, the NEW one wins — it is the value the running app has been writing. The stale
    /// legacy leftover is deleted anyway, so the ambiguity cannot reach a third launch.
    func testNewValueWinsOverALegacyLeftover() {
        standard.set("claro", forKey: PrefKey.apariencia.legacyKey)
        standard.set("oscuro", forKey: PrefKey.apariencia.rawValue)

        migrate()

        XCTAssertEqual(standard.string(forKey: PrefKey.apariencia.rawValue), "oscuro")
        XCTAssertNil(standard.object(forKey: PrefKey.apariencia.legacyKey))
    }

    /// It runs on every launch, and it has no flag of its own — so running it again must not undo,
    /// resurrect or overwrite anything.
    func testIsIdempotent() {
        standard.set("oscuro", forKey: PrefKey.apariencia.legacyKey)

        migrate()
        standard.set("claro", forKey: PrefKey.apariencia.rawValue)   // the user changes it afterwards
        migrate()
        migrate()

        XCTAssertEqual(standard.string(forKey: PrefKey.apariencia.rawValue), "claro",
                       "a later run must not resurrect the legacy value over a newer choice")
    }

    /// `pendingIntents` migrates in the shared suite and nowhere else.
    func testPendingIntentsMigratesOnlyInTheGroupSuite() {
        group.set(["markMoment|2026-09-06T10:00:00Z"], forKey: PrefKey.pendingIntents.legacyKey)
        standard.set(["should-not-be-touched"], forKey: PrefKey.pendingIntents.legacyKey)

        migrate()

        XCTAssertEqual(group.stringArray(forKey: PrefKey.pendingIntents.rawValue),
                       ["markMoment|2026-09-06T10:00:00Z"])
        XCTAssertNil(group.object(forKey: PrefKey.pendingIntents.legacyKey))
        XCTAssertNil(standard.object(forKey: PrefKey.pendingIntents.rawValue),
                     "the app's own defaults are not the inbox — nothing lands there")
        XCTAssertEqual(standard.stringArray(forKey: PrefKey.pendingIntents.legacyKey), ["should-not-be-touched"],
                       "and a same-named key in the wrong suite is left alone")
    }

    /// FER-398 · la excepción a la migración: la descarga de animaciones perdió su control en Ajustes,
    /// así que copiar su preferencia dejaría a quien la tenía ENCENDIDA con la red prendida y sin
    /// interruptor. Estas dos claves salieron del enum a propósito y la migración las BORRA — la app
    /// tiene que quedar en cero red, no en "red encendida sin apagador".
    func testRetiredMediaKeysAreDeletedNotMigrated() {
        standard.set(true, forKey: "noop.exerciseMediaEnabled")
        standard.set(["bench-press"], forKey: "noop.exerciseMediaMissedIds")

        migrate()

        XCTAssertNil(standard.object(forKey: "cenit.exerciseMediaEnabled"),
                     "la preferencia retirada no debe renacer bajo el nombre nuevo")
        XCTAssertNil(standard.object(forKey: "cenit.exerciseMediaMissedIds"),
                     "los ids fallidos tampoco viajan al nombre nuevo")
        XCTAssertNil(standard.object(forKey: "noop.exerciseMediaEnabled"),
                     "y la clave heredada se borra, no se queda esperando")
        XCTAssertNil(standard.object(forKey: "noop.exerciseMediaMissedIds"))

        XCTAssertFalse(PrefKey.allCases.contains { $0.rawValue.contains("exerciseMedia") },
                       "si una de estas claves vuelve al enum, la migración volvería a copiarla")
    }

    /// A fresh install has no legacy keys at all: the migration must not invent any.
    func testFreshInstallWritesNothing() {
        migrate()

        for key in PrefKey.allCases {
            XCTAssertNil(standard.object(forKey: key.rawValue), "\(key.rawValue) was invented")
            XCTAssertNil(group.object(forKey: key.rawValue), "\(key.rawValue) was invented in the group suite")
        }
    }
}
