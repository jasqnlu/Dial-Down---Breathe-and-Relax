import Testing
@testable import BreathRelaxStretch

struct SpeechInputTests {
    @Test func micDeniedTakesPrecedence() {
        #expect(SpeechInput.reason(micGranted: false, speechAuthorized: false, localeSupported: false, assetInstalled: false) == .micDenied)
        #expect(SpeechInput.reason(micGranted: false, speechAuthorized: true, localeSupported: true, assetInstalled: true) == .micDenied)
    }

    @Test func speechDeniedWhenMicGranted() {
        #expect(SpeechInput.reason(micGranted: true, speechAuthorized: false, localeSupported: false, assetInstalled: true) == .speechDenied)
    }

    @Test func unsupportedLocale() {
        #expect(SpeechInput.reason(micGranted: true, speechAuthorized: true, localeSupported: false, assetInstalled: true) == .localeUnsupported)
    }

    @Test func assetMissingComesAfterLocale() {
        #expect(SpeechInput.reason(micGranted: true, speechAuthorized: true, localeSupported: true, assetInstalled: false) == .assetUnavailable)
        #expect(SpeechInput.reason(micGranted: true, speechAuthorized: true, localeSupported: false, assetInstalled: false) == .localeUnsupported)
    }

    @Test func allGoodIsNil() {
        #expect(SpeechInput.reason(micGranted: true, speechAuthorized: true, localeSupported: true, assetInstalled: true) == nil)
    }
}
