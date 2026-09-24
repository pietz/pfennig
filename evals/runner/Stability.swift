import Foundation

/// Pass rates by case and failing fields across repeats, and what changed
/// between two runs. One run of a case says little; the tally over repeats
/// separates a steady error from noise.
enum Stability {
    struct Tally: Equatable {
        var runs = 0
        var passes = 0
        /// Failed runs per field, named by the mismatch prefix.
        var fields: [String: Int] = [:]

        var rate: String {
            "\(passes)/\(runs)"
        }

        var fieldText: String {
            fields.sorted { ($1.value, $0.key) < ($0.value, $1.key) }
                .map { $0.value > 1 ? "\($0.key)×\($0.value)" : $0.key }
                .joined(separator: ", ")
        }
    }

    static func tally(_ runs: [(id: String, mismatches: [String])]) -> [String: Tally] {
        var tallies: [String: Tally] = [:]
        for run in runs {
            var tally = tallies[run.id] ?? Tally()
            tally.runs += 1
            if run.mismatches.isEmpty {
                tally.passes += 1
            }
            for field in Set(run.mismatches.map(field)) {
                tally.fields[field, default: 0] += 1
            }
            tallies[run.id] = tally
        }
        return tallies
    }

    static func field(_ mismatch: String) -> String {
        String(mismatch.split(separator: ":", maxSplits: 1).first ?? "")
    }

    /// Every case that failed at least once, then the failing fields overall.
    static func summary(_ tallies: [String: Tally]) -> [String] {
        let failing = tallies.filter { $0.value.passes < $0.value.runs }.sorted { $0.key < $1.key }
        guard failing.isEmpty == false else { return ["Every case passed every run."] }
        var fields: [String: Int] = [:]
        for tally in tallies.values {
            fields.merge(tally.fields, uniquingKeysWith: +)
        }
        let overall = Tally(fields: fields).fieldText
        return ["Failing cases (passed/runs, failed runs per field):"]
            + failing.map { "  \($0.key)  \($0.value.rate)  \($0.value.fieldText)" }
            + ["Failed runs per field: \(overall)"]
    }

    /// Cases whose pass rate changed, better first. A case in only one run
    /// is listed as added or dropped.
    static func comparison(_ old: [String: Tally], _ new: [String: Tally]) -> [String] {
        func share(_ tally: Tally) -> Double {
            Double(tally.passes) / Double(max(tally.runs, 1))
        }
        var better: [String] = []
        var worse: [String] = []
        for id in Set(old.keys).intersection(new.keys).sorted() {
            guard let before = old[id], let after = new[id], share(before) != share(after) else { continue }
            let line = "  \(id)  \(before.rate) → \(after.rate)  \(after.fieldText)"
            if share(after) > share(before) {
                better.append(line)
            } else {
                worse.append(line)
            }
        }
        let added = Set(new.keys).subtracting(old.keys).sorted()
        let dropped = Set(old.keys).subtracting(new.keys).sorted()
        var lines: [String] = []
        if better.isEmpty == false {
            lines += ["Better:"] + better
        }
        if worse.isEmpty == false {
            lines += ["Worse:"] + worse
        }
        if added.isEmpty == false {
            lines.append("Only in the new run: \(added.joined(separator: ", "))")
        }
        if dropped.isEmpty == false {
            lines.append("Only in the old run: \(dropped.joined(separator: ", "))")
        }
        return lines.isEmpty ? ["No case changed its pass rate."] : lines
    }
}
