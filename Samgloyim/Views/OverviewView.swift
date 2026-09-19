import SwiftUI
import Charts

struct OverviewView: View {
    @EnvironmentObject var store: FinanceStore
    var add: () -> Void
    var imports: () -> Void
    var settings: () -> Void
    var showActivity: () -> Void
    var showPlan: () -> Void
    @State private var selectedTransaction: Transaction?

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
                if let goal = store.data.goals.first {
                    Button(action: showPlan) {
                        HStack(spacing: 15) {
                            Image(systemName: goal.symbol).font(.system(size: 25, weight: .light)).frame(width: 57, height: 65).background(Palette.peach, in: RoundedRectangle(cornerRadius: 16))
                            VStack(alignment: .leading, spacing: 8) {
                                Text("A LITTLE CLOSER").font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1.4).foregroundStyle(Palette.muted)
                                Text(goal.name).font(.system(size: 15, weight: .semibold))
                                ProgressTrack(value: Double(goal.saved) / Double(max(goal.target, 1)), color: Palette.orange)
                                Text("\(Money.format(goal.saved, decimals: false)) of \(Money.format(goal.target, decimals: false)) saved").font(.system(size: 10)).foregroundStyle(Palette.muted)
                            }
                            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Palette.muted)
                        }.pocketCard(padding: 17)
                    }.buttonStyle(.plain)
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
                Label("MONTHLY SPENDING", systemImage: "arrow.up.right").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.4).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Circle().fill(Palette.lime).frame(width: 5, height: 5)
                Text(store.selectedAccountID == nil ? "ALL ACCOUNTS" : "ACCOUNT").font(.system(size: 8, weight: .semibold)).tracking(0.8).foregroundStyle(Palette.lime)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(Money.format(store.spent)).font(.system(size: 43, weight: .regular, design: .rounded)).tracking(-2).minimumScaleFactor(0.6).lineLimit(1).accessibilityIdentifier("monthly-spending")
                Spacer(minLength: 0)
            }.foregroundStyle(.white)
            sparkline.frame(height: 48).accessibilityLabel("Cumulative monthly spending")
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.remainingBudget >= 0 ? "Left in overall budget" : "Over overall budget").font(.system(size: 10)).foregroundStyle(.white.opacity(0.65))
                    Text(store.budgetTotal > 0 ? Money.format(abs(store.remainingBudget)) : "No budget set").font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.lime)
                }
                Spacer()
                Button(action: showPlan) {
                    HStack(spacing: 7) { Text("Your plan"); Image(systemName: "arrow.up.right") }.font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.ink).padding(.horizontal, 14).padding(.vertical, 11).background(Palette.lime, in: Capsule())
                }
            }.padding(.top, 3)
        }.padding(22).background(Palette.forest, in: RoundedRectangle(cornerRadius: 25))
    }

    private var sparkline: some View {
        let points = cumulativePoints
        return Chart(points, id: \.day) { point in
            AreaMark(x: .value("Day", point.day), y: .value("Spending", point.amount)).foregroundStyle(LinearGradient(colors: [Palette.lime.opacity(0.20), Palette.lime.opacity(0)], startPoint: .top, endPoint: .bottom)).interpolationMethod(.monotone)
            LineMark(x: .value("Day", point.day), y: .value("Spending", point.amount)).foregroundStyle(Palette.lime).lineStyle(StrokeStyle(lineWidth: 1.8)).interpolationMethod(.monotone)
        }.chartXAxis(.hidden).chartYAxis(.hidden)
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
                    Chart(store.categoryTotals, id: \.category) { item in
                        SectorMark(angle: .value("Amount", item.amount), innerRadius: .ratio(0.73), angularInset: 2).cornerRadius(3).foregroundStyle(item.category.color)
                    }.frame(width: 126, height: 126).chartBackground { _ in
                        VStack(spacing: 4) { Text("\(store.expenses.count)").font(.system(size: 25, weight: .medium, design: .rounded)); Text("purchases").font(.system(size: 9)).foregroundStyle(Palette.muted) }
                    }.accessibilityLabel("Spending by category")
                    VStack(spacing: 12) {
                        ForEach(Array(store.categoryTotals.prefix(4)), id: \.category) { item in
                            HStack(spacing: 6) {
                                Circle().fill(item.category.color).frame(width: 6, height: 6)
                                Text(item.category.rawValue).font(.system(size: 10)).lineLimit(1)
                                Spacer(minLength: 3)
                                Text("\(Int((Double(item.amount) / Double(max(store.spent, 1)) * 100).rounded()))%").font(.system(size: 10, weight: .semibold)).monospacedDigit()
                            }
                        }
                        if store.categoryTotals.count > 4 { Text("+ \(store.categoryTotals.count - 4) more categories").font(.system(size: 9)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity, alignment: .leading) }
                    }
                }
            }
        }.pocketCard()
    }
}
