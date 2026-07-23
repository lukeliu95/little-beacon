import Foundation

/// Family-controlled settings that travel with the rest of `RuleSet`.
///
/// The feature is deliberately off by default: enabling camera access is a visible,
/// consent-requiring action that must be completed on the child Mac.
public struct ViewingDistancePolicy: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var checkIntervalMinutes: Int
    public var minimumDistanceCentimeters: Int

    public init(
        enabled: Bool = false,
        checkIntervalMinutes: Int = 10,
        minimumDistanceCentimeters: Int = 45
    ) {
        self.enabled = enabled
        self.checkIntervalMinutes = min(60, max(5, checkIntervalMinutes))
        self.minimumDistanceCentimeters = min(80, max(30, minimumDistanceCentimeters))
    }

    public static let disabled = ViewingDistancePolicy()

    private enum CodingKeys: String, CodingKey {
        case enabled, checkIntervalMinutes, minimumDistanceCentimeters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try container.decode(Bool.self, forKey: .enabled),
            checkIntervalMinutes: try container.decode(Int.self, forKey: .checkIntervalMinutes),
            minimumDistanceCentimeters: try container.decode(Int.self, forKey: .minimumDistanceCentimeters)
        )
    }
}

/// A device-local geometric reference. It contains no image, facial landmarks, or identity.
///
/// Face width is normalized to the camera frame (0...1), so the reference remains independent
/// of capture resolution. A different camera invalidates the calibration.
public struct ViewingDistanceCalibration: Codable, Equatable, Sendable {
    public var cameraUniqueID: String
    public var referenceFaceWidth: Double
    public var referenceDistanceCentimeters: Int
    public var calibratedAt: Date

    public init(
        cameraUniqueID: String,
        referenceFaceWidth: Double,
        referenceDistanceCentimeters: Int,
        calibratedAt: Date = Date()
    ) {
        self.cameraUniqueID = cameraUniqueID
        self.referenceFaceWidth = referenceFaceWidth
        self.referenceDistanceCentimeters = referenceDistanceCentimeters
        self.calibratedAt = calibratedAt
    }
}

public enum ViewingDistanceAssessment: Equatable, Sendable {
    case safe(estimatedCentimeters: Int)
    case tooClose(estimatedCentimeters: Int)
    case inconclusive
}

/// Converts a short batch of normalized face widths into one observable result.
///
/// A monocular webcam cannot provide trustworthy absolute depth. The estimate is therefore
/// relative to a local calibration and intentionally rounded to whole centimeters. Callers
/// should present the safe/too-close classification, not the estimate as medical-grade truth.
public enum ViewingDistanceJudge {
    public static let minimumValidSamples = 5
    public static let clearHysteresisCentimeters = 8

    public static func makeCalibration(
        cameraUniqueID: String,
        normalizedFaceWidths: [Double],
        referenceDistanceCentimeters: Int,
        at date: Date = Date()
    ) -> ViewingDistanceCalibration? {
        guard let faceWidth = medianValidWidth(normalizedFaceWidths) else { return nil }
        return ViewingDistanceCalibration(
            cameraUniqueID: cameraUniqueID,
            referenceFaceWidth: faceWidth,
            referenceDistanceCentimeters: min(80, max(30, referenceDistanceCentimeters)),
            calibratedAt: date
        )
    }

    public static func assess(
        cameraUniqueID: String,
        normalizedFaceWidths: [Double],
        calibration: ViewingDistanceCalibration,
        policy: ViewingDistancePolicy,
        wasTooClose: Bool
    ) -> ViewingDistanceAssessment {
        guard cameraUniqueID == calibration.cameraUniqueID,
              calibration.referenceFaceWidth > 0,
              let currentFaceWidth = medianValidWidth(normalizedFaceWidths) else {
            return .inconclusive
        }

        let estimate = Double(calibration.referenceDistanceCentimeters)
            * calibration.referenceFaceWidth
            / currentFaceWidth
        let roundedEstimate = max(1, Int(estimate.rounded()))
        let threshold = policy.minimumDistanceCentimeters
            + (wasTooClose ? clearHysteresisCentimeters : 0)

        if roundedEstimate < threshold {
            return .tooClose(estimatedCentimeters: roundedEstimate)
        }
        return .safe(estimatedCentimeters: roundedEstimate)
    }

    private static func medianValidWidth(_ widths: [Double]) -> Double? {
        let sorted = widths
            .filter { $0.isFinite && $0 >= 0.03 && $0 <= 1 }
            .sorted()
        guard sorted.count >= minimumValidSamples else { return nil }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}
