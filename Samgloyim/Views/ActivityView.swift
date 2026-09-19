import SwiftUI

struct ActivityView: View {
    @EnvironmentObject var store: FinanceStore
    var add: () -> Void
    var imports: () -> Void
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    @State private var category: SpendingCategory?
    @State private var selectedTransaction: Transaction?
    @State private var kindFilter = "All"
    private var transactions: [Transaction] {
        store.filteredTransactions.filter {
            (search.isEmpty || $0.merchant.localizedCaseInsensitiveContains(search) || $0.note.localizedCaseInsensitiveContains(search))
                && (category == nil || $0.category == category)
                && (kindFilter == "All" || $0.kind.rawValue == kindFilter)
        }
    }
    private var days: [Date] { Array(Set(transactions.map { Calendar.current.startOfDay(for: $0.date) })).sorted(by: >) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(eyebrow: "THE EVERYDAY DETAILS", title: "Your activity.", action: add)
                MonthSelector()
                AccountFilter()
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                    TextField("Search merchants or notes", text: $search).font(.system(size: 14)).accessibilityIdentifier("transaction-search").focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false }
                    if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted) }.accessibilityLabel("Clear search") }
                }.padding(15).background(.white, in: RoundedRectangle(cornerRadius: 15)).overlay(RoundedRectangle(cornerRadius: 15).stroke(Palette.line))
                HStack {
                    Menu {
                        Button("All categories") { category = nil }
                        ForEach(SpendingCategory.allCases) { item in Button(item.rawValue) { category = item } }
                    } label: { Label(category?.rawValue ?? "All categories", systemImage: "line.3.horizontal.decrease").font(.system(size: 12, weight: .medium)) }
                    Spacer()
                    Menu {
                        ForEach(["All", "Expense", "Income"], id: \.self) { kind in Button(kind) { kindFilter = kind } }
                    } label: { HStack(spacing: 5) { Text(kindFilter == "All" ? "All types" : kindFilter); Image(systemName: "chevron.down") }.font(.system(size: 12, weight: .medium)) }
                }
                HStack {
                    metric(title: "MONEY IN", amount: store.income, symbol: "arrow.down.left", color: Palette.forest)
                    Rectangle().fill(Palette.line).frame(width: 1, height: 38)
                    metric(title: "MONEY OUT", amount: store.spent, symbol: "arrow.up.right", color: Palette.orange)
                }.pocketCard(padding: 18)
                if transactions.isEmpty {
                    EmptyState(symbol: "tray", title: "Nothing here just yet", detail: search.isEmpty && category == nil ? "Add your first expense or choose another month." : "Try another search or clear your filters.")
                    PrimaryButton(title: "Import transactions", symbol: "tray.and.arrow.down", action: imports)
                } else {
                    HStack {
                        Text("\(transactions.count) TRANSACTIONS").font(.system(size: 10, weight: .medium, design: .monospaced)).tracking(1.3).foregroundStyle(Palette.muted)
                        Spacer()
                        Button("Import", action: imports).font(.system(size: 12, weight: .semibold))
                    }
                    ForEach(days, id: \.self) { day in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.muted)
                            VStack(spacing: 3) {
                                ForEach(transactions.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }) { transaction in
                                    Button { selectedTransaction = transaction } label: { TransactionRow(transaction: transaction) }.buttonStyle(.plain).accessibilityIdentifier("transaction-\(transaction.merchant)")
                                }
                            }.pocketCard(padding: 14)
                        }
                    }
                }
            }.padding(.horizontal, 22).padding(.bottom, 30)
        }.scrollDismissesKeyboard(.interactively).pageBackground().toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selectedTransaction) { TransactionEditor(transaction: $0) }
    }
    private func metric(title: String, amount: Int, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(0.7).foregroundStyle(color)
            Text(Money.format(amount)).font(.system(size: 21, weight: .medium, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
