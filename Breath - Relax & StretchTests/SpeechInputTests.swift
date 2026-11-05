import Testing
@testable import BreathRelaxStretch

struct SpeechInputTests {
    @Test func micDeniedTakesPrecedence() {
        #expect(SpeechInput.reason(micGranted: false, speechAuthorized: false, localeSupported: false) == .micDenied)
        #expect(SpeechInput.reason(micGranted: false, speechAuthorized: true, localeSupported: true) == .micDenied)
    }

    @Test func speechDeniedWhenMicGranted() {
        #expect(SpeechInput.reason(micGranted: true, speechAuthorized: false, localeSupported: false) == .speechDenied)
    }

    @Test func unsupportedLocale() {
        #expect(SpeechInput.reason(micGranted: true, speechAuthorized: true, localeSupported: false) == .localeUnsupported)
    }

    @Test func allGoodIsNil() {
        #expect(SpeechInput.reason(micGranted: true, speechAuthorized: true, localeSupported: true) == nil)
    }
}
