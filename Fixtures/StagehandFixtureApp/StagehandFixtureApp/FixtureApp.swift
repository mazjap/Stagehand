import StagehandScene
import SwiftUI

/// A tiny app for the capture runner's end-to-end tests, on iPhone, Apple Watch and the Mac. Its scene comes from the
/// capture kit.
@main
struct FixtureApp: App {
    private let scene = FixtureScene(rawValue: StagehandScene.current() ?? "") ?? .light
    
    var body: some Scene {
        #if os(macOS)
        let size = StagehandScene.requestedWindowSize ?? CGSize(width: 1440, height: 900)
        
        WindowGroup {
            FixtureView(scene: scene)
                .frame(width: size.width, height: size.height)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(size)
        #else
        WindowGroup {
            FixtureView(scene: scene)
        }
        #endif
    }
}

enum FixtureScene: String {
    case dark
    case light
}

struct FixtureView: View {
    private let scene: FixtureScene
    
    init(scene: FixtureScene) {
        self.scene = scene
    }
    
    #if os(watchOS)
    private let iconSize: Double = 40
    private let rows = 2
    #else
    private let iconSize: Double = 96
    private let rows = 4
    #endif
    
    /// A greeting in the test language, so captures in two languages differ.
    ///
    /// NOTE: - This reads the preferred languages, not `Locale.current`, which only offers the languages the app is
    /// localized for, and the fixture isn't.
    private var greeting: String {
        switch Locale.preferredLanguages.first.map({ Locale.Language(identifier: $0).languageCode?.identifier }) {
        case "de": "Hallo"
        case "fr": "Bonjour"
        default: "Hello"
        }
    }
    
    var body: some View {
        ZStack {
            (scene == .dark ? Color(white: 0.06) : Color(red: 0.96, green: 0.94, blue: 0.88))
                .ignoresSafeArea()
            
            VStack(spacing: 12) {
                Image(systemName: scene == .dark ? "moon.stars.fill" : "sun.max.fill")
                    .font(.system(size: iconSize))
                    .foregroundStyle(scene == .dark ? Color.yellow : Color.orange)
                
                Text("\(greeting), \(scene == .dark ? "Dark" : "Light")")
                    .font(.title2.bold())
                    .foregroundStyle(scene == .dark ? Color.white : Color.black)
                
                ForEach(0..<rows, id: \.self) { row in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(scene == .dark ? Color(white: 0.2) : Color.white)
                        .frame(height: 36)
                        .overlay(alignment: .leading) {
                            Text("Row \(row + 1)")
                                .padding(.horizontal)
                                .foregroundStyle(scene == .dark ? Color.white : Color.black)
                        }
                }
            }
            .padding()
        }
        .accessibilityElement(children: .contain)
        .overlay {
            Text("staged: true")
                .font(.caption2)
                .opacity(0.01)
                .accessibilityIdentifier("fixture-ready")
        }
    }
}

#Preview {
    FixtureView(scene: .dark)
}
