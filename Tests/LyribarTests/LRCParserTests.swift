import Foundation
import Testing

@testable import Lyribar

struct LRCParserTests {
    @Test func normalLine() {
        let result = LRCParser.parse("[00:12.34]Hello")
        #expect(result?.lines == [LyricLine(time: 12.34, text: "Hello")])
    }

    @Test func multipleTimestampsOnOneLine() {
        let result = LRCParser.parse("[00:12.00][00:15.00]Hello")
        #expect(
            result?.lines == [
                LyricLine(time: 12.0, text: "Hello"),
                LyricLine(time: 15.0, text: "Hello"),
            ])
    }

    @Test func metadataTagLinesAreIgnored() {
        let result = LRCParser.parse("[ar:Some Artist]\n[00:12.00]Hello")
        #expect(result?.lines == [LyricLine(time: 12.0, text: "Hello")])
    }

    @Test func leadingSpaceAfterTimestampIsTrimmed() {
        let result = LRCParser.parse("[00:12.00] Hello")
        #expect(result?.lines == [LyricLine(time: 12.0, text: "Hello")])
    }

    @Test func emptyTextLineIsKeptForInstrumentalGaps() {
        let result = LRCParser.parse("[00:12.00]")
        #expect(result?.lines == [LyricLine(time: 12.0, text: "")])
    }

    @Test func whitespaceOnlyTextLineIsKeptForInstrumentalGaps() {
        let result = LRCParser.parse("[00:12.00]   ")
        #expect(result?.lines == [LyricLine(time: 12.0, text: "")])
    }

    @Test func outOfOrderInputIsSortedByTime() {
        let result = LRCParser.parse("[00:15.00]Second\n[00:12.00]First")
        #expect(
            result?.lines == [
                LyricLine(time: 12.0, text: "First"),
                LyricLine(time: 15.0, text: "Second"),
            ])
    }

    @Test func threeDigitFraction() throws {
        let result = LRCParser.parse("[00:12.345]Hello")
        let time = try #require(result?.lines.first?.time)
        #expect(abs(time - 12.345) < 0.0001)
    }

    @Test func timestampWithoutFraction() throws {
        let result = LRCParser.parse("[01:23]Hello")
        let time = try #require(result?.lines.first?.time)
        #expect(abs(time - 83.0) < 0.0001)
        #expect(result?.lines.first?.text == "Hello")
    }

    @Test func oneDigitFraction() throws {
        let result = LRCParser.parse("[01:23.4]Hello")
        let time = try #require(result?.lines.first?.time)
        #expect(abs(time - 83.4) < 0.0001)
    }

    @Test func fractionDigitsMayBeMixed() throws {
        let result = try #require(
            LRCParser.parse("[01:23]None\n[01:23.4]One\n[01:23.45]Two\n[01:23.456]Three"))
        #expect(result.lines.map(\.text) == ["None", "One", "Two", "Three"])
        let expected = [83.0, 83.4, 83.45, 83.456]
        #expect(zip(result.lines.map(\.time), expected).allSatisfy { abs($0 - $1) < 0.0001 })
    }

    // The minutes must be digits, which is what keeps metadata out.
    @Test func lengthTagIsIgnored() {
        #expect(LRCParser.parse("[length:03:45]") == nil)
        #expect(LRCParser.parse("[length:03:45]\n[01:23]Hello")?.lines.count == 1)
    }

    @Test func malformedFractionIsRejected() {
        #expect(LRCParser.parse("[01:23.]Hello") == nil)
        #expect(LRCParser.parse("[01:23.4567]Hello") == nil)
        #expect(LRCParser.parse("[01:2]Hello") == nil)
    }

    @Test func emptyStringReturnsNil() {
        #expect(LRCParser.parse("") == nil)
    }
}
