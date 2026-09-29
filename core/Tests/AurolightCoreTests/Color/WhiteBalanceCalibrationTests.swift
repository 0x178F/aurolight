import Testing

@testable import AurolightCore

struct WhiteBalanceCalibrationTests {
    @Test func startsNeutralWithWarmerAndCoolerOptions() {
        let calibration = WhiteBalanceCalibration()
        #expect(calibration.result == .neutral)
        #expect(calibration.candidate(0).temperature < WhiteBalance.neutralTemperature)
        #expect(calibration.candidate(1).temperature > WhiteBalance.neutralTemperature)
        #expect(calibration.candidate(0).tint == 0)
    }

    @Test func alwaysPickingOneConvergesAndFinishes() {
        var calibration = WhiteBalanceCalibration()
        for _ in 0..<WhiteBalanceCalibration.rounds { calibration.choose(0) }
        #expect(calibration.phase == .done)
        #expect(calibration.answered == WhiteBalanceCalibration.rounds)
        #expect(calibration.result.temperature < 4000)
        #expect(calibration.result.tint < -0.5)
        calibration.choose(1)
        #expect(calibration.answered == WhiteBalanceCalibration.rounds)
    }

    @Test func neitherKeepsTheGuessButNarrowsTheStep() {
        var calibration = WhiteBalanceCalibration()
        let wide = calibration.candidate(1).temperature
        calibration.chooseNeither()
        #expect(calibration.result == .neutral)
        #expect(calibration.candidate(1).temperature < wide)
    }

    @Test func tintIsSearchedAfterWarmth() {
        var calibration = WhiteBalanceCalibration()
        while calibration.phase == .warmth { calibration.choose(1) }
        let warmth = calibration.result.temperature
        #expect(calibration.phase == .tint)
        #expect(calibration.candidate(0).temperature == warmth && calibration.candidate(0).tint < 0)
    }

    @Test func optionsStayInRange() {
        var calibration = WhiteBalanceCalibration()
        for _ in 0..<WhiteBalanceCalibration.rounds {
            #expect(WhiteBalance.temperatureRange.contains(calibration.candidate(1).temperature))
            #expect((-1...1).contains(calibration.candidate(1).tint))
            calibration.choose(1)
        }
    }
}
