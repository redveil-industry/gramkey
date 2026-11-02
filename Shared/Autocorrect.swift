import UIKit

/// On-device autocorrect + next-word prediction (no network). Noisy-channel ranking:
///   score = −typo cost (keyboard-aware Damerau–Levenshtein) + prior (word frequency, personal history, previous word).
/// Personal memory holds plain alphabetic words/pairs only, lives in the App Group, and can be cleared from the app.
final class WordEngine {
    struct Memory: Codable, Equatable {
        var words: [String: Int] = [:]
        var pairs: [String: [String: Int]] = [:]
    }
    struct Candidate { let word: String; let cost: Double; let score: Double }

    var memory = Memory()
    var replacements: [String: String] = [:]   // UILexicon text replacements: lowercased shortcut → expansion
    var names: Set<String> = []                // contact names etc. (lowercased): never corrected

    private let checker = UITextChecker()
    private let language = UITextChecker.availableLanguages.first { $0.hasPrefix("en") } ?? "en_US"
    private var prefixRanks: [String: [String: Int]] = [:]

    // MARK: Autocorrect

    /// What space should turn `word` into, or nil to leave it alone.
    func correction(for word: String, previous: String? = nil) -> String? {
        let lw = word.lowercased()
        if let expansion = replacements[lw] { return expansion }
        if lw == "i" { return word == "i" ? "I" : nil }
        guard word.count >= 2, !isKnown(word) else { return nil }
        let ranked = rank(word, previous: previous)
        guard let best = ranked.first, best.cost <= 1.6 else { return nil }
        let margin = ranked.count > 1 ? best.score - ranked[1].score : .infinity
        // Short words are easy to "fix" into the wrong thing; demand a clearer win.
        guard margin >= (word.count <= 3 ? 0.8 : 0.3) || best.cost <= 0.35 else { return nil }
        return Suggestions.matchCase(best.word, to: word)
    }

    func isKnown(_ word: String) -> Bool {
        let lw = word.lowercased()
        if names.contains(lw) || (memory.words[lw] ?? 0) >= 2 { return true }
        let r = NSRange(location: 0, length: (word as NSString).length)
        return checker.rangeOfMisspelledWord(in: word, range: r, startingAt: 0, wrap: false,
                                             language: language).location == NSNotFound
    }

    func rank(_ word: String, previous: String?) -> [Candidate] {
        let lw = word.lowercased()
        let r = NSRange(location: 0, length: (lw as NSString).length)
        var pool = Set((checker.guesses(forWordRange: r, in: lw, language: language) ?? [])
            .filter { !$0.contains(" ") && !$0.contains("-") }.map { $0.lowercased() })
        for (w, n) in memory.words where n >= 2 && w.first == lw.first && abs(w.count - lw.count) <= 2 { pool.insert(w) }
        return pool.compactMap { c -> Candidate? in
            let cost = Typo.cost(typed: lw, intended: c)
            guard cost <= 2.5 else { return nil }
            return Candidate(word: c, cost: cost, score: -2.2 * cost + prior(c, previous: previous))
        }
        .sorted { $0.score != $1.score ? $0.score > $1.score : $0.word < $1.word }
    }

    private func prior(_ w: String, previous: String?) -> Double {
        var p = Self.common.contains(w) ? 1.0 : 0
        p += frequency(w)
        p += 0.4 * log(1 + Double(memory.words[w] ?? 0))
        if let prev = previous?.lowercased(), let n = memory.pairs[prev]?[w] { p += 0.8 * log(1 + Double(n)) }
        return p
    }

    /// 0…1. UITextChecker returns completions in frequency order, so a word's rank among the completions of its
    /// two-letter prefix is a corpus-free frequency signal.
    private func frequency(_ w: String) -> Double {
        let prefix = String(w.prefix(2))
        if prefixRanks[prefix] == nil {
            let list = checker.completions(forPartialWordRange: NSRange(location: 0, length: (prefix as NSString).length),
                                           in: prefix, language: language) ?? []
            prefixRanks[prefix] = Dictionary(list.enumerated().map { ($1.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        }
        guard let ranks = prefixRanks[prefix], let i = ranks[w] else { return 0 }
        return 1 - Double(i) / Double(max(ranks.count, 1))
    }

    // MARK: Strip

    /// While typing: the pending correction (if any) plus other options (your words first, then dictionary).
    func suggestions(for word: String, previous: String?) -> (correction: String?, others: [String]) {
        let fix = correction(for: word, previous: previous)
        let lw = word.lowercased()
        let mine = memory.words.filter { $0.key.hasPrefix(lw) && $0.key != lw && $0.value >= 2 }
            .sorted { $0.value > $1.value }.prefix(2).map { Suggestions.matchCase($0.key, to: word) }
        var seen: Set<String> = [lw, fix?.lowercased() ?? ""]
        let others = (mine + Suggestions.candidates(for: word, limit: 3)).filter { seen.insert($0.lowercased()).inserted }
        return (fix, Array(others.prefix(fix == nil ? 2 : 1)))
    }

    /// After a space: what you usually type next, from your own word pairs; generic fallbacks fill the rest.
    func predictions(after previous: String?, sentenceStart: Bool) -> [String] {
        var out: [String] = []
        if let prev = previous?.lowercased(), let next = memory.pairs[prev] {
            out = next.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(3).map(\.key)
        }
        for w in sentenceStart ? ["I", "The", "Thanks"] : ["the", "to", "and"] where out.count < 3 && !out.contains(w.lowercased()) {
            out.append(w)
        }
        return out.map { w in
            if w == "i" { return "I" }
            return sentenceStart ? w.prefix(1).uppercased() + w.dropFirst() : w
        }
    }

    // MARK: Learning

    /// Records a word you kept (and the word before it). Only plain words: no digits/symbols, so tokens and keys stay out.
    func learn(_ word: String, previous: String?) {
        let w = word.lowercased()
        guard (2...24).contains(w.count), w.allSatisfy({ $0.isLetter || $0 == "'" }) else { return }
        memory.words[w, default: 0] += 1
        if let p = previous?.lowercased(), p.allSatisfy({ $0.isLetter || $0 == "'" }) {
            memory.pairs[p, default: [:]][w, default: 0] += 1
        }
        prune()
    }

    /// You undid a correction: treat the original as a real word from now on.
    func reject(_ original: String) {
        let w = original.lowercased()
        memory.words[w] = max(memory.words[w] ?? 0, 2) + 1
    }

    private func prune() {
        if memory.words.count > 6000 {
            memory.words = memory.words.filter { $0.value > 1 }
        }
        if memory.pairs.count > 3000 {
            memory.pairs = memory.pairs.filter { $0.value.values.reduce(0, +) > 1 }
        }
    }

    /// High-frequency English words: a strong prior so "teh" → "the", not "ten".
    static let common: Set<String> = Set("""
    the be to of and a in that have i it for not on with he as you do at this but his by from they we say her she or \
    an will my one all would there their what so up out if about who get which go me when make can like time no just \
    him know take people into year your good some could them see other than then now look only come its over think \
    also back after use two how our work first well way even new want because any these give day most us is are was \
    were been has had did said does doing going thanks thank please yes okay ok hello hi hey sorry today tomorrow \
    tonight love great really very much more here where why need right still should let off same last long little \
    own old big high different small large next early young important few public bad able don't i'm it's can't \
    won't didn't doesn't isn't that's there's you're they're we're i've i'll let's receive believe weird because
    """.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init))
}

/// Keyboard-aware typo cost (optimal-string-alignment Damerau–Levenshtein with QWERTY weights).
enum Typo {
    private static let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map(Array.init)
    private static let neighbors: [Character: Set<Character>] = {
        var n: [Character: Set<Character>] = [:]
        for (r, row) in rows.enumerated() {
            for (i, c) in row.enumerated() {
                var s = Set<Character>()
                for j in [i - 1, i + 1] where row.indices.contains(j) { s.insert(row[j]) }
                if r > 0 { for j in [i, i + 1] where rows[r - 1].indices.contains(j) { s.insert(rows[r - 1][j]) } }   // staggered rows
                if r < 2 { for j in [i - 1, i] where rows[r + 1].indices.contains(j) { s.insert(rows[r + 1][j]) } }
                n[c, default: []].formUnion(s)
            }
        }
        for (c, s) in n { for d in s { n[d, default: []].insert(c) } }   // symmetric
        return n
    }()

    static func adjacent(_ a: Character, _ b: Character) -> Bool { neighbors[a]?.contains(b) ?? false }

    /// Cost of typing `typed` when you meant `intended` (both lowercased). Lower = more plausible typo.
    static func cost(typed: String, intended: String) -> Double {
        let a = Array(typed), b = Array(intended)
        var d = Array(repeating: Array(repeating: 0.0, count: b.count + 1), count: a.count + 1)
        for i in 1...max(a.count, 1) where i <= a.count { d[i][0] = d[i - 1][0] + delete(a, i - 1) }
        for j in 1...max(b.count, 1) where j <= b.count { d[0][j] = d[0][j - 1] + insert(b, j - 1) }
        guard !a.isEmpty, !b.isEmpty else { return d[a.count][b.count] }
        for i in 1...a.count {
            for j in 1...b.count {
                let sub = a[i - 1] == b[j - 1] ? 0 : (adjacent(a[i - 1], b[j - 1]) ? 0.4 : 1.0)
                var best = min(d[i - 1][j - 1] + sub, d[i - 1][j] + delete(a, i - 1), d[i][j - 1] + insert(b, j - 1))
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { best = min(best, d[i - 2][j - 2] + 0.5) }
                d[i][j] = best
            }
        }
        return d[a.count][b.count]
    }

    /// Extra typed char: cheap if it's a doubled letter ("helllo").
    private static func delete(_ a: [Character], _ i: Int) -> Double { i > 0 && a[i] == a[i - 1] ? 0.35 : 0.7 }
    /// Missing char: apostrophes ("dont") and double letters ("helo") are the usual suspects.
    private static func insert(_ b: [Character], _ j: Int) -> Double {
        if b[j] == "'" { return 0.1 }
        return j > 0 && b[j] == b[j - 1] ? 0.35 : 0.7
    }
}
