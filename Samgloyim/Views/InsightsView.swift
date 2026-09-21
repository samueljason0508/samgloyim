import SwiftUI
import Charts

enum FlowMode: String, CaseIterable { case flow = "Flow", accounts = "Account" }

struct InsightsView: View {
    @EnvironmentObject var store: FinanceStore
    @State private var flowMode = FlowMode.flow
    /// Nil means everything. A trend is only readable against something: one category over six
    /// months, or the whole month-by-month shape.
    @State private var trendCategory: SpendingCategory?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                PageHeader(eyebrow: "LESS GUESSING, MORE UNDERSTANDING", title: "The bigger picture.", symbol: "chart.pie", accessibility: "Spending by category") { }
                MonthSelector()
                AccountFilter()
                VStack(alignment: .leading, spacing: 13) {
                    Label("YOUR MONTHLY NOTE", systemImage: "sparkles").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.3)
                    Text(insightTitle).font(.system(size: 26, design: .serif))
                    Text(insightBody).font(.system(size: 12)).lineSpacing(4).foregroundStyle(Palette.ink.opacity(0.8))
                    Text("Calculated from your recorded transactions").font(.system(size: 9)).foregroundStyle(Palette.muted)
                }.padding(23).background(Palette.sage, in: RoundedRectangle(cornerRadius: 24))
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeading(title: "Follow your money")
                    Text(flowSubtitle).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    HStack(spacing: 5) {
                        ForEach(FlowMode.allCases, id: \.self) { value in
                            Button { flowMode = value } label: {
                                Text(value.rawValue).font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 10)
                                    .background(flowMode == value ? .white : .clear, in: Capsule())
                                    .foregroundStyle(flowMode == value ? Palette.ink : Palette.muted)
                            }.buttonStyle(.plain).accessibilityIdentifier("flow-\(value.rawValue)")
                        }
                    }.padding(4).background(Palette.line, in: Capsule())
                    if store.expenses.isEmpty {
                        EmptyState(symbol: "point.3.connected.trianglepath.dotted", title: "Connect the dots", detail: "Your account-to-category map appears after you add expenses.")
                    } else if flowMode == .flow {
                        MoneyFlowView(transactions: store.expenses, accounts: store.data.accounts).frame(height: 215)
                        HStack { Text("ACCOUNTS"); Spacer(); Text("SPENDING") }.font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(1.3).foregroundStyle(Palette.muted)
                    } else {
                        breakdown(of: accountGroups)
                    }
                }.pocketCard(padding: 18)
                trendCard
                subscriptionCard
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeading(title: "By category", detail: "Tap to explore")
                    ForEach(store.categoryTotals, id: \.category) { item in
                        NavigationLink { CategoryDetailView(category: item.category) } label: {
                            HStack(spacing: 12) {
                                CategoryIcon(category: item.category, size: 36)
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(item.category.rawValue).font(.system(size: 12, weight: .medium))
                                        Spacer()
                                        Text(Money.format(item.amount)).font(.system(size: 12, weight: .semibold))
                                    }
                                    ProgressTrack(value: Double(item.amount) / Double(max(store.spent, 1)), color: item.category.color, height: 4)
                                }
                                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(Palette.muted)
                            }
                        }.buttonStyle(.plain).accessibilityIdentifier("category-\(item.category.rawValue)")
                    }
                    if store.categoryTotals.isEmpty { Text("No spending recorded for this month.").font(.subheadline).foregroundStyle(Palette.muted) }
                }.pocketCard(padding: 18)
            }.padding(.horizontal, 22).padding(.bottom, 30)
        }.pageBackground().toolbar(.hidden, for: .navigationBar)
    }
    /// What renews whether you look or not.
    ///
    /// Read across the whole ledger rather than the selected month: a subscription never appears
    /// twice on one statement, which is exactly why it is easy to keep paying for.
    @ViewBuilder private var subscriptionCard: some View {
        let found = Recurring.detect(store.data.transactions)
        if !found.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(title: "Renews on its own")
                Text("\(Money.format(found.reduce(0) { $0 + $1.yearly }, decimals: false)) a year at today’s prices")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .accessibilityIdentifier("subscriptions-yearly")
                VStack(spacing: 0) {
                    ForEach(Array(found.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 11) {
                            Image(systemName: item.category.symbol).font(.system(size: 12)).frame(width: 26).foregroundStyle(Palette.forest)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.merchant).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text(subscriptionNote(item)).font(.system(size: 10)).foregroundStyle(noteColor(item))
                            }
                            Spacer(minLength: 6)
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(Money.format(item.latest)).font(.system(size: 13, weight: .medium))
                                Text("\(Money.format(item.yearly, decimals: false))/yr").font(.system(size: 9)).foregroundStyle(Palette.muted)
                            }
                        }.padding(.vertical, 10)
                        if index < found.count - 1 { Divider().overlay(Palette.line).padding(.leading, 37) }
                    }
                }
            }.pocketCard(padding: 18)
        }
    }

    /// The most useful thing known about this charge, and only one of them: a row that says three
    /// things says none of them.
    private func subscriptionNote(_ item: Subscription) -> String {
        if item.onSeveralAccounts {
            let names = item.accountIDs.compactMap { store.account($0)?.name }.sorted()
            return "Billed to \(names.joined(separator: " and "))"
        }
        if let increase = item.increase { return "Up \(Money.format(increase)) on the last charge" }
        let account = item.accountIDs.first.flatMap { store.account($0)?.name }
        return "\(item.occurrences) charges · \(account ?? "one account")"
    }

    private func noteColor(_ item: Subscription) -> Color {
        item.onSeveralAccounts || item.increase != nil ? Palette.orange : Palette.muted
    }

    /// Six months of spending, because a habit is invisible inside a single month.
    ///
    /// Filters above change the month and the account; this deliberately ignores the month —
    /// looking across months is the whole point — while still respecting the account filter, so
    /// one card can be read on its own.
    @ViewBuilder private var trendCard: some View {
        let totals = store.monthlyTotals(category: trendCategory, accountID: store.selectedAccountID, months: 6)
        let highest = totals.map(\.amount).max() ?? 0
        if highest > 0 {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(title: "Across the months")
                Text(trendSubtitle(totals)).font(.system(size: 11)).foregroundStyle(Palette.muted)
                Chart {
                    ForEach(totals, id: \.month) { point in
                        BarMark(
                            x: .value("Month", point.month, unit: .month),
                            y: .value("Spent", Double(point.amount) / 100)
                        )
                        .foregroundStyle(Palette.forest.opacity(point.month == totals.last?.month ? 1 : 0.45))
                        .cornerRadius(5)
                    }
                }
                .chartYAxis { AxisMarks(position: .leading) }
                .chartXAxis { AxisMarks(values: .stride(by: .month)) { AxisValueLabel(format: .dateTime.month(.narrow)) } }
                .frame(height: 135)
                .accessibilityIdentifier("trend-chart")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        trendChip(nil, label: "All")
                        ForEach(store.trendingCategories(months: 6), id: \.self) { category in
                            trendChip(category, label: category.rawValue)
                        }
                    }
                }
            }.pocketCard(padding: 18)
        }
    }

    private func trendChip(_ category: SpendingCategory?, label: String) -> some View {
        Button { trendCategory = category } label: {
            Text(label).font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(trendCategory == category ? Palette.forest : Palette.line, in: Capsule())
                .foregroundStyle(trendCategory == category ? .white : Palette.muted)
        }.buttonStyle(.plain).accessibilityIdentifier("trend-\(label)")
    }

    /// The sentence a chart cannot say: whether this month is better or worse than the last one.
    private func trendSubtitle(_ totals: [(month: Date, amount: Int)]) -> String {
        let name = trendCategory?.rawValue ?? "Everything"
        guard totals.count >= 2, let current = totals.last?.amount else { return name }
        let previous = totals[totals.count - 2].amount
        guard previous > 0 else { return "\(name) · nothing to compare last month against" }
        let difference = current - previous
        if difference == 0 { return "\(name) · exactly level with last month" }
        let direction = difference > 0 ? "more" : "less"
        return "\(name) · \(Money.format(abs(difference), decimals: false)) \(direction) than last month"
    }

    private var flowSubtitle: String {
        flowMode == .flow ? "From each account to the things in your life." : "What each account carried this month."
    }

    private struct SpendingGroup: Identifiable {
        var id: String
        var name: String
        var detail: String
        var symbol: String
        var color: Color
        var amount: Int
        var count: Int
        var categories: [(category: SpendingCategory, amount: Int)]
    }

    private func group(_ rows: [Transaction]) -> (amount: Int, count: Int, categories: [(category: SpendingCategory, amount: Int)]) {
        let categories = Dictionary(grouping: rows, by: \.category)
            .map { (category: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }) }
            .sorted { $0.amount > $1.amount }
        return (rows.reduce(0) { $0 + $1.amount }, rows.count, categories)
    }

    /// Only accounts that spent this month, largest first. Respects the account filter above.
    private var accountGroups: [SpendingGroup] {
        store.data.accounts.compactMap { account in
            let rows = store.expenses.filter { $0.accountID == account.id }
            guard !rows.isEmpty else { return nil }
            let totals = group(rows)
            return SpendingGroup(id: account.id.uuidString, name: account.name,
                                 detail: "\(totals.count) transaction\(totals.count == 1 ? "" : "s") · balance \(Money.format(store.balance(account)))",
                                 symbol: account.symbol, color: Palette.colors[account.colorIndex % Palette.colors.count],
                                 amount: totals.amount, count: totals.count, categories: totals.categories)
        }.sorted { $0.amount > $1.amount }
    }

    private func breakdown(of groups: [SpendingGroup]) -> some View {
        VStack(spacing: 18) {
            ForEach(groups) { entry in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 11) {
                        Image(systemName: entry.symbol).font(.system(size: 13, weight: .light))
                            .frame(width: 30, height: 30).background(Palette.sage, in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Text(entry.detail).font(.system(size: 9)).foregroundStyle(Palette.muted).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(Money.format(entry.amount)).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                            Text("\(share(entry.amount))% of spending").font(.system(size: 9)).foregroundStyle(Palette.muted)
                        }
                    }
                    ProgressTrack(value: Double(entry.amount) / Double(max(store.spent, 1)), color: entry.color, height: 4)
                    VStack(spacing: 6) {
                        ForEach(entry.categories.prefix(4), id: \.category) { item in
                            HStack(spacing: 8) {
                                Circle().fill(item.category.color).frame(width: 6, height: 6)
                                Text(item.category.rawValue).font(.system(size: 10)).foregroundStyle(Palette.muted)
                                Spacer(minLength: 4)
                                Text(Money.format(item.amount)).font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(Palette.muted)
                            }
                        }
                        if entry.categories.count > 4 {
                            HStack {
                                Text("\(entry.categories.count - 4) more categor\(entry.categories.count - 4 == 1 ? "y" : "ies")")
                                    .font(.system(size: 9)).foregroundStyle(Palette.muted)
                                Spacer()
                            }
                        }
                    }
                }.accessibilityElement(children: .combine)
                    .accessibilityLabel("\(entry.name), \(Money.format(entry.amount)) across \(entry.count) transactions, \(share(entry.amount)) percent of spending")
            }
        }
    }

    private func share(_ amount: Int) -> Int {
        Int((Double(amount) / Double(max(store.spent, 1)) * 100).rounded())
    }

    private var insightTitle: String {
        guard let biggest = store.categoryTotals.first else { return "Every little detail adds up." }
        return "\(biggest.category.rawValue) leads the way."
    }
    private var insightBody: String {
        guard let biggest = store.categoryTotals.first else { return "Add a few expenses to see where your money goes. Your monthly note will change as your picture gets clearer." }
        let percent = Int((Double(biggest.amount) / Double(max(store.spent, 1)) * 100).rounded())
        return "You’ve recorded \(Money.format(biggest.amount)) in \(biggest.category.rawValue.lowercased()) — \(percent)% of this month’s spending. Explore the breakdown below to see the purchases behind the number."
    }
}

struct MoneyFlowView: View {
    var transactions: [Transaction]
    var accounts: [BankAccount]
    private struct Node { var name: String; var amount: Int; var color: Color; var y: CGFloat = 0; var height: CGFloat = 0 }
    private var activeAccounts: [BankAccount] { accounts.filter { account in transactions.contains { $0.accountID == account.id } } }
    private var topCategories: [SpendingCategory] {
        Array(SpendingCategory.allCases.map { category in (category, transactions.filter { $0.category == category }.reduce(0) { $0 + $1.amount }) }
            .filter { $0.1 > 0 }.sorted { $0.1 > $1.1 }.prefix(4).map(\.0))
    }
    private func layout(_ nodes: [Node], height: CGFloat) -> [Node] {
        let gap: CGFloat = 12
        let minimum: CGFloat = min(24, height / CGFloat(max(nodes.count, 1)) / 2)
        let remainder = max(0, height - gap * CGFloat(max(nodes.count - 1, 0)) - minimum * CGFloat(nodes.count))
        let total = max(1, nodes.reduce(0) { $0 + $1.amount })
        var y: CGFloat = 0
        return nodes.map { node in
            var node = node
            node.height = minimum + remainder * CGFloat(node.amount) / CGFloat(total)
            node.y = y; y += node.height + gap
            return node
        }
    }
    var body: some View {
        GeometryReader { geometry in
            let active = activeAccounts
            let categories = topCategories
            let hasOthers = transactions.contains { !categories.contains($0.category) }
            let left = layout(active.map { account in Node(name: account.name, amount: transactions.filter { $0.accountID == account.id }.reduce(0) { $0 + $1.amount }, color: Palette.forest) }, height: geometry.size.height)
            let right = layout(categories.map { category in Node(name: category.rawValue, amount: transactions.filter { $0.category == category }.reduce(0) { $0 + $1.amount }, color: category.color) } + (hasOthers ? [Node(name: "Everything else", amount: transactions.filter { !categories.contains($0.category) }.reduce(0) { $0 + $1.amount }, color: Palette.muted)] : []), height: geometry.size.height)
            let startX: CGFloat = 64
            let endX = geometry.size.width - 79
            Canvas { context, _ in
                var sourceOffsets = Array(repeating: CGFloat(0), count: left.count)
                var targetOffsets = Array(repeating: CGFloat(0), count: right.count)
                for source in left.indices {
                    for target in right.indices {
                        let amount = transactions.filter { $0.accountID == active[source].id && (target < categories.count ? $0.category == categories[target] : !categories.contains($0.category)) }.reduce(0) { $0 + $1.amount }
                        guard amount > 0 else { continue }
                        let sourceHeight = left[source].height * CGFloat(amount) / CGFloat(max(left[source].amount, 1))
                        let targetHeight = right[target].height * CGFloat(amount) / CGFloat(max(right[target].amount, 1))
                        let sy = left[source].y + sourceOffsets[source]
                        let ty = right[target].y + targetOffsets[target]
                        let mid = (startX + endX) / 2
                        var path = Path()
                        path.move(to: CGPoint(x: startX, y: sy))
                        path.addCurve(to: CGPoint(x: endX, y: ty), control1: CGPoint(x: mid, y: sy), control2: CGPoint(x: mid, y: ty))
                        path.addLine(to: CGPoint(x: endX, y: ty + targetHeight))
                        path.addCurve(to: CGPoint(x: startX, y: sy + sourceHeight), control1: CGPoint(x: mid, y: ty + targetHeight), control2: CGPoint(x: mid, y: sy + sourceHeight))
                        path.closeSubpath()
                        context.fill(path, with: .color(right[target].color.opacity(0.26)))
                        sourceOffsets[source] += sourceHeight; targetOffsets[target] += targetHeight
                    }
                }
            }
            ForEach(left.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2).fill(left[index].color).frame(width: 4, height: left[index].height).position(x: startX, y: left[index].y + left[index].height / 2)
                Text(left[index].name).font(.system(size: 9, weight: .medium)).lineLimit(2).frame(width: 56, alignment: .leading).position(x: 28, y: left[index].y + left[index].height / 2)
            }
            ForEach(right.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2).fill(right[index].color).frame(width: 4, height: right[index].height).position(x: endX, y: right[index].y + right[index].height / 2)
                Text(right[index].name).font(.system(size: 9, weight: .medium)).lineLimit(2).frame(width: 69, alignment: .leading).position(x: endX + 43, y: right[index].y + right[index].height / 2)
            }
        }.accessibilityElement(children: .ignore).accessibilityLabel("Spending flows from \(activeAccounts.count) accounts into categories. Detailed amounts follow below.")
    }
}

struct CategoryDetailView: View {
    @EnvironmentObject var store: FinanceStore
    var category: SpendingCategory
    @State private var selected: Transaction?
    private var transactions: [Transaction] { store.expenses.filter { $0.category == category } }
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                CategoryIcon(category: category, size: 65)
                Text(Money.format(transactions.reduce(0) { $0 + $1.amount })).font(.system(size: 39, design: .rounded))
                Text("\(transactions.count) purchases · \(store.selectedMonth.formatted(.dateTime.month(.wide).year()))").font(.subheadline).foregroundStyle(Palette.muted)
                if breakdown.count > 1 { detailBreakdown }
                VStack { ForEach(transactions) { transaction in Button { selected = transaction } label: { TransactionRow(transaction: transaction) }.buttonStyle(.plain) } }.pocketCard(padding: 15)
            }.padding(22)
        }.pageBackground().navigationTitle(category.rawValue).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar).sheet(item: $selected) { TransactionEditor(transaction: $0) }
    }

    /// The second level: what the bank called each purchase inside this category. Rows it said
    /// nothing about — anything typed in by hand — gather under one honest heading rather than
    /// being guessed at.
    private var breakdown: [(name: String, amount: Int, count: Int)] {
        Dictionary(grouping: transactions) { $0.detailedCategory.map(SpendingDetail.name(for:)) ?? "Not specified" }
            .map { (name: $0.key, amount: $0.value.reduce(0) { $0 + $1.amount }, count: $0.value.count) }
            .sorted { $0.amount > $1.amount }
    }

    private var detailBreakdown: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("WHAT IT WAS").font(.system(size: 9, weight: .bold, design: .monospaced)).tracking(1.2).foregroundStyle(Palette.muted)
            let total = max(transactions.reduce(0) { $0 + $1.amount }, 1)
            ForEach(breakdown, id: \.name) { item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(item.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(item.count)×").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                        Text(Money.format(item.amount)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    }
                    ProgressTrack(value: Double(item.amount) / Double(total), color: category.color, height: 4)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).pocketCard(padding: 16)
    }
}
