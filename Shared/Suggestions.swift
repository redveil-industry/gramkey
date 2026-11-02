import UIKit

/// Word suggestions for the strip above the keys. Third-party keyboards can't use Apple's predictive model;
/// UITextChecker (on-device dictionary: spelling guesses + completions) is the public API available to them.
enum Suggestions {
    private static let checker = UITextChecker()
    private static let language = UITextChecker.availableLanguages.first { $0.hasPrefix("en") } ?? "en_US"

    /// The word being typed: trailing letters/apostrophes left of the cursor.
    static func currentWord(before: String) -> String {
        String(before.reversed().prefix { $0.isLetter || $0 == "'" }.reversed())
    }

    /// The word before the one being typed, if only spaces separate them (punctuation breaks the chain).
    static func previousWord(before: String) -> String? {
        let rest = before.dropLast(currentWord(before: before).count)
        let trimmed = String(rest.reversed().drop { $0 == " " }.reversed())
        guard trimmed.last?.isLetter == true || trimmed.last == "'" else { return nil }
        let w = currentWord(before: trimmed)
        return w.isEmpty ? nil : w
    }

    static func isSentenceStart(_ before: String) -> Bool {
        let t = before.trimmingCharacters(in: .whitespaces)
        return t.isEmpty || t.hasSuffix(".") || t.hasSuffix("!") || t.hasSuffix("?") || t.hasSuffix("\n")
    }

    /// Up to `limit` candidates (completions and spelling fixes interleaved), cased like the typed word, excluding the word itself.
    static func candidates(for word: String, limit: Int = 2) -> [String] {
        guard !word.isEmpty else { return [] }
        let range = NSRange(location: 0, length: (word as NSString).length)
        let misspelled = checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false,
                                                       language: language).location != NSNotFound
        // Completions (frequency-ordered) suit partial words: "keyb" → keyboard. Guesses fix typos: "teh" → the.
        // Interleave so the strip offers the best of each; drop multi-word/hyphen guesses and possessives.
        let guesses = (misspelled ? checker.guesses(forWordRange: range, in: word, language: language) ?? [] : [])
            .filter { !$0.contains(" ") && !$0.contains("-") }
        let completions = (checker.completions(forPartialWordRange: range, in: word, language: language) ?? [])
            .filter { !$0.hasSuffix("'s") }
        var raw: [String] = []
        for i in 0..<max(guesses.count, completions.count) {
            if i < completions.count { raw.append(completions[i]) }
            if i < guesses.count { raw.append(guesses[i]) }
        }
        var seen: Set<String> = [word.lowercased()]
        return Array(raw.map { matchCase($0, to: word) }.filter { seen.insert($0.lowercased()).inserted }.prefix(limit))
    }

    /// UITextChecker loads its lexicon lazily and returns partial results until then; call once at keyboard load.
    static func warmUp() { _ = candidates(for: "th") }

    static func matchCase(_ s: String, to word: String) -> String {
        if word.count > 1, word == word.uppercased() { return s.uppercased() }
        if word.first?.isUppercase == true { return s.prefix(1).uppercased() + s.dropFirst() }
        return s
    }
}
