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
                id: "default",
                name: "Default",
                systemPrompt: """
                Rewrite the user's dictated text into clear, concise prose. Preserve the user's intent, facts, and point of view. Remove filler, repetition, false starts, and unnecessary hedging. Use a balanced tone with moderate formality. Return only the polished text.

                \(noReasoningInstruction)
                """,
                isBuiltin: true,
                isDefault: true,
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
