import SwiftUI
import Charts

struct InsightsView: View {
    @EnvironmentObject var store: FinanceStore
    @State private var lesson: Lesson?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                PageHeader(eyebrow: "LESS GUESSING, MORE UNDERSTANDING", title: "The bigger picture.", symbol: "book.closed", accessibility: "Learn about budgeting") { lesson = Lesson.library[0] }
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
                    Text("From each account to the things in your life.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    if store.expenses.isEmpty { EmptyState(symbol: "point.3.connected.trianglepath.dotted", title: "Connect the dots", detail: "Your account-to-category map appears after you add expenses.") }
                    else { MoneyFlowView(transactions: store.expenses, accounts: store.data.accounts).frame(height: 215) }
                    HStack { Text("ACCOUNTS"); Spacer(); Text("SPENDING") }.font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(1.3).foregroundStyle(Palette.muted)
                }.pocketCard(padding: 18)
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
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "Money, made simpler", detail: "Small lessons")
                    ForEach(Lesson.library) { item in
                        Button { lesson = item } label: {
                            HStack(spacing: 14) {
                                Image(systemName: item.symbol).font(.system(size: 21, weight: .light)).frame(width: 47, height: 54).background(item.color, in: RoundedRectangle(cornerRadius: 14))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.title).font(.system(size: 14, weight: .semibold))
                                    Text("\(item.tag) · 2 min read").font(.system(size: 10)).foregroundStyle(Palette.muted)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right").font(.system(size: 12))
                            }.pocketCard(padding: 14)
                        }.buttonStyle(.plain)
                    }
                }
            }.padding(.horizontal, 22).padding(.bottom, 30)
        }.pageBackground().toolbar(.hidden, for: .navigationBar).sheet(item: $lesson) { LessonView(lesson: $0) }
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
                VStack { ForEach(transactions) { transaction in Button { selected = transaction } label: { TransactionRow(transaction: transaction) }.buttonStyle(.plain) } }.pocketCard(padding: 15)
            }.padding(22)
        }.pageBackground().navigationTitle(category.rawValue).navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar).sheet(item: $selected) { TransactionEditor(transaction: $0) }
    }
}

struct Lesson: Identifiable {
    var id: String { title }
    var title: String
    var tag: String
    var symbol: String
    var color: Color
    var intro: String
    var sections: [(String, String)]
    static let library = [
        Lesson(title: "A budget that feels like you", tag: "BUDGETING", symbol: "chart.pie", color: Palette.sage,
               intro: "A budget is a plan for your money. It makes the trade-offs visible before you spend.",
               sections: [("Start with what’s real", "List the income you expect and the expenses you know about. A fixed expense stays relatively steady, like rent. A variable expense changes, like groceries."),
                          ("Give categories a limit", "If you plan $200 for food and record $75 in purchases, you have $125 left in that category. Your plan can change as your needs change."),
                          ("Read the whole picture", "Samgloyim adds spending across all your accounts. Unbudgeted categories still count toward total spending, so check those too.")]),
        Lesson(title: "Small steps, visible progress", tag: "SAVING", symbol: "leaf", color: Palette.peach,
               intro: "A savings goal turns a future expense into a number you can track.",
               sections: [("Name the finish line", "A goal has a purpose and a target amount. For a $600 goal with $150 already saved, the remaining amount is $450."),
                          ("Break down the arithmetic", "In that example, saving $50 each month would cover the $450 gap in nine months, assuming no withdrawals, interest, or changes to the target."),
                          ("Keep progress accurate", "Update your saved total after setting money aside. This app tracks progress; it doesn’t transfer or hold your money.")]),
        Lesson(title: "One purchase, one record", tag: "SMART TRACKING", symbol: "doc.on.doc", color: Color(hex: 0xE7E1ED),
               intro: "A receipt and a spreadsheet can describe the same purchase. Counting both would overstate your spending.",
               sections: [("Look for the same details", "Samgloyim flags matching merchant names, amounts, dates, transaction types, and accounts. The match ignores capitalization and punctuation."),
                          ("A match isn’t proof", "Two coffees can cost the same amount on the same day. Review the details and keep both when they are separate purchases."),
                          ("Know what can be missed", "A posting date or merchant name that differs between sources can prevent a match. Review imported transactions, especially OCR totals, before adding them.")])
    ]
}

struct LessonView: View {
    @Environment(\.dismiss) private var dismiss
    var lesson: Lesson
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Image(systemName: lesson.symbol).font(.system(size: 34, weight: .light)).padding(24).background(lesson.color, in: RoundedRectangle(cornerRadius: 24))
                    Text(lesson.tag).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(Palette.muted)
                    Text(lesson.title).font(.system(size: 34, design: .serif))
                    Text(lesson.intro).font(.system(size: 17)).lineSpacing(5)
                    ForEach(lesson.sections.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 10) {
                            Text("0\(index + 1) / \(lesson.sections[index].0)").font(.system(size: 18, weight: .semibold))
                            Text(lesson.sections[index].1).font(.system(size: 15)).foregroundStyle(Palette.muted).lineSpacing(6)
                        }
                    }
                    Text("Simple concepts for understanding your records.").font(.footnote).foregroundStyle(Palette.muted)
                }.padding(25)
            }.pageBackground().navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
