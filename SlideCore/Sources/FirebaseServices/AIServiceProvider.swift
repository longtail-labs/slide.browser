import Foundation

// Provider to access AI Service from ObjectBox layer
public final class AIServiceProvider {
    public static let shared = AIServiceProvider()
    
    public private(set) var aiService: AIService?
    
    private init() {
        // AI Service will be available after Firebase is configured
        self.aiService = AIService.shared
    }
    
    public func configure() {
        // Ensure AI service is available
        if aiService == nil {
            aiService = AIService.shared
        }
    }
}