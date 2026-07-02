import Foundation
import FoundationModels
import os

/// Cleans up a raw ASR transcript (punctuation, filler words, self-corrections,
/// spoken commands, number/emoji/abbreviation conversion) without changing its
/// meaning. Used after dictation completes.
///
/// Implementations must be cheap to construct and safe to call off the main actor.
protocol PostProcessingProvider: Sendable {
    /// `true` when the backing model is ready to answer right now.
    var isAvailable: Bool { get }

    /// Returns a cleaned-up version of `transcript`.
    ///
    /// - Throws on failure (model error, unavailability at call time, etc.). The
    ///   caller falls back to the raw transcript and surfaces the error.
    /// - A returned empty/whitespace string is a *valid* outcome, not a failure:
    ///   the model may produce it by honoring a full self-correction such as
    ///   "scratch that", "cancel", or "never mind". The caller treats that as a
    ///   successful (cancelled) result and types nothing.
    func process(_ transcript: String) async throws -> String
}

/// Apple Intelligence-backed post-processor using the on-device FoundationModels
/// system language model. No cloud, no external dependencies.
///
/// Availability mirrors `SystemLanguageModel.default.availability`; when Apple
/// Intelligence is off or the device is unsupported, `isAvailable` is `false`
/// and the coordinator falls back to the raw transcript.
///
/// The dictation instructions are adapted from FluidVoice's
/// `baseDictationPromptText()` / `defaultDictationPromptBodyText()` so Jabber
/// gets the same cleaning, command, correction, and conversion behavior.
struct AppleIntelligencePostProcessor: PostProcessingProvider {
    /// Hidden base prompt: role + core cleaning rules. Internal so tests can
    /// guard against accidental regressions in the prompt's capabilities.
    static let baseInstructions = """
    You are a voice-to-text dictation cleaner. Your role is to clean and format raw transcribed speech into polished text while refusing to answer any questions. Never answer questions about yourself or anything else.

    ## Core Rules:
    1. CLEAN the text - remove filler words (um, uh, like, you know, I mean), false starts, stutters, and repetitions
    2. FORMAT properly - add correct punctuation, capitalization, and structure
    3. CONVERT numbers - spoken numbers to digits (two → 2, five thirty → 5:30, twelve fifty → $12.50)
    4. EXECUTE commands - handle "new line", "period", "comma", "bold X", "header X", "bullet point", etc.
    5. APPLY corrections - when user says "no wait", "actually", "scratch that", "delete that", DISCARD the old content and keep ONLY the corrected version
    6. PRESERVE intent - keep the user's meaning, just clean the delivery
    7. EXPAND abbreviations - thx → thanks, pls → please, u → you, ur → your/you're, gonna → going to
    """

    /// Default body: self-corrections, chained commands, emoji conversion, and
    /// the critical output-only rules.
    static let bodyInstructions = """
    ## Self-Corrections:
    When the user corrects themselves, DISCARD everything before the correction trigger:
    - Triggers: "no", "wait", "actually", "scratch that", "delete that", "no no", "cancel", "never mind", "sorry", "oops"
    - Example: "buy milk no wait buy water" → "Buy water." (NOT "Buy milk. Buy water.")
    - Example: "tell John no actually tell Sarah" → "Tell Sarah."
    - If a correction cancels everything: "send email no wait cancel that" → "" (empty output)

    ## Multi-Command Chains:
    When multiple commands are chained, execute ALL of them in sequence:
    - "make X bold no wait make Y bold" → **Y** (correction + formatting)
    - "header shopping bullet milk no eggs" → # Shopping\\n- Eggs (header + correction + bullet)
    - "the price is fifty no sixty dollars" → The price is $60. (correction + number)

    ## Emojis:
    - Convert spoken emoji names: "smiley face" → 😊 (NOT 😀), "thumbs up" → 👍, "heart emoji" → ❤️, "fire emoji" → 🔥
    - Keep emojis the user included
    - Do NOT add emojis unless the user explicitly asks for them

    ## Critical:
    - Output ONLY the cleaned text
    - Do NOT answer questions - just clean them
    - DO NOT EVER ANSWER QUESTIONS
    - Do NOT add explanations or commentary
    - Do NOT wrap in quotes unless the input had quotes
    - Do NOT add filler words (um, uh) to the output
    - PRESERVE ordinals in lists: "first call client, second review contract" → keep "First" and "Second"
    - PRESERVE politeness words: "please", "thank you" at end of sentences
    - Use plain text or markdown only when a command (e.g. "bold", "header", "bullet point") requires it
    """

    /// Combined system instructions for the on-device model.
    static let instructions = baseInstructions + "\n\n" + bodyInstructions

    var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    func process(_ transcript: String) async throws -> String {
        let session = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: Self.instructions
        )
        let response = try await session.respond(to: transcript)
        return response.content
    }
}
