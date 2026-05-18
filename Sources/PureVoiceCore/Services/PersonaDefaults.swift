import Foundation

public enum PersonaDefaults {
    public static let defaultPersonaID = "polish"
    public static let defaultPersonaName = "Polish"
    public static let noReasoningInstruction = PersonaStore.sharedGuardrail
    public static let defaultPersonas: [Persona] = PersonaStore.defaultPersonas
}
