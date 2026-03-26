import SwiftUI
import CoreGraphics
import CoreText

public struct SlideFont {
    public static func registerFonts() {
        let fonts = [
            "Lato-Regular",
            "Lato-Bold", 
            "Lato-Light",
            "Lato-Black",
            "Lato-Thin",
            "Lato-Italic",
            "Lato-BoldItalic",
            "Lato-LightItalic",
            "Lato-BlackItalic",
            "Lato-ThinItalic",
            "DMSans-VariableFont_opsz,wght",
            "DMSans-Italic-VariableFont_opsz,wght",
            "Marcellus-Regular"
        ]
        
        fonts.forEach { fontName in
            registerFont(fontName: fontName, fontExtension: "ttf")
        }
    }
    
    fileprivate static func registerFont(fontName: String, fontExtension: String) {
        guard let fontURL = Bundle.module.url(forResource: fontName, withExtension: fontExtension),
              let fontDataProvider = CGDataProvider(url: fontURL as CFURL),
              let font = CGFont(fontDataProvider) else {
            print("Failed to register font: \(fontName).\(fontExtension)")
            return
        }
        
        var error: Unmanaged<CFError>?
        CTFontManagerRegisterGraphicsFont(font, &error)
        
        if let error = error {
            print("Error registering font \(fontName): \(error.takeUnretainedValue())")
        }
    }
}

extension Font {
    public static let latoRegular = Font.custom("Lato-Regular", size: 16)
    public static let latoBold = Font.custom("Lato-Bold", size: 16)
    public static let latoLight = Font.custom("Lato-Light", size: 16)
    
    public static func lato(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .bold:
            return .custom("Lato-Bold", size: size)
        case .semibold, .heavy:
            return .custom("Lato-Bold", size: size)
        case .black:
            return .custom("Lato-Black", size: size)
        case .light:
            return .custom("Lato-Light", size: size)
        case .thin, .ultraLight:
            return .custom("Lato-Thin", size: size)
        default:
            return .custom("Lato-Regular", size: size)
        }
    }
    
    public static func dmSans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        return .custom("DMSans-VariableFont_opsz,wght", size: size)
    }
    
    public static func marcellus(_ size: CGFloat) -> Font {
        return .custom("Marcellus-Regular", size: size)
    }
}