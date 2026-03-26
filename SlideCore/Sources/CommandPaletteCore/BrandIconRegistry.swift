import Foundation

// MARK: - Brand Icon Registry

public enum BrandIconRegistry {
    // Map of service name to icon asset name
    public static let brandIcons: [String: String] = [
        // AI Services
        "ChatGPT": "ChatGPT",
        "Claude": "Claude",
        "Perplexity": "Perplexity",
        
        // Development
        "GitHub": "GitHub",
        
        // Productivity
        "Notion": "Notion",
        "Linear": "Linear",
        
        // Google Services
        "Google": "Google",
        "Google Docs": "GoogleDocs",
        "Google Sheets": "GoogleSheets",
        "Google Calendar": "GoogleCalendar",
        
        // Social & Media
        "X": "X",
        "Twitter": "X", // Alias
        "Discord": "Discord",
        "YouTube": "YouTube",
        "Spotify": "Spotify",
        "Reddit": "Reddit",
        "Hacker News": "YC"
    ]
    
    // Generate Brandfetch brand icon URL from domain (fallback for dynamic content)
    public static func generateBrandIconUrl(_ domain: String) -> String {
        let clientId = "1id5V3AaQCCdmkWxzPr" // public Brandfetch CDN client id
        return "https://cdn.brandfetch.io/\(domain)/icon/theme/light/fallback/lettermark/h/400/w/400?c=\(clientId)"
    }
    
    // Get icon identifier for a service name
    public static func iconIdentifier(for serviceName: String) -> String? {
        if let assetName = brandIcons[serviceName] {
            return "asset:\(assetName)"
        }
        return nil
    }
    
    // Get icon identifier for a domain (for dynamic content like favicons)
    public static func iconIdentifier(forDomain domain: String) -> String {
        // First check if we have a cached asset for common domains
        let normalizedDomain = domain
            .replacingOccurrences(of: "www.", with: "")
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .components(separatedBy: "/").first ?? domain
        
        // Map common domains to service names
        let domainToService: [String: String] = [
            "chat.openai.com": "ChatGPT",
            "openai.com": "ChatGPT",
            "claude.ai": "Claude",
            "perplexity.ai": "Perplexity",
            "github.com": "GitHub",
            "notion.so": "Notion",
            "linear.app": "Linear",
            "docs.google.com": "Google Docs",
            "sheets.google.com": "Google Sheets",
            "calendar.google.com": "Google Calendar",
            "google.com": "Google",
            "x.com": "X",
            "twitter.com": "X",
            "discord.com": "Discord",
            "youtube.com": "YouTube",
            "spotify.com": "Spotify",
            "open.spotify.com": "Spotify",
            "reddit.com": "Reddit",
            "news.ycombinator.com": "Hacker News",
            "ycombinator.com": "Hacker News"
        ]
        
        if let serviceName = domainToService[normalizedDomain],
           let assetName = brandIcons[serviceName] {
            return "asset:\(assetName)"
        }
        
        // Fallback to Brandfetch URL for unknown domains
        return generateBrandIconUrl(normalizedDomain)
    }
}