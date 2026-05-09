import CoreServices
import Foundation

enum MacOSDictionaryBridge {
    /// Fetch the raw definition string from the system dictionary services.
    /// Returns nil if the user has no enabled dictionary that contains the word.
    static func rawDefinition(for word: String) -> String? {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let range = CFRangeMake(0, trimmed.count)
        guard let cf = DCSCopyTextDefinition(nil, trimmed as CFString, range) else {
            return nil
        }
        let result = cf.takeRetainedValue() as String
        return result.isEmpty ? nil : result
    }

    /// Parse the raw definition into a structured DictionaryEntry.
    /// The raw text format depends on the active dictionary; this parser handles common
    /// macOS bundled dictionaries (New Oxford American, Oxford English, 牛津高阶, Collins).
    static func entry(for word: String, sourceLabel: String) -> DictionaryEntry? {
        guard let raw = rawDefinition(for: word) else { return nil }
        return DictionaryParser.parse(raw: raw, word: word, sourceLabel: sourceLabel)
    }
}

enum DictionaryParser {
    /// Heuristic parser. macOS Dictionary returns text like:
    ///   "ephemeral | əˈfem(ə)rəl | adjective lasting for a very short time: fashions are ephemeral. ..."
    /// Different dictionaries vary; the parser stays defensive — anything it can't
    /// confidently split goes into a single "definition" sense.
    static func parse(raw: String, word: String, sourceLabel: String) -> DictionaryEntry {
        let phonetics = extractPhonetics(from: raw)
        let stripped = strippedHeader(raw, word: word, phonetics: phonetics)
        let senses = extractSenses(from: stripped)

        return DictionaryEntry(
            word: word,
            phonetics: phonetics,
            senses: senses.isEmpty
                ? [DictionaryEntry.Sense(partOfSpeech: nil, definition: stripped, examples: [])]
                : senses,
            sourceLabel: sourceLabel
        )
    }

    private static func extractPhonetics(from raw: String) -> [DictionaryEntry.Phonetic] {
        var found: [DictionaryEntry.Phonetic] = []
        // Pipes around IPA chunk: NOAD writes "word | ˈwərd |"; Oxford 牛津高阶 writes
        // "Real | BrE rɪəl, AmE ri(ə)l |". The chunk can contain regional markers.
        let pipePattern = #"\|\s*([^|]{1,80}?)\s*\|"#
        if let regex = try? NSRegularExpression(pattern: pipePattern) {
            let nsRaw = raw as NSString
            let matches = regex.matches(in: raw, range: NSRange(location: 0, length: nsRaw.length))
            for m in matches.prefix(2) where m.numberOfRanges > 1 {
                let s = nsRaw.substring(with: m.range(at: 1))
                let split = splitRegionalPhonetics(s)
                if !split.isEmpty {
                    found.append(contentsOf: split)
                } else if looksLikeIPA(s) {
                    found.append(.init(region: .generic, ipa: s))
                }
            }
        }
        // Slashes: "/ɪˈfɛm(ə)rəl/"
        let slashPattern = #"\/([^\/]{2,40})\/"#
        if let regex = try? NSRegularExpression(pattern: slashPattern) {
            let nsRaw = raw as NSString
            let matches = regex.matches(in: raw, range: NSRange(location: 0, length: nsRaw.length))
            for m in matches.prefix(4) where m.numberOfRanges > 1 {
                let s = nsRaw.substring(with: m.range(at: 1))
                if looksLikeIPA(s), found.allSatisfy({ $0.ipa != s }) {
                    found.append(.init(region: .generic, ipa: s))
                }
            }
        }
        return found
    }

    /// Split a phonetic chunk like "BrE rɪəl, AmE ri(ə)l" into per-region entries.
    /// Returns empty if no regional marker is detected (caller falls back to .generic).
    private static func splitRegionalPhonetics(_ s: String) -> [DictionaryEntry.Phonetic] {
        guard s.contains("BrE") || s.contains("AmE") || s.range(of: "UK", options: .literal) != nil
              || s.range(of: "US", options: .literal) != nil else { return [] }

        var phonetics: [DictionaryEntry.Phonetic] = []
        // Split on commas / semicolons; each part may begin with BrE / AmE / UK / US.
        let parts = s.components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for part in parts {
            let (region, ipa) = stripRegionPrefix(part)
            let trimmedIPA = ipa.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedIPA.isEmpty, looksLikeIPA(trimmedIPA) else { continue }
            phonetics.append(.init(region: region, ipa: trimmedIPA))
        }
        return phonetics
    }

    private static func stripRegionPrefix(_ s: String) -> (DictionaryEntry.Phonetic.Region, String) {
        let prefixes: [(String, DictionaryEntry.Phonetic.Region)] = [
            ("BrE", .uk), ("AmE", .us),
            ("UK:", .uk), ("US:", .us),
            ("UK", .uk), ("US", .us)
        ]
        for (prefix, region) in prefixes {
            if s.hasPrefix(prefix) {
                let rest = String(s.dropFirst(prefix.count))
                return (region, rest.trimmingCharacters(in: CharacterSet.whitespaces.union(.init(charactersIn: ":"))))
            }
        }
        return (.generic, s)
    }

    private static func looksLikeIPA(_ s: String) -> Bool {
        let ipaIndicators: Set<Character> = [
            "ə", "ɪ", "ʊ", "ɛ", "æ", "ɑ", "ɔ", "ʌ", "ŋ", "θ", "ð", "ʃ", "ʒ", "ˈ", "ˌ"
        ]
        return s.contains { ipaIndicators.contains($0) }
    }

    private static func strippedHeader(_ raw: String, word: String, phonetics: [DictionaryEntry.Phonetic]) -> String {
        var s = raw
        if s.lowercased().hasPrefix(word.lowercased()) {
            s = String(s.dropFirst(word.count))
        }
        // Strip leading IPA-bearing pipe block: "| əˈfem(ə)rəl |"
        if let firstBar = s.firstIndex(of: "|") {
            let after = s.index(after: firstBar)
            if let secondBar = s[after...].firstIndex(of: "|") {
                s = String(s[s.index(after: secondBar)...])
            }
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let posKeywords: [String] = [
        "noun", "verb", "adjective", "adverb", "pronoun", "preposition",
        "conjunction", "interjection", "article", "determiner", "abbreviation",
        // Localized forms appearing in some Apple dictionaries
        "名词", "动词", "形容词", "副词", "代词", "介词", "连词", "感叹词", "缩略"
    ]

    private static func extractSenses(from text: String) -> [DictionaryEntry.Sense] {
        // Oxford 牛津高阶 (Eudic dictionary in macOS Dictionary.app) marks major sections
        // with "A.", "B.", "C." letters before the part-of-speech. Try that format first
        // since it's unambiguous; fall back to POS-keyword scanning otherwise.
        if let sections = extractLetterSections(from: text), !sections.isEmpty {
            var senses: [DictionaryEntry.Sense] = []
            for section in sections {
                senses.append(contentsOf: splitNumberedSenses(section.body, partOfSpeech: section.pos))
            }
            return senses
        }

        // Split on POS keywords. Matches are positions where a sense block likely starts.
        var ranges: [(NSRange, String)] = []
        let nsText = text as NSString
        for keyword in posKeywords {
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: keyword))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
            for m in matches {
                ranges.append((m.range, keyword))
            }
        }
        ranges.sort { $0.0.location < $1.0.location }

        guard !ranges.isEmpty else {
            return splitNumberedSenses(text, partOfSpeech: nil)
        }

        var senses: [DictionaryEntry.Sense] = []
        for (i, entry) in ranges.enumerated() {
            let start = entry.0.location + entry.0.length
            let end = (i + 1 < ranges.count) ? ranges[i + 1].0.location : nsText.length
            guard end > start else { continue }
            let block = nsText.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !block.isEmpty else { continue }
            let pos = entry.1
            senses.append(contentsOf: splitNumberedSenses(block, partOfSpeech: pos))
        }
        return senses
    }

    /// Recognize section markers like "A. adjective", "B. for real adjective phrase",
    /// "C. adverb", "D. noun". Returns nil if no markers found.
    /// Splits each section into (pos chip, body for sense parsing), with the heading
    /// text (less the POS keyword) prepended to the body so its content survives.
    private static func extractLetterSections(from text: String) -> [(pos: String, body: String)]? {
        let nsText = text as NSString
        let pattern = #"(?:^|\s)([A-Z])\.\s"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return nil }

        var sections: [(pos: String, body: String)] = []
        for (i, m) in matches.enumerated() {
            let sectionStart = m.range.location + m.range.length
            let sectionEnd = (i + 1 < matches.count) ? matches[i + 1].range.location : nsText.length
            guard sectionEnd > sectionStart else { continue }
            let sectionText = nsText.substring(with: NSRange(location: sectionStart, length: sectionEnd - sectionStart))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sectionText.isEmpty else { continue }

            let (pos, remainder) = splitOffPOS(sectionText)
            sections.append((pos: pos, body: remainder))
        }
        return sections
    }

    /// Pull a POS keyword out of `text` and return (chip, rest). Scans the first
    /// few words; prefers phrasal POS ("phrase", "idiom") over base POS so that
    /// e.g. "for real adjective phrase informal" becomes ("phrase", "for real adjective informal").
    private static func splitOffPOS(_ text: String) -> (pos: String, remaining: String) {
        let phrasal: Set<String> = ["phrase", "idiom", "expression"]
        let basePos: Set<String> = Set(posKeywords.map { $0.lowercased() })

        // Scan up to the first 8 words.
        var word = text.startIndex
        var charsScanned = 0
        var bestMatch: (kind: Int, range: Range<String.Index>)? = nil  // kind: 0=phrasal, 1=base
        while word < text.endIndex, charsScanned < 8 {
            // skip whitespace
            while word < text.endIndex, text[word].isWhitespace {
                word = text.index(after: word)
            }
            guard word < text.endIndex else { break }
            var end = word
            while end < text.endIndex, !text[end].isWhitespace {
                end = text.index(after: end)
            }
            let token = String(text[word..<end])
            let cleaned = token.lowercased().trimmingCharacters(in: CharacterSet.punctuationCharacters)
            if phrasal.contains(cleaned) {
                bestMatch = (0, word..<end)
                break // phrasal wins; stop scanning
            } else if basePos.contains(cleaned), bestMatch == nil {
                bestMatch = (1, word..<end)
                // keep scanning in case a phrasal one comes later
            }
            word = end
            charsScanned += 1
        }

        guard let bestMatch else {
            // Fall back: first word as POS, rest stays.
            var firstEnd = text.startIndex
            while firstEnd < text.endIndex, !text[firstEnd].isWhitespace {
                firstEnd = text.index(after: firstEnd)
            }
            let first = String(text[..<firstEnd])
            let rest = String(text[firstEnd...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (first, rest)
        }

        let posWord = String(text[bestMatch.range])
        // Build remainder = (text before POS) + (text after POS), trimmed.
        let before = text[..<bestMatch.range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let after = text[bestMatch.range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let remainder = [before, after].filter { !$0.isEmpty }.joined(separator: " ")
        return (posWord.lowercased(), remainder)
    }

    /// Within a single POS block, split numbered senses if present. Recognizes both
    /// ASCII digits (NOAD: "1 …  2 …") and circled digits (Oxford 牛津高阶: "① … ② …",
    /// also ❶❷ for some dictionaries).
    private static func splitNumberedSenses(_ block: String, partOfSpeech: String?) -> [DictionaryEntry.Sense] {
        let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Marker patterns:
        // - circled digits ①…⑳ (U+2460..U+2473) and ㉑…㉟ (U+3251..U+325F)
        // - filled circled digits ❶…❿ (U+2776..U+277F)
        // - ASCII digit 1–99 followed by optional period
        // (Inline literal codepoints — ICU regex doesn't accept Swift's "\u{…}" escape.)
        let pattern = #"(?:^|[\s\)\]])([①-⑳㉑-㉟❶-❿]|\d{1,2}\.?)(?=\s)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [definitionToSense(trimmed, partOfSpeech: partOfSpeech)]
        }
        let nsBlock = trimmed as NSString
        let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: nsBlock.length))
        guard !matches.isEmpty else {
            return [definitionToSense(trimmed, partOfSpeech: partOfSpeech)]
        }

        var senses: [DictionaryEntry.Sense] = []
        for (i, m) in matches.enumerated() {
            // Capture group 1 holds the marker; the segment text begins right after it.
            let markerRange = m.range(at: 1)
            let start = markerRange.location + markerRange.length
            let end = (i + 1 < matches.count) ? matches[i + 1].range.location : nsBlock.length
            guard end > start else { continue }
            let text = nsBlock.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            senses.append(definitionToSense(text, partOfSpeech: partOfSpeech))
        }
        return senses.isEmpty
            ? [definitionToSense(trimmed, partOfSpeech: partOfSpeech)]
            : senses
    }

    private static func definitionToSense(_ text: String, partOfSpeech: String?) -> DictionaryEntry.Sense {
        var definition = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var examples: [String] = []

        // Oxford 牛津高阶 (Eudic dictionary in macOS Dictionary.app) uses U+25B8 ▸ to
        // introduce examples, with each subsequent example starting with another ▸.
        // The chunk before the first ▸ is the definition (with optional usage hint
        // and Chinese gloss); chunks after are example sentences. If the text starts
        // with ▸, there's no definition — every chunk is an example.
        if definition.contains("\u{25B8}") {
            let startsWithMarker = definition.trimmingCharacters(in: .whitespacesAndNewlines)
                .hasPrefix("\u{25B8}")
            let parts = definition
                .components(separatedBy: "\u{25B8}")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !parts.isEmpty {
                if startsWithMarker {
                    definition = ""
                    examples = parts
                } else {
                    definition = parts[0]
                    examples = Array(parts.dropFirst())
                }
                return DictionaryEntry.Sense(
                    partOfSpeech: partOfSpeech,
                    definition: definition,
                    examples: examples
                )
            }
        }

        // Some dictionaries use " · " (middle dot) instead.
        let middleDotParts = definition
            .components(separatedBy: " · ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if middleDotParts.count >= 2 {
            definition = middleDotParts[0]
            examples = Array(middleDotParts.dropFirst())
            return DictionaryEntry.Sense(
                partOfSpeech: partOfSpeech,
                definition: definition,
                examples: examples
            )
        }

        // NOAD-style fallback: "<short def>: <example>" with `|` chaining further examples.
        if let colonIdx = definition.firstIndex(of: ":") {
            let after = definition.index(after: colonIdx)
            let exampleChunk = String(definition[after...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !exampleChunk.isEmpty, exampleChunk.count < 400 {
                examples = exampleChunk
                    .split(separator: "|", omittingEmptySubsequences: true)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if examples.isEmpty { examples = [exampleChunk] }
                definition = String(definition[..<colonIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return DictionaryEntry.Sense(
            partOfSpeech: partOfSpeech,
            definition: definition,
            examples: examples
        )
    }
}
