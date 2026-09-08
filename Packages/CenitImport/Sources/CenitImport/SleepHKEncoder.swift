import Foundation

/// Descriptor for a single Apple Health sleep sample — platform-agnostic so the
/// mapping logic is testable on macOS without a HealthKit import.
public struct SleepHKSample: Equatable {
    public let hkValue: Int       // HKCategoryValueSleepAnalysis raw value
    public let start: Date
    public let end: Date
    public let dedupeKey: String  // value for HKMetadataKeyExternalUUID

    // Explicit public init — a public struct's memberwise init is internal, so `HealthKitBridge`
    // (CenitApp module) couldn't construct these from `HKCategorySample`s without it (FER-486).
    public init(hkValue: Int, start: Date, end: Date, dedupeKey: String) {
        self.hkValue = hkValue; self.start = start; self.end = end; self.dedupeKey = dedupeKey
    }
}

/// The stage vocabulary shared with `SleepHKSample` and the pure decoder `SleepHKDecoder`: the raw
/// `HKCategoryValueSleepAnalysis` values plus the stage-name → value map.
///
/// The sleep write-back path (which turned these into `HKObject`s under a branded dedupe key) was
/// retired with the band amputation (FER-1003); FER-479 deleted the last of it (`samples(...)`), so
/// what remains is only the read-side stage vocabulary. Keeping it as one enum lets the mapping be
/// unit-tested on macOS without `HKHealthStore`.
///
/// HKCategoryValueSleepAnalysis raw values used here are stable since iOS 16 / macOS 13
/// and documented at developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis.
public enum SleepHKEncoder {

    // Raw values for HKCategoryValueSleepAnalysis (stable since iOS 16 / macOS 13).
    public static let inBedValue: Int      = 0  // .inBed
    public static let awakeValue: Int      = 2  // .awake
    public static let asleepCoreValue: Int = 3  // .asleepCore  (NREM light)
    public static let asleepDeepValue: Int = 4  // .asleepDeep
    public static let asleepREMValue: Int  = 5  // .asleepREM

    /// Maps a decoded stage name to the matching `HKCategoryValueSleepAnalysis` raw value — the
    /// forward companion of `SleepHKDecoder.stage(forHKValue:)`.
    public static func hkValue(forStage stage: String) -> Int {
        switch stage {
        case "deep":  return asleepDeepValue
        case "rem":   return asleepREMValue
        case "wake":  return awakeValue
        case "light": return asleepCoreValue
        default:      return asleepCoreValue
        }
    }
}
