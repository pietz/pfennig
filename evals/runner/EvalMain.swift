import Agent
import Core
import Darwin
import Foundation

private struct Options {
    var root = URL(fileURLWithPath: "evals/2026-q3")
    var truthFile: URL?
    var model: Model?
    var effort: ReasoningEffort?
    var allCases = false
    var caseIDs: Set<String> = []
    var repeats = 1
    var jobs = 1
    var rulesFile: URL?
    var output: URL?
    var rescoreFile: URL?
    var summaryFile: URL?
    var compareFiles: (old: URL, new: URL)?
    var validateOnly = false

    init(_ arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            let flag = arguments[index]
            if flag == "--validate-only" {
                validateOnly = true
            } else if flag == "--all" {
                allCases = true
            } else if flag == "--compare" {
                guard index + 2 < arguments.count else { throw EvalError.invalid("--compare needs two reports") }
                compareFiles = (URL(fileURLWithPath: arguments[index + 1]), URL(fileURLWithPath: arguments[index + 2]))
                index += 2
            } else {
                index += 1
                guard index < arguments.count else { throw EvalError.invalid("Missing value for \(flag)") }
                let value = arguments[index]
                switch flag {
                case "--root": root = URL(fileURLWithPath: value)
                case "--truth": truthFile = URL(fileURLWithPath: value)
                case "--model":
                    guard let chosen = Model(rawValue: value) else {
                        throw EvalError.invalid("Unknown model \(value); choose \(Model.allCases.map(\.rawValue))")
                    }
                    model = chosen
                case "--effort":
                    guard let chosen = ReasoningEffort(rawValue: value) else {
                        let efforts = ReasoningEffort.allCases.map(\.rawValue)
                        throw EvalError.invalid("Unknown effort \(value); choose \(efforts)")
                    }
                    effort = chosen
                case "--cases": caseIDs = Set(value.split(separator: ",").map(String.init))
                case "--repeats": repeats = Int(value) ?? 0
                case "--jobs": jobs = Int(value) ?? 0
                case "--rules": rulesFile = URL(fileURLWithPath: value)
                case "--output": output = URL(fileURLWithPath: value)
                case "--rescore": rescoreFile = URL(fileURLWithPath: value)
                case "--summary": summaryFile = URL(fileURLWithPath: value)
                default: throw EvalError.invalid("Unknown option: \(flag)")
                }
            }
            index += 1
        }
        guard (1 ... 10).contains(repeats) else { throw EvalError.invalid("--repeats must be 1...10") }
        guard (1 ... 50).contains(jobs) else { throw EvalError.invalid("--jobs must be 1...50") }
    }
}

private struct CaseResult: Codable {
    let id: String
    let repetition: Int
    let outcome: String
    let error: String?
    let agentEvaluated: Bool
    let seconds: Double
    let inputTokens: Int?
    let outputTokens: Int?
    let trace: String?
    let promptFile: String
    let promptSHA256: String
    let fileSHA256: String
    /// Absent in reports written before it was recorded.
    let fileID: Int64?
    var mismatches: [String]
    let bookings: [Buchung]

    var passed: Bool {
        mismatches.isEmpty
    }
}

private struct Report: Codable {
    var generatedAt: String
    let model: String
    let effort: String
    let rulesFile: String?
    let rulesSHA256: String?
    var truthSHA256: String
    var passed: Int
    let total: Int
    let plannedTotal: Int?
    var agentPassed: Int
    let agentTotal: Int
    var cases: [CaseResult]
    var rescoreOf: String?

    mutating func recount() {
        passed = cases.filter(\.passed).count
        agentPassed = cases.filter { $0.agentEvaluated && $0.passed }.count
    }

    var tallies: [String: Stability.Tally] {
        Stability.tally(cases.map { ($0.id, $0.mismatches) })
    }

    /// Mean input and output tokens of the runs that reported usage.
    var tokenText: String {
        let counted = cases.filter { $0.inputTokens != nil }
        guard counted.isEmpty == false else { return "none recorded" }
        let input = counted.reduce(0) { $0 + ($1.inputTokens ?? 0) } / counted.count
        let output = counted.reduce(0) { $0 + ($1.outputTokens ?? 0) } / counted.count
        return "\(input) in, \(output) out"
    }

    static func read(_ url: URL) throws -> Report {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Report.self, from: Data(contentsOf: url))
    }

    func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

@main
enum PfennigEval {
    static func main() async {
        do {
            try await execute()
        } catch {
            fputs("Eval error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func execute() async throws {
        let options = try Options(Array(CommandLine.arguments.dropFirst()))
        if let file = options.summaryFile {
            let report = try Report.read(file)
            print("\(report.passed)/\(report.total) passed; agent-evaluable \(report.agentPassed)/\(report.agentTotal)")
            Stability.summary(report.tallies).forEach { print($0) }
            return
        }
        if let (oldFile, newFile) = options.compareFiles {
            let old = try Report.read(oldFile)
            let new = try Report.read(newFile)
            print(
                "Passed \(old.passed)/\(old.total) → \(new.passed)/\(new.total); agent-evaluable \(old.agentPassed)/\(old.agentTotal) → \(new.agentPassed)/\(new.agentTotal)"
            )
            print("Tokens per run: \(old.tokenText) → \(new.tokenText)")
            Stability.comparison(old.tallies, new.tallies).forEach { print($0) }
            return
        }
        let root = options.root.standardizedFileURL
        let truthURL = options.truthFile ?? root.appending(path: "ground-truth.json")
        let truthData = try Data(contentsOf: truthURL)
        let truth = try GroundTruth.load(truthData, root: root)
        if options.validateOnly {
            print(
                "Valid ground truth: \(truth.cases.filter { $0.expected != nil }.count) bookable, \(truth.cases.filter { $0.expected == nil }.count) controls"
            )
            return
        }
        if let sourceReport = options.rescoreFile {
            try rescore(sourceReport, truth: truth, truthData: truthData, root: root, output: options.output)
            return
        }
        guard let model = options.model, let effort = options.effort,
              options.allCases || options.caseIDs.isEmpty == false
        else {
            throw EvalError.invalid("Choose --model, --effort and either --cases or --all.")
        }
        let selected = options.allCases ? truth.cases : truth.cases.filter { options.caseIDs.contains($0.id) }
        guard selected.isEmpty == false, options.allCases || selected.count == options.caseIDs.count else {
            throw EvalError.invalid("Unknown or empty case selection.")
        }
        let key = try apiKey()
        let rules = try options.rulesFile.map { try String(contentsOf: $0, encoding: .utf8) }
        if let rules, rules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw EvalError.invalid("Rules file is empty.")
        }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let output = (options
            .output ?? URL(fileURLWithPath: "evals/results/\(stamp)-\(model.rawValue)-\(effort.rawValue)"))
            .standardizedFileURL
        guard FileManager.default.fileExists(atPath: output.path) == false else {
            throw EvalError.invalid("Output directory already exists: \(output.path)")
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try truthData.write(to: output.appending(path: "truth-snapshot.json"), options: .atomic)
        var results: [CaseResult] = []
        func saveReport() throws -> Report {
            var report = Report(
                generatedAt: ISO8601DateFormatter().string(from: Date()),
                model: model.rawValue,
                effort: effort.rawValue,
                rulesFile: options.rulesFile?.path,
                rulesSHA256: rules.map { FileIntake.hash(Data($0.utf8)) },
                truthSHA256: FileIntake.hash(truthData),
                passed: 0,
                total: results.count,
                plannedTotal: selected.count * options.repeats,
                agentPassed: 0,
                agentTotal: results.filter(\.agentEvaluated).count,
                cases: results,
                rescoreOf: nil
            )
            report.recount()
            try report.write(to: output.appending(path: "report.json"))
            return report
        }
        // Every run has its own archive, so runs only share the API. Results
        // arrive in any order and are saved as they come.
        let runs = selected.flatMap { item in (1 ... options.repeats).map { (item, $0) } }
        let profile = truth.profile
        let today = truth.today
        let rates = try RateCache(file: truthURL.deletingLastPathComponent().appending(path: "fx-rates.json"))
        let transport = rates.transport(over: Responses.network)
        try await withThrowingTaskGroup(of: CaseResult.self) { group in
            var pending = runs.makeIterator()
            func startNext() {
                guard let (item, repetition) = pending.next() else { return }
                group.addTask {
                    try await LocalDate.$pinnedToday.withValue(today) {
                        try await run(
                            item, repetition: repetition, root: root, output: output, profile: profile,
                            model: model, effort: effort, rules: rules, key: key, transport: transport
                        )
                    }
                }
            }
            for _ in 0 ..< options.jobs {
                startNext()
            }
            while let result = try await group.next() {
                results.append(result)
                _ = try saveReport()
                let fields = result.mismatches.map { String($0.split(separator: ":", maxSplits: 1).first ?? "") }
                print(
                    "\(result.id) #\(result.repetition): \(result.passed ? "PASS" : "FAIL") \(fields.joined(separator: ", "))"
                )
                fflush(stdout)
                startNext()
            }
        }
        let order = Dictionary(uniqueKeysWithValues: selected.enumerated().map { ($1.id, $0) })
        results.sort { (order[$0.id] ?? 0, $0.repetition) < (order[$1.id] ?? 0, $1.repetition) }
        let report = try saveReport()
        print(
            "\(report.passed)/\(results.count) passed; agent-evaluable \(report.agentPassed)/\(report.agentTotal). Report: \(output.appending(path: "report.json").path)"
        )
        Stability.summary(report.tallies).forEach { print($0) }
    }

    /// `OPENAI_API_KEY` from the environment or from `.env` in the working
    /// directory. The eval never touches the app's Keychain entry, so a
    /// rebuilt binary does not ask for Keychain access again.
    private static func apiKey() throws -> String {
        if let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], key.isEmpty == false {
            return key
        }
        let lines = (try? String(contentsOfFile: ".env", encoding: .utf8))?.split(whereSeparator: \.isNewline) ?? []
        for line in lines {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0] == "OPENAI_API_KEY" || parts[0] == "export OPENAI_API_KEY" else {
                continue
            }
            let key = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if key.isEmpty == false {
                return key
            }
        }
        throw EvalError.invalid("Set OPENAI_API_KEY in the environment or in .env.")
    }

    private static func rescore(_ source: URL, truth: GroundTruth, truthData: Data, root: URL, output: URL?) throws {
        var report = try Report.read(source)
        let items = Dictionary(uniqueKeysWithValues: truth.cases.map { ($0.id, $0) })
        for index in report.cases.indices {
            let recorded = report.cases[index]
            guard let item = items[recorded.id] else {
                throw EvalError.invalid("Case missing from ground truth: \(recorded.id)")
            }
            let sourceHash = try FileIntake.hash(Data(contentsOf: root.appending(path: item.file)))
            guard sourceHash == recorded.fileSHA256 else {
                throw EvalError.invalid("Source file changed: \(item.file)")
            }
            report.cases[index].mismatches = EvalScoring.mismatches(
                item,
                outcome: recorded.outcome,
                error: recorded.error,
                bookings: recorded.bookings,
                fileID: recorded.fileID ?? recorded.bookings.first?.belege.first
            )
        }
        report.generatedAt = ISO8601DateFormatter().string(from: Date())
        report.truthSHA256 = FileIntake.hash(truthData)
        report.recount()
        report.rescoreOf = source.path
        let folder = output ?? source.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let suffix = String(report.truthSHA256.prefix(12))
        let reportURL = folder.appending(path: "rescore-\(suffix).json")
        try truthData.write(to: folder.appending(path: "truth-\(suffix).json"), options: .atomic)
        try report.write(to: reportURL)
        print(
            "Rescored \(report.passed)/\(report.total); agent-evaluable \(report.agentPassed)/\(report.agentTotal). Report: \(reportURL.path)"
        )
    }

    private static func run(
        _ item: EvalCase, repetition: Int, root: URL, output: URL,
        profile: GroundTruth.Profile, model: Model, effort: ReasoningEffort, rules: String?, key: String,
        transport: @escaping Transport
    ) async throws -> CaseResult {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pfennig-eval-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let archive = ArchivePaths(folder: folder)
        try archive.create()
        let repository = try Repository(path: archive.databaseFile)
        try repository.saveProfile(Profil(
            name: profile.name,
            ustid: profile.ustid,
            kleinunternehmer: profile.kleinunternehmer
        ))
        try repository.saveAISettings(AISettings(model: model, effort: effort))
        let prompt = try AgentInstructions.build(repository, rulesOverride: rules)
        let promptSHA256 = FileIntake.hash(Data(prompt.utf8))
        let promptFile = "prompt-\(promptSHA256).txt"
        let promptURL = output.appending(path: promptFile)
        if FileManager.default.fileExists(atPath: promptURL.path) == false {
            try prompt.write(to: promptURL, atomically: true, encoding: .utf8)
        }
        // The model sees the file name. A neutral one keeps names such as
        // "12-laptop.pdf" from answering what the document should; a number
        // would be mistaken for the file ID.
        let source = root.appending(path: item.file)
        let input = folder.appending(path: "dokument.\(source.pathExtension)")
        try FileManager.default.copyItem(at: source, to: input)
        let intake = try FileIntake(
            repository: repository,
            path: archive,
            transport: transport,
            key: key,
            rulesOverride: rules
        )
        let started = Date()
        let intakeResult = await intake.process(input)
        let seconds = Date().timeIntervalSince(started)
        let (outcome, error): (String, String?) = switch intakeResult {
        case .booked: ("booked", nil)
        case .alreadyPresent: ("alreadyPresent", nil)
        case let .failed(_, message): ("failed", message)
        }
        let bookings = try repository.allBookings()
        let request = try repository.allRequests().last
        let agentEvaluated = request != nil && EvalScoring.isInfrastructureError(error) == false
        let hash = try FileIntake.hash(Data(contentsOf: source))
        let fileID = try repository.fileID(sha256: hash)
        let mismatches = EvalScoring.mismatches(
            item,
            outcome: outcome,
            error: error,
            bookings: bookings,
            fileID: fileID
        )
        var trace: String?
        if let conversation = request?.konversation {
            trace = "\(item.id)-\(repetition)-trace.json"
            try conversation.write(to: output.appending(path: trace!), atomically: true, encoding: .utf8)
        }
        return CaseResult(
            id: item.id,
            repetition: repetition,
            outcome: outcome,
            error: error,
            agentEvaluated: agentEvaluated,
            seconds: seconds,
            inputTokens: request?.eingabeTokens,
            outputTokens: request?.ausgabeTokens,
            trace: trace,
            promptFile: promptFile,
            promptSHA256: promptSHA256,
            fileSHA256: hash,
            fileID: fileID,
            mismatches: mismatches,
            bookings: bookings
        )
    }
}
