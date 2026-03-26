#!/usr/bin/env swift

import Foundation

// MARK: - Service Registry

struct Service {
    let name: String
    let domain: String
}

let services = [
    // AI Services
    Service(name: "ChatGPT", domain: "openai.com"),
    Service(name: "Claude", domain: "claude.ai"),
    Service(name: "Perplexity", domain: "perplexity.ai"),
    
    // Development
    Service(name: "GitHub", domain: "github.com"),
    
    // Productivity
    Service(name: "Notion", domain: "notion.so"),
    Service(name: "Linear", domain: "linear.app"),
    
    // Google Services
    Service(name: "Google", domain: "google.com"),
    Service(name: "GoogleDocs", domain: "docs.google.com"),
    Service(name: "GoogleSheets", domain: "sheets.google.com"),
    Service(name: "GoogleCalendar", domain: "calendar.google.com"),
    
    // Social
    Service(name: "X", domain: "x.com"),
    Service(name: "Discord", domain: "discord.com"),
    Service(name: "YouTube", domain: "youtube.com"),
    Service(name: "Spotify", domain: "spotify.com"),
    Service(name: "Reddit", domain: "reddit.com"),
]

// MARK: - Brandfetch Configuration

let brandfetchClientId = "1id5V3AaQCCdmkWxzPr" // public Brandfetch CDN client id

func generateBrandIconUrl(_ domain: String, size: Int = 400) -> String {
    return "https://cdn.brandfetch.io/\(domain)/icon/theme/light/fallback/lettermark/h/\(size)/w/\(size)?c=\(brandfetchClientId)"
}

// MARK: - Download Functions

func downloadImage(from urlString: String, to destinationPath: String) async throws {
    guard let url = URL(string: urlString) else {
        throw URLError(.badURL)
    }
    
    let (data, response) = try await URLSession.shared.data(from: url)
    
    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw URLError(.badServerResponse)
    }
    
    try data.write(to: URL(fileURLWithPath: destinationPath))
}

// MARK: - Asset Catalog Generation

func createImageSetContents(name: String) -> String {
    return """
    {
      "images" : [
        {
          "filename" : "\(name).png",
          "idiom" : "universal",
          "scale" : "1x"
        },
        {
          "filename" : "\(name)@2x.png",
          "idiom" : "universal",
          "scale" : "2x"
        },
        {
          "filename" : "\(name)@3x.png",
          "idiom" : "universal",
          "scale" : "3x"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """
}

// MARK: - Main Execution

func main() async {
    let outputDir = "BrandIcons"
    let assetsDir = "\(outputDir).xcassets"
    
    // Create directories
    let fileManager = FileManager.default
    try? fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true, attributes: nil)
    try? fileManager.createDirectory(atPath: assetsDir, withIntermediateDirectories: true, attributes: nil)
    
    // Create Assets.xcassets Contents.json
    let assetsContents = """
    {
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """
    try? assetsContents.write(toFile: "\(assetsDir)/Contents.json", atomically: true, encoding: .utf8)
    
    print("Downloading brand icons...")
    print("=" * 50)
    
    for service in services {
        print("Processing \(service.name)...")
        
        // Create imageset directory
        let imagesetDir = "\(assetsDir)/\(service.name).imageset"
        try? fileManager.createDirectory(atPath: imagesetDir, withIntermediateDirectories: true, attributes: nil)
        
        // Download icons at different sizes
        let sizes = [
            (scale: "1x", size: 100, filename: "\(service.name).png"),
            (scale: "2x", size: 200, filename: "\(service.name)@2x.png"),
            (scale: "3x", size: 300, filename: "\(service.name)@3x.png")
        ]
        
        var downloadSuccess = true
        
        for sizeConfig in sizes {
            let url = generateBrandIconUrl(service.domain, size: sizeConfig.size)
            let outputPath = "\(imagesetDir)/\(sizeConfig.filename)"
            
            do {
                try await downloadImage(from: url, to: outputPath)
                print("  ✓ Downloaded \(sizeConfig.scale) (\(sizeConfig.size)x\(sizeConfig.size))")
            } catch {
                print("  ✗ Failed to download \(sizeConfig.scale): \(error.localizedDescription)")
                downloadSuccess = false
            }
        }
        
        if downloadSuccess {
            // Create Contents.json for the imageset
            let contents = createImageSetContents(name: service.name)
            try? contents.write(toFile: "\(imagesetDir)/Contents.json", atomically: true, encoding: .utf8)
            print("  ✓ Created imageset for \(service.name)")
        }
        
        // Also save standalone PNGs for direct use
        let standaloneUrl = generateBrandIconUrl(service.domain, size: 400)
        let standalonePath = "\(outputDir)/\(service.name).png"
        
        do {
            try await downloadImage(from: standaloneUrl, to: standalonePath)
            print("  ✓ Saved standalone icon")
        } catch {
            print("  ✗ Failed to save standalone: \(error.localizedDescription)")
        }
        
        print("")
    }
    
    print("=" * 50)
    print("Download complete!")
    print("")
    print("Assets catalog created at: \(assetsDir)")
    print("Standalone icons saved to: \(outputDir)/")
    print("")
    print("To use in Xcode:")
    print("1. Drag \(assetsDir) into your Xcode project")
    print("2. Reference icons with: Image(\"\(services[0].name)\")")
    print("")
    print("Or copy to existing Assets.xcassets:")
    print("cp -R \(assetsDir)/*.imageset /path/to/your/Assets.xcassets/")
}

// Helper for string multiplication
extension String {
    static func * (lhs: String, rhs: Int) -> String {
        return String(repeating: lhs, count: rhs)
    }
}

// Run the async main function
Task {
    await main()
    exit(0)
}

RunLoop.main.run()