import AppKit
import SwiftUI

/// The main application window: sidebar navigation with all configuration,
/// activity, and help pages. Replaces the old tabbed Settings dialog.
struct MainWindowView: View {
    @ObservedObject var updaterController: UpdaterController
    let onAppearAction: () -> Void

    @State private var selection: Section = .gettingStarted

    enum Section: String, CaseIterable, Identifiable {
        case gettingStarted
        case general
        case hotkey
        case speech
        case refinement
        case vocabulary
        case history
        case about

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .gettingStarted: return "Getting Started"
            case .general: return "General"
            case .hotkey: return "Hotkey"
            case .speech: return "Speech"
            case .refinement: return "Refinement"
            case .vocabulary: return "Vocabulary"
            case .history: return "History"
            case .about: return "About"
            }
        }

        var symbol: String {
            switch self {
            case .gettingStarted: return "sparkles"
            case .general: return "gearshape.fill"
            case .hotkey: return "keyboard.fill"
            case .speech: return "waveform"
            case .refinement: return "wand.and.stars"
            case .vocabulary: return "text.book.closed.fill"
            case .history: return "clock.arrow.circlepath"
            case .about: return "info"
            }
        }

        var iconColor: Color {
            switch self {
            case .gettingStarted: return .green
            case .general: return .gray
            case .hotkey: return .indigo
            case .speech: return .blue
            case .refinement: return .purple
            case .vocabulary: return .orange
            case .history: return .teal
            case .about: return .secondary
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
                .navigationTitle(selection.title)
        }
        .frame(minWidth: 760, minHeight: 540)
        .onAppear(perform: onAppearAction)
    }

    private var sidebar: some View {
        List(selection: $selection) {
            SwiftUI.Section("Setup") {
                sidebarRow(.gettingStarted)
            }

            SwiftUI.Section("Configure") {
                sidebarRow(.general)
                sidebarRow(.hotkey)
                sidebarRow(.speech)
                sidebarRow(.refinement)
                sidebarRow(.vocabulary)
            }

            SwiftUI.Section("Activity") {
                sidebarRow(.history)
            }

            SwiftUI.Section("Help") {
                sidebarRow(.about)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
    }

    private func sidebarRow(_ section: Section) -> some View {
        Label {
            Text(section.title)
        } icon: {
            Image(systemName: section.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(section.iconColor.gradient)
                )
        }
        .tag(section)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .gettingStarted:
            GettingStartedPage()
        case .general:
            GeneralPage(updaterController: updaterController)
        case .hotkey:
            HotkeyPage()
        case .speech:
            SpeechPage()
        case .refinement:
            RefinementPage()
        case .vocabulary:
            VocabularyPage()
        case .history:
            HistoryPage()
        case .about:
            AboutPage()
        }
    }
}

#Preview {
    MainWindowView(updaterController: UpdaterController(), onAppearAction: {})
}
