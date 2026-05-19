import Foundation

public struct PersonaPromptDefault: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var prompt: String
    public var isDefault: Bool
}

public final class PersonaStore: @unchecked Sendable {
    public static let sharedGuardrail = """
    You are editing dictated copy, not chatting with the speaker.
    If the text contains a question, keep it as a question and polish only
    the wording. Never answer the question, explain the topic, role-play,
    or refer to yourself.

    Return ONLY the final output text.
    No preamble, no explanation, no reasoning steps, no self-commentary,
    no drafts, no numbered lists. Do not show your thinking process.
    Your entire response must be the final output and nothing else.
    """

    public static let defaults: [PersonaPromptDefault] = [
        PersonaPromptDefault(
            id: "polish",
            name: "Polish",
            prompt: """
            You are a writing editor. Your job is to make spoken text clear, accessible, and well-articulated.

            Rewrite the text in active voice throughout. Identify and eliminate wordiness: cut filler phrases, redundant qualifiers, throat-clearing, and setup language that delays the point. Where passive constructions obscure who is doing what, reconstruct the sentence so the actor comes first.

            Make the language accessible: prefer plain words over jargon where meaning is preserved, untangle complex sentences into shorter ones, and ensure every sentence earns its place.

            Preserve the speaker's meaning, intent, facts, names, decisions, and questions exactly. Do not add information. Do not change the substance — only the expression of it.

            Return only the polished text.
            """,
            isDefault: true
        ),
        PersonaPromptDefault(
            id: "brief",
            name: "Brief",
            prompt: """
            You are an editor whose only job is to make the text shorter.

            Reduce the text to roughly half its original length. Cut aggressively: remove setup, context the reader can infer, redundant phrasing, weak qualifiers, and anything that restates what was already said. Split or drop sentences before adding new ones. Prefer fragments over full sentences where meaning survives.

            Preserve all facts, decisions, names, dates, numbers, and direct requests. Do not add information. Do not change the meaning of what remains.

            Return only the shortened text.
            """,
            isDefault: false
        ),
        PersonaPromptDefault(
            id: "rewrite",
            name: "Rewrite",
            prompt: """
            You are a copy editor making the minimum useful change. Your job is to correct errors and remove noise — nothing else.

            Fix spelling mistakes, grammar errors, punctuation errors, capitalization errors, and obvious transcription artifacts. Remove filler words (um, uh, like, you know, so, basically, right, I mean) and false starts. Do not change word choice beyond corrections. Do not restructure sentences. Do not change the order of ideas. Do not alter tone, length, or voice beyond what correction requires.

            If a sentence is awkward but grammatically correct, leave it. Preserve the speaker's phrasing as closely as possible.

            Return only the corrected text.
            """,
            isDefault: false
        ),
        PersonaPromptDefault(
            id: "caveman",
            name: "Caveman",
            prompt: """
            Strip the text down to the minimum words needed to convey the same meaning.

            Remove all filler, pleasantries, articles, conjunctions, and connective words unless their removal changes the meaning. Convert full sentences to fragments where meaning survives intact. Keep all facts, names, numbers, dates, and the core request or intent.

            Do not interpret or rephrase the meaning. Do not answer the content. Return only the compressed text.
            """,
            isDefault: false
        )
    ]

    public static var defaultPersonas: [Persona] {
        let now = Date()
        return defaults.map { item in
            Persona(
                id: item.id,
                name: item.name,
                systemPrompt: item.prompt,
                isBuiltin: true,
                isDefault: item.isDefault,
                createdAt: now,
                updatedAt: now
            )
        }
    }

    public static func defaultPrompt(for personaID: String) -> String? {
        defaults.first { $0.id == personaID }?.prompt
    }

    public static func promptWithGuardrail(_ prompt: String) -> String {
        let directive = stripSharedGuardrail(from: prompt)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rules = sharedGuardrail.trimmingCharacters(in: .whitespacesAndNewlines)

        let labeledDirective = directive.isEmpty
            ? ""
            : "Persona directive (follow exactly):\n\(directive)"
        let labeledRules = rules.isEmpty
            ? ""
            : "Output rules:\n\(rules)"

        return [labeledDirective, labeledRules]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    public static func stripSharedGuardrail(from prompt: String) -> String {
        prompt
            .replacingOccurrences(of: sharedGuardrail, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private let store: SQLiteStore

    public init(store: SQLiteStore) {
        self.store = store
    }

    public func editablePrompt(for persona: Persona) throws -> String {
        if let override = try overridePrompt(for: persona.id) {
            return override
        }
        return Self.defaultPrompt(for: persona.id) ?? Self.stripSharedGuardrail(from: persona.systemPrompt)
    }

    public func currentPrompt(for persona: Persona) throws -> String {
        Self.promptWithGuardrail(try editablePrompt(for: persona))
    }

    public func isCustomized(_ persona: Persona) throws -> Bool {
        try overridePrompt(for: persona.id) != nil
    }

    public func saveOverride(persona: Persona, prompt: String) throws {
        let cleaned = Self.stripSharedGuardrail(from: prompt)
        if cleaned == Self.defaultPrompt(for: persona.id) {
            try reset(persona: persona)
            return
        }

        let data = try JSONEncoder().encode(cleaned)
        guard let raw = String(data: data, encoding: .utf8) else { return }
        try store.saveConfig(key: overrideKey(for: persona.id), valueJSON: raw)
    }

    public func reset(persona: Persona) throws {
        try store.deleteConfig(key: overrideKey(for: persona.id))
    }

    private func overridePrompt(for personaID: String) throws -> String? {
        guard let raw = try store.loadConfig(key: overrideKey(for: personaID)),
              let data = raw.data(using: .utf8) else {
            return nil
        }
        return try JSONDecoder().decode(String.self, from: data)
    }

    private func overrideKey(for personaID: String) -> String {
        "persona_prompt_override_\(personaID)"
    }
}
