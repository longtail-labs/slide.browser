import Foundation
import FirebaseAnalytics

public enum AnalyticsService {
    
    // MARK: - Event Names
    private enum Events {
        // Task Management
        static let taskCreated = "task_created"
        static let taskCompleted = "task_completed"
        static let taskDeleted = "task_deleted"
        static let taskStarted = "task_started"
        static let taskSkipped = "task_skipped"
        
        // Object Management
        static let objectAdded = "object_added"
        static let objectDeleted = "object_deleted"
        static let objectReordered = "object_reordered"
        static let objectOpened = "object_opened"
        
        // Navigation
        static let screenChanged = "screen_changed"
        static let tabSwitched = "tab_switched"
        static let commandBarOpened = "command_bar_opened"
        
        // Note Management
        static let noteCreated = "note_created"
        static let noteUpdated = "note_updated"
        
        // AI Features
        static let emojiGenerated = "emoji_generated"
        static let aiRequestFailed = "ai_request_failed"
        
        // App Usage
        static let sessionStart = "session_start"
        static let sessionEnd = "session_end"
        static let darkModeToggled = "dark_mode_toggled"
        static let focusModeToggled = "focus_mode_toggled"
    }
    
    // MARK: - User Properties
    private enum UserProperties {
        static let totalTasksCreated = "total_tasks_created"
        static let totalTasksCompleted = "total_tasks_completed"
        static let totalObjects = "total_objects"
        static let darkModeEnabled = "dark_mode_enabled"
        static let averageTaskTime = "average_task_time"
    }
    
    // MARK: - Screen Names
    public enum ScreenName {
        static let planning = "planning"
        static let working = "working"
        static let taskNote = "task_note"
        static let commandBar = "command_bar"
    }
    
    // MARK: - Core Logging Functions
    
    public static func logEvent(_ event: String, parameters: [String: Any]? = nil) {
        Analytics.logEvent(event, parameters: parameters)
        #if DEBUG
        print("📊 Analytics Event: \(event)")
        if let params = parameters {
            print("   Parameters: \(params)")
        }
        #endif
    }
    
    public static func setUserProperty(_ value: String?, forName name: String) {
        Analytics.setUserProperty(value, forName: name)
        #if DEBUG
        print("👤 User Property: \(name) = \(value ?? "nil")")
        #endif
    }
    
    public static func logScreenView(_ screenName: String, screenClass: String? = nil) {
        var params: [String: Any] = [
            AnalyticsParameterScreenName: screenName
        ]
        if let screenClass = screenClass {
            params[AnalyticsParameterScreenClass] = screenClass
        }
        Analytics.logEvent(AnalyticsEventScreenView, parameters: params)
        #if DEBUG
        print("📱 Screen View: \(screenName)")
        #endif
    }
    
    // MARK: - Task Events
    
    public static func logTaskCreated(title: String, hasEmoji: Bool) {
        logEvent(Events.taskCreated, parameters: [
            "task_title_length": title.count,
            "has_emoji": hasEmoji
        ])
    }
    
    public static func logTaskCompleted(timeSpent: TimeInterval?) {
        var params: [String: Any] = [:]
        if let time = timeSpent {
            params["time_spent_seconds"] = Int(time)
        }
        logEvent(Events.taskCompleted, parameters: params)
    }
    
    public static func logTaskDeleted() {
        logEvent(Events.taskDeleted)
    }
    
    public static func logTaskStarted(taskId: String) {
        logEvent(Events.taskStarted, parameters: [
            "task_id": taskId
        ])
    }
    
    public static func logTaskSkipped() {
        logEvent(Events.taskSkipped)
    }
    
    // MARK: - Object Events
    
    public static func logObjectAdded(type: String, taskId: String) {
        logEvent(Events.objectAdded, parameters: [
            "object_type": type,
            "task_id": taskId
        ])
    }
    
    public static func logObjectDeleted(type: String) {
        logEvent(Events.objectDeleted, parameters: [
            "object_type": type
        ])
    }
    
    public static func logObjectReordered(count: Int) {
        logEvent(Events.objectReordered, parameters: [
            "object_count": count
        ])
    }
    
    public static func logObjectOpened(type: String) {
        logEvent(Events.objectOpened, parameters: [
            "object_type": type
        ])
    }
    
    // MARK: - Navigation Events
    
    public static func logScreenChanged(to screen: String) {
        logEvent(Events.screenChanged, parameters: [
            "screen_name": screen
        ])
        logScreenView(screen)
    }
    
    public static func logTabSwitched(to objectId: String?) {
        logEvent(Events.tabSwitched, parameters: [
            "has_object": objectId != nil
        ])
    }
    
    public static func logCommandBarOpened(mode: String) {
        logEvent(Events.commandBarOpened, parameters: [
            "mode": mode
        ])
    }
    
    // MARK: - Note Events
    
    public static func logNoteCreated(wordCount: Int) {
        logEvent(Events.noteCreated, parameters: [
            "word_count": wordCount
        ])
    }
    
    public static func logNoteUpdated(wordCount: Int) {
        logEvent(Events.noteUpdated, parameters: [
            "word_count": wordCount
        ])
    }
    
    // MARK: - AI Events
    
    public static func logEmojiGenerated(success: Bool, latencyMs: Int? = nil) {
        var params: [String: Any] = [
            "success": success
        ]
        if let latency = latencyMs {
            params["latency_ms"] = latency
        }
        logEvent(Events.emojiGenerated, parameters: params)
    }
    
    public static func logAIRequestFailed(error: String) {
        logEvent(Events.aiRequestFailed, parameters: [
            "error_message": error
        ])
    }
    
    // MARK: - App Usage Events
    
    public static func logSessionStart() {
        logEvent(Events.sessionStart)
    }
    
    public static func logSessionEnd(duration: TimeInterval) {
        logEvent(Events.sessionEnd, parameters: [
            "duration_seconds": Int(duration)
        ])
    }
    
    public static func logDarkModeToggled(enabled: Bool) {
        logEvent(Events.darkModeToggled, parameters: [
            "enabled": enabled
        ])
        setUserProperty(enabled ? "true" : "false", forName: UserProperties.darkModeEnabled)
    }
    
    public static func logFocusModeToggled(enabled: Bool) {
        logEvent(Events.focusModeToggled, parameters: [
            "enabled": enabled
        ])
    }
    
    // MARK: - User Property Updates
    
    public static func updateUserStats(tasksCreated: Int? = nil,
                                      tasksCompleted: Int? = nil,
                                      totalObjects: Int? = nil,
                                      averageTaskTime: TimeInterval? = nil) {
        if let created = tasksCreated {
            setUserProperty("\(created)", forName: UserProperties.totalTasksCreated)
        }
        if let completed = tasksCompleted {
            setUserProperty("\(completed)", forName: UserProperties.totalTasksCompleted)
        }
        if let objects = totalObjects {
            setUserProperty("\(objects)", forName: UserProperties.totalObjects)
        }
        if let avgTime = averageTaskTime {
            setUserProperty("\(Int(avgTime))", forName: UserProperties.averageTaskTime)
        }
    }
}