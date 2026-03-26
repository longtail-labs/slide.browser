import Foundation
import FirebaseAI
import FirebaseCore

// Centralized AI service for Gemini via Firebase AI Logic
enum AIError: LocalizedError {
    case emojiGenerationFailed(String)
    case invalidResponse
    case firebaseNotConfigured
    
    var errorDescription: String? {
        switch self {
        case .emojiGenerationFailed(let message):
            return message
        case .invalidResponse:
            return "Invalid response from AI service"
        case .firebaseNotConfigured:
            return "Firebase is not configured"
        }
    }
}

public final class AIService {
    public static let shared = AIService()
    
    // Using Google AI (Gemini Developer API) for quick start with free tier
    private lazy var ai = FirebaseAI.firebaseAI(backend: .googleAI())
    
    // Text-focused model for generating emojis and titles
    private lazy var textModel: GenerativeModel = { [unowned self] in
        self.ensureFirebaseConfigured()
        return self.ai.generativeModel(modelName: "gemini-2.0-flash-001")
    }()
    
    private init() {}
    
    // MARK: - Task emoji generation
    public struct TaskMetadata: Codable {
        public let emoji: String
        public let suggestedTitle: String?
    }
    
    /// Generate an emoji for a task based on its title
    public func generateEmojiForTask(title: String) async throws -> String {
        let prompt = """
        Generate a single emoji that best represents this task or activity: "\(title)"
        
        Return JSON with:
        - emoji: a single emoji character that represents the task
        - suggestedTitle: optional improved title if the original is unclear (null if title is good)
        
        Examples:
        - "Research competitors" → {"emoji": "🔍", "suggestedTitle": null}
        - "Meeting with team" → {"emoji": "👥", "suggestedTitle": null}
        - "Write blog post" → {"emoji": "✍️", "suggestedTitle": null}
        - "stuff" → {"emoji": "📦", "suggestedTitle": "Organize items"}
        
        Be creative and avoid overusing common emojis. Match the emoji to the specific context.
        """
        
        do {
            ensureFirebaseConfigured()
            
            // Define schema for structured output
            let jsonSchema = Schema.object(
                properties: [
                    "emoji": .string(),
                    "suggestedTitle": .string()
                ],
                optionalProperties: ["suggestedTitle"]
            )
            
            let model = ai.generativeModel(
                modelName: "gemini-2.0-flash-001",
                generationConfig: GenerationConfig(
                    responseMIMEType: "application/json",
                    responseSchema: jsonSchema
                )
            )
            
            let response = try await model.generateContent(prompt)
            
            guard let jsonText = response.text,
                  let jsonData = jsonText.data(using: .utf8) else {
                throw AIError.invalidResponse
            }
            
            let metadata = try JSONDecoder().decode(TaskMetadata.self, from: jsonData)
            return metadata.emoji
            
        } catch {
            print("[AIService] Emoji generation failed: \(error)")
            // Return a default emoji if generation fails
            return "📝"
        }
    }
    
    /// Generate emoji for multiple tasks in batch (more efficient)
    public func generateEmojisForTasks(titles: [String]) async throws -> [String: String] {
        guard !titles.isEmpty else { return [:] }
        
        let titlesJson = titles.map { "\"\($0)\"" }.joined(separator: ", ")
        let prompt = """
        Generate appropriate emojis for these tasks:
        [\(titlesJson)]
        
        Return JSON with a "tasks" array where each item has:
        - title: the original task title
        - emoji: a single emoji that represents the task
        
        Be creative and match each emoji to its specific context.
        """
        
        do {
            ensureFirebaseConfigured()
            
            // Define schema for batch response
            let jsonSchema = Schema.object(
                properties: [
                    "tasks": .array(
                        items: .object(
                            properties: [
                                "title": .string(),
                                "emoji": .string()
                            ]
                        )
                    )
                ]
            )
            
            let model = ai.generativeModel(
                modelName: "gemini-2.0-flash-001",
                generationConfig: GenerationConfig(
                    responseMIMEType: "application/json",
                    responseSchema: jsonSchema
                )
            )
            
            let response = try await model.generateContent(prompt)
            
            guard let jsonText = response.text,
                  let jsonData = jsonText.data(using: .utf8) else {
                throw AIError.invalidResponse
            }
            
            struct BatchResponse: Codable {
                let tasks: [TaskItem]
                struct TaskItem: Codable {
                    let title: String
                    let emoji: String
                }
            }
            
            let batchResponse = try JSONDecoder().decode(BatchResponse.self, from: jsonData)
            
            var emojiMap: [String: String] = [:]
            for task in batchResponse.tasks {
                emojiMap[task.title] = task.emoji
            }
            
            return emojiMap
            
        } catch {
            print("[AIService] Batch emoji generation failed: \(error)")
            // Return default emojis for all tasks
            var defaults: [String: String] = [:]
            for title in titles {
                defaults[title] = "📝"
            }
            return defaults
        }
    }
    
    // MARK: - Helper methods
    private func ensureFirebaseConfigured() {
        if FirebaseApp.app() == nil {
            if Thread.isMainThread {
                FirebaseApp.configure()
            } else {
                DispatchQueue.main.sync {
                    FirebaseApp.configure()
                }
            }
        }
    }
}