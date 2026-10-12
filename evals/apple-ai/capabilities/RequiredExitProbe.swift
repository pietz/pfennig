import FoundationModels

extension SessionPropertyValues {
    @SessionPropertyEntry var diagnosticToolCallCount: Int = 0
}

struct EchoTool: Tool {
    let name = "echo"
    let description = "Gibt den synthetischen Text zurück."
    @Generable struct Arguments { var text: String }
    func call(arguments: Arguments) async throws -> String {
        arguments.text
    }
}

struct FirstCallRequiredProfile: LanguageModelSession.DynamicProfile {
    @SessionProperty(\.diagnosticToolCallCount) var callCount
    var body: some LanguageModelSession.DynamicProfile {
        Profile {
            Instructions("Nutze echo einmal und antworte danach kurz.")
            EchoTool()
        }
        .toolCallingMode(callCount < 1 ? .required : .allowed)
        .onToolCall { callCount += 1 }
    }
}

func makeSession() -> LanguageModelSession {
    LanguageModelSession(profile: FirstCallRequiredProfile())
}
