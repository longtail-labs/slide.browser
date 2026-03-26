import Foundation
import AppKit

public class ConveyorUpdateChecker {
    public static let shared = ConveyorUpdateChecker()
    
    private init() {}
    
    /// Check for updates using Conveyor's built-in functionality
    /// This will only work in the packaged app where Conveyor symbols are available
    @discardableResult
    public func checkForUpdates() -> Bool {
        // Use dlsym to dynamically look up the conveyor_check_for_updates function
        // RTLD_DEFAULT searches all loaded libraries
        guard let handle = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "conveyor_check_for_updates") else {
            print("[UpdateChecker] conveyor_check_for_updates symbol not found - this is normal in development")
            return false
        }
        
        // Cast the handle to a C function pointer and call it
        typealias CheckForUpdatesFunction = @convention(c) () -> Void
        let checkForUpdates = unsafeBitCast(handle, to: CheckForUpdatesFunction.self)
        
        print("[UpdateChecker] Triggering Conveyor update check...")
        checkForUpdates()
        return true
    }
    
    /// Check if we're running in a Conveyor-packaged app
    public var isConveyorPackaged: Bool {
        // Check if the conveyor_check_for_updates symbol is available
        return dlsym(UnsafeMutableRawPointer(bitPattern: -2), "conveyor_check_for_updates") != nil
    }
}