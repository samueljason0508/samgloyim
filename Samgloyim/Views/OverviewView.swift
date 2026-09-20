import SwiftUI
import Charts

struct OverviewView: View {
    @EnvironmentObject var store: FinanceStore
    var add: () -> Void
    var imports: () -> Void
    var settings: () -> Void
    var showActivity: () -> Void
    @State private var selectedTransaction: Transaction?
    @State private var showAllCategories = false
    /// The day being traced on the chart, while a finger is down on it.
    @State private var traced: (day: Int, amount: Double)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                masthead
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("A LITTLE CLARITY, EVERY DAY").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.7).foregroundStyle(Palette.muted)
                        Text("Make room for\nwhat matters.").font(.system(size: 35, weight: .regular, design: .serif)).tracking(-1).lineSpacing(-1)
                    }
                    Spacer()
                    Image(systemName: "leaf").font(.system(size: 37, weight: .ultraLight)).rotationEffect(.degrees(-25)).foregroundStyle(Palette.forest).padding(.bottom, 9).padding(.trailing, 8)
                }
                VStack(spacing: 12) { MonthSelector(); AccountFilter() }
                spendingCard
                // Location is only ever asked for on a tap, so this is safe to show everywhere.
                BestCardHere()
                quickActions
                if store.data.isDemo {
                    Button(action: settings) {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkle")
                            Text("You’re exploring sample data.").fontWeight(.medium)
                            Spacer()
                            Text("Make it yours").fontWeight(.semibold)
                            Image(systemName: "arrow.up.right").font(.system(size: 9))
                        }.font(.system(size: 10)).padding(.vertical, 12).padding(.horizontal, 13).background(Palette.sage.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain)
                }
                categoryCard
                VStack(spacing: 12) {
                    SectionHeading(title: "Recent activity", detail: "See all", action: showActivity)
                    if store.filteredTransactions.isEmpty {
                        EmptyState(symbol: "tray", title: "A fresh start", detail: "Add a transaction or import a receipt to see your money more clearly.").pocketCard()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(store.filteredTransactions.prefix(4).enumerated()), id: \.element.id) { index, transaction in
                                Button { selectedTransaction = transaction } label: { TransactionRow(transaction: transaction) }.buttonStyle(.plain)
                                if index < min(store.filteredTransactions.count, 4) - 1 { Divider().overlay(Palette.line).padding(.leading, 56) }
                            }
                        }.pocketCard(padding: 16)
                    }
                }
                Text("A little awareness goes a long way.").font(.system(size: 12, design: .serif)).italic().foregroundStyle(Palette.muted).frame(maxWidth: .infinity).padding(.vertical, 8)
            }.padding(.horizontal, 22).padding(.bottom, 22)
        }.pageBackground().toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selectedTransaction) { TransactionEditor(transaction: $0) }
    }

    private var masthead: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "leaf.fill").font(.system(size: 13)).foregroundStyle(Palette.lime).frame(width: 29, height: 29).background(Palette.forest, in: RoundedRectangle(cornerRadius: 10))
                Text("samgloyim").font(.system(size: 23, weight: .semibold, design: .rounded)).tracking(-1)
            }
            Spacer()
            Button(action: settings) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 17)).frame(width: 42, height: 42).background(.white, in: Circle()).overlay(Circle().stroke(Palette.line))
            }.accessibilityLabel("Settings")
        }.padding(.top, 9)
    }

    private var spendingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(tracedCaption, systemImage: traced == nil ? "arrow.up.right" : "hand.point.up.left.fill").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.4).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Circle().fill(Palette.lime).frame(width: 5, height: 5)
                Text(store.selectedAccountID == nil ? "ALL ACCOUNTS" : "ACCOUNT").font(.system(size: 8, weight: .semibold)).tracking(0.8).foregroundStyle(Palette.lime)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Money.format(traced.map { Int(($0.amount * 100).rounded()) } ?? store.spent)).font(.system(size: 43, weight: .regular, design: .rounded)).tracking(-2).minimumScaleFactor(0.6).lineLimit(1).accessibilityIdentifier("monthly-spending")
                Spacer(minLength: 0)
            }.foregroundStyle(.white)
            sparkline.frame(height: 116).accessibilityLabel("Cumulative monthly spending, by day")
        }.padding(22).background(Palette.forest, in: RoundedRectangle(cornerRadius: 25))
    }

    private var sparkline: some View {
        let points = cumulativePoints
        return Chart(points, id: \.day) { point in
            AreaMark(x: .value("Day", point.day), y: .value("Spending", point.amount)).foregroundStyle(LinearGradient(colors: [Palette.lime.opacity(0.20), Palette.lime.opacity(0)], startPoint: .top, endPoint: .bottom)).interpolationMethod(.monotone)
            LineMark(x: .value("Day", point.day), y: .value("Spending", point.amount)).foregroundStyle(Palette.lime).lineStyle(StrokeStyle(lineWidth: 1.8)).interpolationMethod(.monotone)
            if let traced {
                RuleMark(x: .value("Day", traced.day))
                    .foregroundStyle(.white.opacity(0.35)).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                PointMark(x: .value("Day", traced.day), y: .value("Spending", traced.amount))
                    .foregroundStyle(Palette.lime).symbolSize(70)
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        // minimumDistance 0 so a tap reads a value too, not just a drag.
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard let plot = proxy.plotFrame else { return }
                                let x = value.location.x - geometry[plot].origin.x
                                guard let day: Int = proxy.value(atX: x) else { return }
                                traced = Self.nearest(to: day, in: points)
                            }
                            .onEnded { _ in traced = nil }
                    )
            }
        }
        // Recessive by design: the line is the subject, the axes are there to be read when asked.
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel {
                    if let day = value.as(Int.self) { Text(day == 0 ? "1" : "\(day)") }
                }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel {
                    if let amount = value.as(Double.self) { Text(Self.axisMoney(amount)) }
                }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    /// Snap to a day that actually has a reading rather than interpolating between two, so the
    /// number under the finger is one that happened.
    static func nearest(to day: Int, in points: [(day: Int, amount: Double)]) -> (day: Int, amount: Double)? {
        points.min { abs($0.day - day) < abs($1.day - day) }
    }

    private var tracedCaption: String {
        guard let traced, let date = Calendar.current.date(bySetting: .day, value: max(traced.day, 1), of: store.selectedMonth) else {
            return "MONTHLY SPENDING"
        }
        return "BY \(date.formatted(.dateTime.month(.abbreviated).day()).uppercased())"
    }

    /// Axis ticks are for reading the shape, not the exact total — that is the number above the
    /// chart — so they stay short enough not to crowd the plot.
    static func axisMoney(_ amount: Double) -> String {
        amount >= 1000 ? "$\((amount / 1000).formatted(.number.precision(.fractionLength(amount >= 10000 ? 0 : 1))))k"
                       : "$\(Int(amount))"
    }
    /// Sixteen categories is more slices than a donut can carry, so anything under a fortieth of
    /// the month folds into one remainder wedge. The legend beside it still lists every category —
    /// this is about the shape being readable, not about hiding where money went.
    private var donutSlices: [(name: String, amount: Int, color: Color)] {
        let total = max(store.spent, 1)
        let named = store.categoryTotals.filter { Double($0.amount) / Double(total) >= 0.025 }
        let remainder = store.spent - named.reduce(0) { $0 + $1.amount }
        return named.map { (name: $0.category.rawValue, amount: $0.amount, color: $0.category.color) }
            + (remainder > 0 ? [(name: "Everything else", amount: remainder, color: Palette.remainder)] : [])
    }

    private var cumulativePoints: [(day: Int, amount: Double)] {
        let calendar = Calendar.current
        let days = calendar.range(of: .day, in: .month, for: store.selectedMonth)?.count ?? 30
        let lastDay = calendar.isDate(store.selectedMonth, equalTo: Date(), toGranularity: .month) ? calendar.component(.day, from: Date()) : days
        var amount = 0
        return (0...lastDay).map { day in
            amount += store.expenses.filter { calendar.component(.day, from: $0.date) == day }.reduce(0) { $0 + $1.amount }
            return (day, Double(amount) / 100)
        }
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            Button(action: add) { Label("Add expense", systemImage: "plus").frame(maxWidth: .infinity).padding(.vertical, 15).background(.white, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line)) }.accessibilityIdentifier("add-expense")
            Button(action: imports) { Label("Import", systemImage: "tray.and.arrow.down").frame(maxWidth: .infinity).padding(.vertical, 15).background(.white, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line)) }.accessibilityIdentifier("import-transactions")
        }.font(.system(size: 12, weight: .semibold)).buttonStyle(.plain)
    }

    private var categoryCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeading(title: "Where it went", detail: "\(store.categoryTotals.count) categories")
            if store.categoryTotals.isEmpty {
                Text("Your spending breakdown will appear here.").font(.subheadline).foregroundStyle(Palette.muted).padding(.vertical, 20)
            } else {
                HStack(spacing: 22) {
                    Chart(donutSlices, id: \.name) { item in
                        SectorMark(angle: .value("Amount", item.amount), innerRadius: .ratio(0.73), angularInset: 2).cornerRadius(3).foregroundStyle(item.color)
                    }.frame(width: 126, height: 126).chartBackground { _ in
                        VStack(spacing: 4) { Text("\(store.expenses.count)").font(.system(size: 25, weight: .medium, design: .rounded)); Text("purchases").font(.system(size: 9)).foregroundStyle(Palette.muted) }
                    }.accessibilityLabel("Spending by category")
                    VStack(spacing: 12) {
                        ForEach(Array(store.categoryTotals.prefix(showAllCategories ? store.categoryTotals.count : 4)), id: \.category) { item in
                            NavigationLink { CategoryDetailView(category: item.category) } label: {
                                HStack(spacing: 6) {
                                    Circle().fill(item.category.color).frame(width: 6, height: 6)
                                    Text(item.category.rawValue).font(.system(size: 10)).lineLimit(1)
                                    Spacer(minLength: 3)
                                    Text("\(Int((Double(item.amount) / Double(max(store.spent, 1)) * 100).rounded()))%").font(.system(size: 10, weight: .semibold)).monospacedDigit()
                                    Image(systemName: "chevron.right").font(.system(size: 7, weight: .semibold)).foregroundStyle(Palette.muted)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("overview-category-\(item.category.rawValue)")
                        }
                        if store.categoryTotals.count > 4 {
                            Button { withAnimation(.easeInOut(duration: 0.2)) { showAllCategories.toggle() } } label: {
                                HStack(spacing: 4) {
                                    Text(showAllCategories ? "Show fewer" : "+ \(store.categoryTotals.count - 4) more categories")
                                    Image(systemName: "chevron.down").font(.system(size: 7, weight: .semibold)).rotationEffect(.degrees(showAllCategories ? 180 : 0))
                                }.font(.system(size: 9)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("toggle-categories")
                        }
                    }
                }
            }
        }.pocketCard()
    }
}
