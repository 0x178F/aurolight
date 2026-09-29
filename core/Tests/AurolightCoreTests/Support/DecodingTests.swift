import Foundation
import Testing

@testable import AurolightCore

struct DecodingTests {
    private enum Shape: String, Codable { case circle, square }

    private struct Sample: Decodable {
        var count: Int
        var name: String
        var shape: Shape
        var note: String?

        enum CodingKeys: String, CodingKey { case count, name, shape, note }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            count = c.decode(.count, default: 7)
            name = c.decode(.name, default: "default")
            shape = c.decode(.shape, default: .circle)
            note = c.decodeLenient(.note)
        }
    }

    private func decode(_ json: String) throws -> Sample {
        try JSONDecoder().decode(Sample.self, from: Data(json.utf8))
    }

    @Test func missingKeysUseDefaults() throws {
        let s = try decode("{}")
        #expect(s.count == 7)
        #expect(s.name == "default")
        #expect(s.shape == .circle)
        #expect(s.note == nil)
    }

    @Test func wrongTypeFallsBackAndOtherFieldsSurvive() throws {
        let s = try decode(#"{"count":"lots","name":"kept","note":42}"#)
        #expect(s.count == 7)
        #expect(s.name == "kept")
        #expect(s.note == nil)
    }

    @Test func unknownEnumValueFallsBack() throws {
        let s = try decode(#"{"shape":"triangle","count":3}"#)
        #expect(s.shape == .circle)
        #expect(s.count == 3)
    }

    @Test func validValuesAreKept() throws {
        let s = try decode(#"{"count":3,"name":"x","shape":"square","note":"hi"}"#)
        #expect(s.count == 3)
        #expect(s.name == "x")
        #expect(s.shape == .square)
        #expect(s.note == "hi")
    }
}
