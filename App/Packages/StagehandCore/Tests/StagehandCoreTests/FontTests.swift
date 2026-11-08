import CoreGraphics
import Foundation
@testable import StagehandCore
import StagehandModel
import SwiftUI
import Testing

@MainActor
@Suite struct FontTests {
    @Test func theFixtureFontsPostScriptNameIsRead() throws {
        let name = try LiveFontRegistry().postScriptName(of: TestResources.data("PressStart2P-Regular.ttf"), fileName: "PressStart2P-Regular.ttf")
        #expect(name == "PressStart2P-Regular")
    }
    
    @Test func textRendersInTheRegisteredFontNotTheSystemFont() async throws {
        let names = try await LiveFontRegistry().register(["PressStart2P-Regular.ttf": TestResources.data("PressStart2P-Regular.ttf")])
        #expect(names == ["PressStart2P-Regular"])
        
        func render(_ name: String) -> CGImage? {
            ImageRenderer(content: Text("Stagehand").font(.custom(name, fixedSize: 40)).fixedSize()).cgImage
        }
        
        let custom = try #require(render("PressStart2P-Regular"))
        let fallback = try #require(render("NotARealFont-Regular"))
        
        // Press Start 2P is a wide pixel font: the same text is far wider than in the system font.
        #expect(Double(custom.width) > Double(fallback.width) * 1.4)
    }
    
    @Test func anUnreadableFontIsRefused() {
        #expect(throws: FontError.unreadable("x.ttf")) {
            try LiveFontRegistry().postScriptName(of: Data("not a font".utf8), fileName: "x.ttf")
        }
    }
}
