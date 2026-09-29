import AurolightCore
import Foundation
import Testing

@testable import Aurolight

struct SettingsTests {
    private func withStore(_ body: (SettingsStore, UserDefaults) throws -> Void) rethrows {
        let suite = "SettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(SettingsStore(defaults: defaults), defaults)
    }

    @Test func savedSettingsLoadBackUnchanged() {
        withStore { store, _ in
            var settings = AppSettings()
            settings.layout = LEDLayout(top: 30, right: 17, bottom: 30, left: 17)
            settings.color.select(.vivid)
            settings.effects = EffectSettings(mode: .aurora, speed: 0.7)
            settings.whiteBalance = WhiteBalance(temperature: 5200, tint: 0.1)
            settings.portPath = "/dev/cu.usbserial-1"
            settings.baudRate = 921_600
            settings.onboardingCompleted = true
            store.save(settings)
            #expect(store.load() == settings)
        }
    }

    @Test func settingsFromAnOlderVersionStillLoad() {
        withStore { store, defaults in
            let json = #"{"portPath":"/dev/cu.usbmodem1","layout":{"top":20,"right":10,"bottom":20,"left":10}}"#
            defaults.set(Data(json.utf8), forKey: "settings.v1")
            let settings = store.load()
            #expect(settings.portPath == "/dev/cu.usbmodem1")
            #expect(settings.layout.placedCount == 60)
            #expect(settings.whiteBalance == .neutral && settings.color == ColorSettings())
        }
    }

    @Test func unreadableSettingsFallBackToDefaultsAndAreKept() {
        withStore { store, defaults in
            let garbage = Data("not json".utf8)
            defaults.set(garbage, forKey: "settings.v1")
            #expect(store.load() == AppSettings())
            #expect(defaults.data(forKey: "settings.v1.corrupt") == garbage)
        }
    }
}
