import Foundation
import Testing
@testable import LittleBeaconCore

private let referenceWidths = [0.200, 0.202, 0.198, 0.201, 0.199, 0.200, 0.203]

@Test func policyClampsRemoteOrProgrammaticValuesToSupportedBounds() {
    let policy = ViewingDistancePolicy(
        enabled: true,
        checkIntervalMinutes: 1,
        minimumDistanceCentimeters: 500
    )

    #expect(policy.enabled)
    #expect(policy.checkIntervalMinutes == 5)
    #expect(policy.minimumDistanceCentimeters == 80)
}

@Test func calibrationUsesAStableMedianAndStoresNoImageData() throws {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let calibration = try #require(ViewingDistanceJudge.makeCalibration(
        cameraUniqueID: "built-in-camera",
        normalizedFaceWidths: referenceWidths + [0.95],
        referenceDistanceCentimeters: 45,
        at: date
    ))

    #expect(calibration.cameraUniqueID == "built-in-camera")
    #expect(calibration.referenceFaceWidth == 0.2005)
    #expect(calibration.referenceDistanceCentimeters == 45)
    #expect(calibration.calibratedAt == date)
}

@Test func tooFewOrInvalidFramesCannotProduceACalibration() {
    #expect(ViewingDistanceJudge.makeCalibration(
        cameraUniqueID: "camera",
        normalizedFaceWidths: [0.2, 0.2, 0.2, .nan, 2],
        referenceDistanceCentimeters: 45
    ) == nil)
}

@Test func largerFaceThanCalibrationIsClassifiedAsTooClose() throws {
    let calibration = try #require(ViewingDistanceJudge.makeCalibration(
        cameraUniqueID: "camera",
        normalizedFaceWidths: referenceWidths,
        referenceDistanceCentimeters: 45
    ))
    let assessment = ViewingDistanceJudge.assess(
        cameraUniqueID: "camera",
        normalizedFaceWidths: [0.30, 0.301, 0.299, 0.302, 0.30, 0.30],
        calibration: calibration,
        policy: ViewingDistancePolicy(enabled: true, minimumDistanceCentimeters: 45),
        wasTooClose: false
    )

    #expect(assessment == .tooClose(estimatedCentimeters: 30))
}

@Test func hysteresisRequiresMovingClearlyBackBeforeClearing() throws {
    let calibration = try #require(ViewingDistanceJudge.makeCalibration(
        cameraUniqueID: "camera",
        normalizedFaceWidths: referenceWidths,
        referenceDistanceCentimeters: 45
    ))
    let widthsAtAboutFortyEightCentimeters = Array(repeating: 0.1875, count: 6)
    let withoutHysteresis = ViewingDistanceJudge.assess(
        cameraUniqueID: "camera",
        normalizedFaceWidths: widthsAtAboutFortyEightCentimeters,
        calibration: calibration,
        policy: ViewingDistancePolicy(enabled: true, minimumDistanceCentimeters: 45),
        wasTooClose: false
    )
    let whileAlreadyTooClose = ViewingDistanceJudge.assess(
        cameraUniqueID: "camera",
        normalizedFaceWidths: widthsAtAboutFortyEightCentimeters,
        calibration: calibration,
        policy: ViewingDistancePolicy(enabled: true, minimumDistanceCentimeters: 45),
        wasTooClose: true
    )

    #expect(withoutHysteresis == .safe(estimatedCentimeters: 48))
    #expect(whileAlreadyTooClose == .tooClose(estimatedCentimeters: 48))
}

@Test func aDifferentCameraIsInconclusiveInsteadOfRaisingAnAlarm() throws {
    let calibration = try #require(ViewingDistanceJudge.makeCalibration(
        cameraUniqueID: "old-camera",
        normalizedFaceWidths: referenceWidths,
        referenceDistanceCentimeters: 45
    ))

    #expect(ViewingDistanceJudge.assess(
        cameraUniqueID: "new-camera",
        normalizedFaceWidths: Array(repeating: 0.5, count: 8),
        calibration: calibration,
        policy: ViewingDistancePolicy(enabled: true),
        wasTooClose: false
    ) == .inconclusive)
}
