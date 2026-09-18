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

    @Test func emptyStringReturnsNil() {
        #expect(LRCParser.parse("") == nil)
    }
}
