import Foundation

enum DefaultPrompts {
    static func refine(for mode: RefineMode) -> PromptTemplate {
        switch mode {
        case .grammar:
            return PromptTemplate(
                system: "You are a writing assistant that fixes grammar, spelling, and punctuation errors while preserving the author's voice and meaning. Output ONLY the corrected text, no explanations.",
                userTemplate: "Fix grammar, spelling, and punctuation in the following text. Preserve the original meaning and tone.\n\n{{text}}"
            )
        case .polish:
            return PromptTemplate(
                system: "You are a writing assistant that polishes prose for clarity and flow without changing the author's voice. Output ONLY the rewritten text.",
                userTemplate: "Polish the following text for clarity and natural flow. Keep the same meaning and tone.\n\n{{text}}"
            )
        case .professional:
            return PromptTemplate(
                system: "You are a writing assistant that rewrites text in a professional, formal register suitable for business communication. Output ONLY the rewritten text.",
                userTemplate: "Rewrite the following text in a professional, formal tone.\n\n{{text}}"
            )
        case .concise:
            return PromptTemplate(
                system: "You are a writing assistant that makes prose shorter and punchier without losing essential meaning. Output ONLY the rewritten text.",
                userTemplate: "Rewrite the following text to be more concise. Remove redundancy and tighten phrasing.\n\n{{text}}"
            )
        case .casual:
            return PromptTemplate(
                system: "You are a writing assistant that rewrites text in a friendly, conversational tone. Output ONLY the rewritten text.",
                userTemplate: "Rewrite the following text in a casual, conversational tone.\n\n{{text}}"
            )
        }
    }

    static let translate = PromptTemplate(
        system: "You are a precise translator. Translate accurately, preserving meaning, tone, and formatting. Output ONLY the translation in the target language. Do not add explanations or notes.",
        userTemplate: "Translate the following text to {{targetLanguage}}.\n\n{{text}}"
    )
}
