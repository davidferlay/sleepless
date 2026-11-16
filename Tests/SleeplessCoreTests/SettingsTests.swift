import Testing

@testable import SleeplessCore

struct SettingsTests {
    @Test func usesDefaultsWhenNothingIsSet() {
        let settings = Settings(lookup: { _ in nil })
        #expect(settings.startDelay == 3)
        #expect(settings.stopDelay == 30)
    }

    @Test func readsNumbers() {
        let values: [String: Any] = ["startDelay": 1.5, "stopDelay": 4]
        let settings = Settings(lookup: { values[$0] })
        #expect(settings.startDelay == 1.5)
        #expect(settings.stopDelay == 4)
    }

    @Test func readsNumericStringsFromLaunchArguments() {
        let values: [String: Any] = ["startDelay": "1", "stopDelay": "3.5"]
        let settings = Settings(lookup: { values[$0] })
        #expect(settings.startDelay == 1)
        #expect(settings.stopDelay == 3.5)
    }

    @Test(arguments: [0, -1, Double.nan, Double.infinity] as [Double])
    func rejectsNonPositiveOrNonFiniteNumbers(value: Double) {
        let settings = Settings(lookup: { _ in value })
        #expect(settings == Settings())
    }

    @Test(arguments: ["", "abc", "-2", "0"])
    func rejectsInvalidStrings(value: String) {
        let settings = Settings(lookup: { _ in value })
        #expect(settings == Settings())
    }

    @Test func rejectsOtherTypes() {
        let settings = Settings(lookup: { _ in [1, 2] })
        #expect(settings == Settings())
    }
}
