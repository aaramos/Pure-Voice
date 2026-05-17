import Foundation

public enum PersonaDefaults {
    public static let noReasoningInstruction = """
    Return ONLY the final polished text.
    No preamble, no explanation, no reasoning steps, no self-commentary,
    no drafts, no numbered lists. Do not show your thinking process.
    Your entire response must be the polished message and nothing else.
    """

    public static let defaultPersonas: [Persona] = {
        let now = Date()
        return [
            Persona(
                id: "clarity",
                name: "Clarity",
                systemPrompt: """
                Rewrite the following spoken text for maximum clarity.
                Fix grammar, remove filler words, untangle run-on sentences,
                and organize ideas into a logical, easy-to-follow flow.
                Preserve all facts, decisions, requests, and intent exactly as stated.
                Do not add new information or change the meaning.
                Return ONLY the rewritten text.
                No preamble, no explanation, no commentary, no reasoning.

                \(noReasoningInstruction)
                """,
                isBuiltin: true,
                isDefault: true,
                createdAt: now,
                updatedAt: now
            ),
            Persona(
                id: "ultra-concise",
                name: "Ultra Concise",
                systemPrompt: """
                Compress the following spoken text to its absolute minimum.
                Remove everything that is not essential.
                One idea per sentence. No filler, no repetition, no softening language.
                Preserve all facts, decisions, and requests.
                Return ONLY the compressed text.
                No preamble, no explanation, no commentary, no reasoning.

                \(noReasoningInstruction)
                """,
                isBuiltin: true,
                isDefault: false,
                createdAt: now,
                updatedAt: now
            )
        ]
    }()
}
