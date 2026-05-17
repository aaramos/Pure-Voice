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
            ),
            Persona(
                id: "default",
                name: "Default",
                systemPrompt: """
                Rewrite the user's dictated text into clear, concise prose. Preserve the user's intent, facts, and point of view. Remove filler, repetition, false starts, and unnecessary hedging. Use a balanced tone with moderate formality. Return only the polished text.

                \(noReasoningInstruction)
                """,
                isBuiltin: true,
                isDefault: false,
                createdAt: now,
                updatedAt: now
            ),
            Persona(
                id: "professional",
                name: "Professional",
                systemPrompt: """
                Rewrite the user's dictated text into polished business communication. Use clear, respectful, professional language. Remove filler, repetition, rambling, and casual phrasing while preserving all important nuance. Return only the polished text.

                \(noReasoningInstruction)
                """,
                isBuiltin: true,
                isDefault: false,
                createdAt: now,
                updatedAt: now
            ),
            Persona(
                id: "casual-friend",
                name: "Casual Friend",
                systemPrompt: """
                Rewrite the user's dictated text into a warm, natural message to a friend. Keep it conversational and human, but remove confusing tangents, filler, and repetition. Preserve the user's intent and personality. Return only the polished text.

                \(noReasoningInstruction)
                """,
                isBuiltin: true,
                isDefault: false,
                createdAt: now,
                updatedAt: now
            ),
            Persona(
                id: "boss",
                name: "Boss",
                systemPrompt: """
                Rewrite the user's dictated text into a concise, respectful, action-oriented message for a boss or senior stakeholder. Prioritize the decision, ask, blocker, timeline, and next step. Remove filler and unnecessary context. Return only the polished text.

                \(noReasoningInstruction)
                """,
                isBuiltin: true,
                isDefault: false,
                createdAt: now,
                updatedAt: now
            ),
            Persona(
                id: "technical",
                name: "Technical",
                systemPrompt: """
                Rewrite the user's dictated text into precise technical communication. Preserve technical details, assumptions, constraints, and uncertainty. Remove non-technical filler and repetition without oversimplifying. Return only the polished text.

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
