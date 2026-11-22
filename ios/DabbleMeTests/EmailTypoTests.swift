import Testing
@testable import DabbleMe

/// The email field's "Did you mean …?" (the web's email_typo.js has the same cases).
struct EmailTypoTests {
    @Test func suggestsTheCommonDomainForATypo() {
        #expect(EmailTypo.suggestion(for: "paul@gmial.com") == "paul@gmail.com")
        #expect(EmailTypo.suggestion(for: "paul@gmail.con") == "paul@gmail.com")
        #expect(EmailTypo.suggestion(for: "paul@hotmial.com") == "paul@hotmail.com")
        #expect(EmailTypo.suggestion(for: " Paul@YAHOO.CMO ") == "paul@yahoo.com")
        #expect(EmailTypo.suggestion(for: "paul@iclod.com") == "paul@icloud.com")
    }

    @Test func fixesAMistypedEndingOnAnyDomain() {
        #expect(EmailTypo.suggestion(for: "paul@example.con") == "paul@example.com")
        #expect(EmailTypo.suggestion(for: "paul@example.nte") == "paul@example.net")
    }

    @Test func leavesRightAndUnfamiliarAddressesAlone() {
        #expect(EmailTypo.suggestion(for: "paul@gmail.com") == nil)
        #expect(EmailTypo.suggestion(for: "paul@example.com") == nil)
        #expect(EmailTypo.suggestion(for: "paul@dabble.me") == nil)
        #expect(EmailTypo.suggestion(for: "paul@") == nil)
        #expect(EmailTypo.suggestion(for: "not an email") == nil)
    }

    @Test func distanceCountsASwapAsOne() {
        #expect(EmailTypo.distance("gmial", "gmail") == 1)
        #expect(EmailTypo.distance("abc", "abc") == 0)
        #expect(EmailTypo.distance("", "abc") == 3)
    }
}
