import SwiftUI

enum AppTab: String, CaseIterable {
    case overview = "Overview", activity = "Activity", plan = "Plan", insights = "Insights"
    var symbol: String {
        switch self { case .overview: "square.grid.2x2"; case .activity: "arrow.left.arrow.right"; case .plan: "chart.pie"; case .insights: "sparkles" }
    }
}

enum AppSheet: String, Identifiable {
    case transaction, imports, settings
    var id: String { rawValue }
}

struct RootView: View {
    @State private var tab = AppTab.overview
    @State private var sheet: AppSheet?
    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch tab {
                case .overview: NavigationStack { OverviewView(add: { sheet = .transaction }, imports: { sheet = .imports }, settings: { sheet = .settings }, showActivity: { tab = .activity }, showPlan: { tab = .plan }) }
                case .activity: NavigationStack { ActivityView(add: { sheet = .transaction }, imports: { sheet = .imports }) }
                case .plan: NavigationStack { PlanView() }
                case .insights: NavigationStack { InsightsView() }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.self) { item in
                    Button { tab = item } label: {
                        VStack(spacing: 6) {
                            Image(systemName: item.symbol).font(.system(size: 18, weight: tab == item ? .semibold : .regular)).frame(height: 22)
                            Text(item.rawValue).font(.system(size: 10, weight: tab == item ? .semibold : .medium))
                        }.frame(maxWidth: .infinity).frame(height: 57)
                            .foregroundStyle(tab == item ? Palette.forest : Palette.muted)
                            .background(alignment: .top) { if tab == item { Capsule().fill(Palette.forest).frame(width: 18, height: 3).offset(y: -3) } }
                    }.buttonStyle(.plain).accessibilityIdentifier("tab-\(item.rawValue)").accessibilityAddTraits(tab == item ? .isSelected : [])
                }
            }.padding(.top, 10).padding(.horizontal, 12).background(.white).overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
        }.background(.white).sheet(item: $sheet) { item in
            switch item {
            case .transaction: TransactionEditor()
            case .imports: ImportView()
            case .settings: SettingsView()
            }
        }
    }
}
