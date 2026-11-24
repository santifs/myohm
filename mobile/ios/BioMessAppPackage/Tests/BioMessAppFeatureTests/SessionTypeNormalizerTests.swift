import Testing
@testable import BioMessAppFeature

@Suite("SessionTypeNormalizer")
struct SessionTypeNormalizerTests {
    @Test func trimsAndLowercases() {
        #expect(SessionTypeNormalizer.normalize("  Basal  ") == "basal")
        #expect(SessionTypeNormalizer.normalize("BASAL") == "basal")
        #expect(SessionTypeNormalizer.normalize("Post_Inc_3") == "post_inc_3")
    }

    @Test func replacesInternalWhitespaceWithUnderscore() {
        #expect(SessionTypeNormalizer.normalize("Serie 1") == "serie_1")
        #expect(SessionTypeNormalizer.normalize("post inc 3") == "post_inc_3")
    }

    @Test func blankInputReturnsNil() {
        #expect(SessionTypeNormalizer.normalize("") == nil)
        #expect(SessionTypeNormalizer.normalize("   ") == nil)
        #expect(SessionTypeNormalizer.normalize(nil) == nil)
    }

    @Test func underscoresArePreserved() {
        #expect(SessionTypeNormalizer.normalize("Basal_") == "basal_")
        #expect(SessionTypeNormalizer.normalize("Post__Inc") == "post__inc")
    }

    @Test func chipsAreIdempotent() {
        for chip in Study.bicepsTFG.sessionTypeSuggestions + Study.sentadillaTFM.sessionTypeSuggestions {
            #expect(SessionTypeNormalizer.normalize(chip) == chip)
        }
    }
}
