//
//  MediaKeyRemapperTests.swift
//  MultiSoundChangerTests
//
//  The A-3 merge semantics: `hidutil property --set` replaces the ENTIRE UserKeyMapping list, so
//  every write must preserve everyone else's mappings and replace only our own. Tested through the
//  pure transformations — apply()/revert() are trivial read->transform->write wrappers around them.
//

import Testing
@testable import MultiSoundChanger2

@Suite struct MediaKeyRemapperTests {
    private typealias Mapping = MediaKeyRemapper.Mapping

    /// The user's own remap (Caps Lock -> Escape), the thing the bulldozer would destroy.
    private let capsLockToEscape = Mapping(src: 0x700000039, dst: 0x700000029)

    // Real `hidutil property --get` output shape: OpenStep plist, numbers printed as bare words
    // (which parse as strings).
    private let realOutput = """
    (
            {
            HIDKeyboardModifierMappingDst = 30064771113;
            HIDKeyboardModifierMappingSrc = 30064771129;
        }
    )
    """

    // MARK: parseMappings

    @Test func parsesRealHidutilOutput() {
        let mappings = MediaKeyRemapper.parseMappings(from: realOutput)

        #expect(mappings == [Mapping(src: 30_064_771_129, dst: 30_064_771_113)])
    }

    @Test func parsesAbsentMappingPrintedAsNull() {
        // An absent mapping prints as "(null)" — in OpenStep that is an ARRAY holding the bare
        // word `null`, so it parses fine and compactMap drops the non-dictionary entry: empty
        // mappings, not a parse error.
        #expect(MediaKeyRemapper.parseMappings(from: "(null)") == [])
    }

    @Test func parsesGarbageAsNil() {
        #expect(MediaKeyRemapper.parseMappings(from: "not a plist {{{") == nil)
    }

    @Test func skipsEntriesWithoutBothKeys() {
        let output = """
        (
            { HIDKeyboardModifierMappingSrc = 42; },
            { HIDKeyboardModifierMappingSrc = 1; HIDKeyboardModifierMappingDst = 2; }
        )
        """

        #expect(MediaKeyRemapper.parseMappings(from: output) == [Mapping(src: 1, dst: 2)])
    }

    // MARK: A-3 merge

    @Test func applyPreservesForeignMappings() {
        let merged = MediaKeyRemapper.applyingOwnMappings(to: [capsLockToEscape])

        #expect(merged.contains(capsLockToEscape))
        #expect(merged.count == 4) // the user's one + our three
    }

    @Test func applyIsIdempotentAfterACrashedSession() {
        // A stale set left behind by a crashed session must be replaced, not duplicated.
        let once = MediaKeyRemapper.applyingOwnMappings(to: [capsLockToEscape])
        let twice = MediaKeyRemapper.applyingOwnMappings(to: once)

        #expect(twice == once)
    }

    @Test func revertRemovesExactlyOurEntries() {
        let applied = MediaKeyRemapper.applyingOwnMappings(to: [capsLockToEscape])

        #expect(MediaKeyRemapper.removingOwnMappings(from: applied) == [capsLockToEscape])
    }

    @Test func revertOnForeignOnlyListIsANoOp() {
        #expect(MediaKeyRemapper.removingOwnMappings(from: [capsLockToEscape]) == [capsLockToEscape])
    }

    // MARK: setPayload

    @Test func payloadIsValidJSONWithBothKeys() throws {
        let payload = MediaKeyRemapper.setPayload(for: [Mapping(src: 1, dst: 2)])

        let object = try JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any]
        let entries = object?["UserKeyMapping"] as? [[String: Int64]]

        #expect(entries == [["HIDKeyboardModifierMappingSrc": 1, "HIDKeyboardModifierMappingDst": 2]])
    }

    @Test func payloadForEmptyListClearsTheProperty() {
        #expect(MediaKeyRemapper.setPayload(for: []) == "{\"UserKeyMapping\":[]}")
    }
}
