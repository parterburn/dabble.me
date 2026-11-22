import Foundation

/// "Did you mean …?" under the email field, for a mistyped common domain (gmial.com,
/// yahoo.con). It only suggests: the address as typed still goes through. The web has the same
/// list and rules (`app/assets/javascripts/email_typo.js`).
enum EmailTypo {
    static let domains = [
        "gmail.com", "googlemail.com", "yahoo.com", "ymail.com", "hotmail.com", "outlook.com",
        "live.com", "msn.com", "icloud.com", "me.com", "mac.com", "aol.com", "comcast.net",
        "att.net", "sbcglobal.net", "verizon.net", "protonmail.com", "proton.me", "fastmail.com",
        "hey.com", "yahoo.co.uk", "hotmail.co.uk", "btinternet.com", "gmx.com", "gmx.de",
        "web.de", "mail.com", "zoho.com",
    ]

    static let tldFixes = ["con": "com", "cmo": "com", "ocm": "com", "vom": "com", "xom": "com", "comm": "com",
                           "om": "com", "cm": "com", "nte": "net", "ner": "net", "nett": "net", "orgg": "org", "ogr": "org"]

    /// The address with its domain fixed, or nil when it looks right (or isn't close to anything).
    static func suggestion(for email: String) -> String? {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let at = email.lastIndex(of: "@"), at != email.startIndex else { return nil }
        let local = String(email[..<at])
        let domain = String(email[email.index(after: at)...])
        guard !domain.isEmpty, !domains.contains(domain) else { return nil }

        var best: String?
        var bestDistance = 3
        for candidate in domains {
            let d = distance(domain, candidate)
            if d < bestDistance { best = candidate; bestDistance = d }
        }
        if let best, bestDistance == 1 || (bestDistance == 2 && domain.count >= 6) {
            return "\(local)@\(best)"
        }

        if let dot = domain.lastIndex(of: "."), dot != domain.startIndex,
           let fix = tldFixes[String(domain[domain.index(after: dot)...])] {
            return "\(local)@\(domain[...dot])\(fix)"
        }
        return nil
    }

    /// Optimal string alignment distance: insertions, deletions, substitutions and swaps of
    /// neighbouring letters each count one.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
    }
}
