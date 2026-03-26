import Foundation
import FirebaseRemoteConfig
import Observation

@MainActor
@Observable
public final class RemoteConfigService {
    // Keys in Firebase Remote Config
    private enum Keys: String {
        case aiEmojiGenerationEnabled = "ai_emoji_generation_enabled"
        case maxTasksPerDay = "max_tasks_per_day"
        case maxObjectsPerTask = "max_objects_per_task"
        case enabledFeatures = "enabled_features"
        case debugMode = "debug_mode"
        case aiModelName = "ai_model_name"
    }
    
    // Backing remote config instance
    private let remoteConfig = RemoteConfig.remoteConfig()
    
    // Published values with sensible defaults
    public var aiEmojiGenerationEnabled: Bool = true
    public var maxTasksPerDay: Int = 100
    public var maxObjectsPerTask: Int = 50
    public var enabledFeatures: [String] = []
    public var debugMode: Bool = false
    public var aiModelName: String = "gemini-2.0-flash-001"
    
    private var listenerHandle: NSObjectProtocol?
    
    public init() {
        // In-app defaults
        let defaults: [String: NSObject] = [
            Keys.aiEmojiGenerationEnabled.rawValue: NSNumber(value: true),
            Keys.maxTasksPerDay.rawValue: NSNumber(value: 100),
            Keys.maxObjectsPerTask.rawValue: NSNumber(value: 50),
            Keys.enabledFeatures.rawValue: NSArray(),
            Keys.debugMode.rawValue: NSNumber(value: false),
            Keys.aiModelName.rawValue: "gemini-2.0-flash-001" as NSString
        ]
        remoteConfig.setDefaults(defaults)
        
        // Dev-friendly fetch interval; server-side throttling still applies
        let settings = RemoteConfigSettings()
        #if DEBUG
        settings.minimumFetchInterval = 0 // Fetch immediately in debug
        #else
        settings.minimumFetchInterval = 3600 // 1 hour in production
        #endif
        remoteConfig.configSettings = settings
    }
    
    public func start() async {
        await fetchAndActivate()
        startRealtimeListener()
    }
    
    public func fetchAndActivate() async {
        do {
            let result = try await remoteConfig.fetchAndActivate()
            switch result {
            case .successFetchedFromRemote:
                print("[RemoteConfig] Successfully fetched from remote")
            case .successUsingPreFetchedData:
                print("[RemoteConfig] Using pre-fetched data")
            case .error:
                print("[RemoteConfig] Error during fetch")
            @unknown default:
                print("[RemoteConfig] Unknown fetch result")
            }
            applyValues()
        } catch {
            print("[RemoteConfig] Fetch error: \(error)")
            // Apply whatever is currently cached/defaulted
            applyValues()
        }
    }
    
    private func startRealtimeListener() {
        // Real-time updates (iOS SDK 10.7.0+)
        remoteConfig.addOnConfigUpdateListener { [weak self] update, error in
            guard error == nil, let self else {
                if let error = error {
                    print("[RemoteConfig] Update listener error: \(error)")
                }
                return
            }
            
            // Log which keys were updated
            if let updatedKeys = update?.updatedKeys {
                print("[RemoteConfig] Updated keys: \(updatedKeys)")
            }
            
            // Activate updated values, then apply to published properties
            self.remoteConfig.activate { _, _ in
                Task { @MainActor in
                    self.applyValues()
                }
            }
        }
    }
    
    private func applyValues() {
        aiEmojiGenerationEnabled = remoteConfig[Keys.aiEmojiGenerationEnabled.rawValue].boolValue
        maxTasksPerDay = remoteConfig[Keys.maxTasksPerDay.rawValue].numberValue.intValue
        maxObjectsPerTask = remoteConfig[Keys.maxObjectsPerTask.rawValue].numberValue.intValue
        debugMode = remoteConfig[Keys.debugMode.rawValue].boolValue
        aiModelName = remoteConfig[Keys.aiModelName.rawValue].stringValue ?? "gemini-2.0-flash-001"
        
        // Parse enabled features as comma-separated string or JSON array
        let featuresValue = remoteConfig[Keys.enabledFeatures.rawValue].stringValue ?? ""
        if featuresValue.starts(with: "[") {
            // Try to parse as JSON array
            if let data = featuresValue.data(using: .utf8),
               let features = try? JSONDecoder().decode([String].self, from: data) {
                enabledFeatures = features
            }
        } else if !featuresValue.isEmpty {
            // Parse as comma-separated values
            enabledFeatures = featuresValue.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        }
        
        // Clamp to sane minimums
        if maxTasksPerDay < 1 { maxTasksPerDay = 1 }
        if maxObjectsPerTask < 1 { maxObjectsPerTask = 1 }
        
        #if DEBUG
        print("[RemoteConfig] Applied values:")
        print("  - aiEmojiGenerationEnabled: \(aiEmojiGenerationEnabled)")
        print("  - maxTasksPerDay: \(maxTasksPerDay)")
        print("  - maxObjectsPerTask: \(maxObjectsPerTask)")
        print("  - enabledFeatures: \(enabledFeatures)")
        print("  - debugMode: \(debugMode)")
        print("  - aiModelName: \(aiModelName)")
        #endif
    }
    
    // Helper method to check if a feature is enabled
    public func isFeatureEnabled(_ feature: String) -> Bool {
        return enabledFeatures.contains(feature)
    }
    
    // Method to manually refresh config
    public func refresh() async {
        await fetchAndActivate()
    }
}