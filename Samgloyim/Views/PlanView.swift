import SwiftUI

struct PlanView: View {
    @EnvironmentObject var store: FinanceStore
    @State private var mode = "Budgets"
    @State private var editor: PlanEditor?
    private enum PlanEditor: Identifiable {
        case budget(SpendingCategory?), goal(SavingsGoal?)
        var id: String {
            switch self {
            case .budget(let category): "budget-" + (category?.rawValue ?? "new")
            case .goal(let goal): "goal-" + (goal?.id.uuidString ?? "new")
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                PageHeader(eyebrow: "A PLAN WITH ROOM TO LIVE", title: "Little by little.", accessibility: mode == "Budgets" ? "Add budget" : "Add savings goal") {
                    editor = mode == "Budgets" ? .budget(nil) : .goal(nil)
                }
                HStack(spacing: 5) {
                    ForEach(["Budgets", "Savings goals"], id: \.self) { value in
                        Button { mode = value } label: {
                            Text(value).font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 13)
                                .background(mode == value ? .white : .clear, in: Capsule()).foregroundStyle(mode == value ? Palette.ink : Palette.muted)
                        }.buttonStyle(.plain).accessibilityIdentifier("plan-\(value)")
                    }
                }.padding(5).background(Palette.line, in: Capsule())
                if mode == "Budgets" { budgets } else { goals }
            }.padding(.horizontal, 22).padding(.bottom, 30)
        }.pageBackground().toolbar(.hidden, for: .navigationBar)
            .sheet(item: $editor) { item in
                switch item {
                case .budget(let category): BudgetEditor(initialCategory: category)
                case .goal(let goal): GoalEditor(goal: goal)
                }
            }
    }

    private var budgets: some View {
        VStack(alignment: .leading, spacing: 22) {
            MonthSelector()
            VStack(alignment: .leading, spacing: 15) {
                HStack { Text("YOUR MONTH, YOUR PACE").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.4); Spacer(); Image(systemName: "sun.max") }
                Text(Money.format(abs(store.remainingBudget))).font(.system(size: 39, weight: .regular, design: .rounded)).tracking(-1.5)
                Text(store.budgetTotal == 0 ? "Set your first budget below." : store.remainingBudget >= 0 ? "left to spend across your monthly plan" : "over your monthly plan").font(.system(size: 12)).foregroundStyle(Palette.ink.opacity(0.75))
                ProgressTrack(value: Double(store.totalMonthlySpending) / Double(max(store.budgetTotal, 1)), color: store.remainingBudget < 0 ? Palette.orange : Palette.forest, height: 8)
                HStack { Text("\(Money.format(store.totalMonthlySpending, decimals: false)) spent"); Spacer(); Text("\(Money.format(store.budgetTotal, decimals: false)) planned") }.font(.system(size: 11, weight: .medium))
            }.padding(23).background(Palette.sage, in: RoundedRectangle(cornerRadius: 24))
            SectionHeading(title: "Give every dollar a place", detail: "All accounts")
            if store.data.budgets.isEmpty { EmptyState(symbol: "chart.pie", title: "Your plan starts here", detail: "Set a monthly limit for a category. You can adjust it anytime.") }
            ForEach(store.data.budgets) { budget in
                Button { editor = .budget(budget.category) } label: {
                    VStack(spacing: 15) {
                        HStack(spacing: 12) {
                            CategoryIcon(category: budget.category, size: 39)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(budget.category.rawValue).font(.system(size: 14, weight: .semibold))
                                Text(budgetStatus(budget)).font(.system(size: 11)).foregroundStyle(store.spent(in: budget.category) > budget.limit ? Palette.orange : Palette.muted)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(Money.format(store.spent(in: budget.category), decimals: false)).font(.system(size: 15, weight: .semibold))
                                Text("of \(Money.format(budget.limit, decimals: false))").font(.system(size: 10)).foregroundStyle(Palette.muted)
                            }
                        }
                        ProgressTrack(value: Double(store.spent(in: budget.category)) / Double(max(budget.limit, 1)), color: store.spent(in: budget.category) > budget.limit ? Palette.orange : budget.category.color)
                    }.pocketCard(padding: 18)
                }.buttonStyle(.plain).accessibilityIdentifier("budget-\(budget.category.rawValue)")
            }
            PrimaryButton(title: "Set a category budget", symbol: "plus") { editor = .budget(nil) }
            Text("Budgets repeat each month across all accounts. Editing a limit updates your plan for every month. Spending in unbudgeted categories still counts toward the overall total.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
        }
    }
    private func budgetStatus(_ budget: Budget) -> String {
        let left = budget.limit - store.spent(in: budget.category)
        return "\(Money.format(abs(left), decimals: false)) \(left >= 0 ? "left this month" : "over budget")"
    }

    private var goals: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 15) {
                Image(systemName: "sparkles").font(.system(size: 26, weight: .light)).padding(16).background(.white.opacity(0.6), in: Circle())
                VStack(alignment: .leading, spacing: 7) {
                    Text("Good things take a little saving.").font(.system(size: 24, design: .serif))
                    Text("Make space for the things you’re looking forward to.").font(.system(size: 12)).foregroundStyle(Palette.muted).lineSpacing(3)
                }
            }.padding(22).background(Palette.peach, in: RoundedRectangle(cornerRadius: 24))
            if store.data.goals.isEmpty { EmptyState(symbol: "flag", title: "Something to look forward to", detail: "Create a goal and track your progress, one contribution at a time.") }
            ForEach(store.data.goals) { goal in
                Button { editor = .goal(goal) } label: {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Image(systemName: goal.symbol).font(.system(size: 24, weight: .light)).frame(width: 52, height: 52).background(Palette.sage, in: RoundedRectangle(cornerRadius: 17))
                            Spacer()
                            Text(goal.saved >= goal.target ? "YOU DID IT" : "\(Int(Double(goal.saved) / Double(max(goal.target, 1)) * 100))% THERE")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1).padding(.horizontal, 11).padding(.vertical, 7).background(Palette.background, in: Capsule())
                        }
                        Text(goal.name).font(.system(size: 23, design: .serif))
                        HStack(alignment: .firstTextBaseline) {
                            Text(Money.format(goal.saved, decimals: false)).font(.system(size: 26, weight: .medium, design: .rounded))
                            Text("of \(Money.format(goal.target, decimals: false))").font(.system(size: 12)).foregroundStyle(Palette.muted)
                            Spacer()
                        }
                        ProgressTrack(value: Double(goal.saved) / Double(max(goal.target, 1)), color: Palette.forest, height: 7)
                        HStack { Text("Update progress"); Spacer(); Image(systemName: "arrow.up.right") }.font(.system(size: 12, weight: .semibold))
                    }.pocketCard()
                }.buttonStyle(.plain).accessibilityIdentifier("goal-\(goal.name)")
            }
            PrimaryButton(title: "Dream up a new goal", symbol: "plus") { editor = .goal(nil) }
            Text("Goals track amounts you’ve set aside. Updating a goal doesn’t transfer money or change account balances.").font(.system(size: 11)).foregroundStyle(Palette.muted).lineSpacing(4)
        }
    }
}

struct BudgetEditor: View {
    @EnvironmentObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    var initialCategory: SpendingCategory?
    @State private var category: SpendingCategory = .food
    @State private var amount = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Monthly category budget") {
                    Picker("Category", selection: $category) { ForEach(SpendingCategory.allCases) { Text($0.rawValue).tag($0) } }
                    HStack { Text("$"); TextField("Monthly limit", text: $amount).keyboardType(.decimalPad).accessibilityIdentifier("budget-amount") }
                }
                Section { Text("This limit applies each month across all accounts. Saving replaces any existing budget for this category.").font(.subheadline).foregroundStyle(Palette.muted) }
                if store.data.budgets.contains(where: { $0.category == category }) {
                    Section { Button("Remove budget", role: .destructive) { if store.saveBudget(category: category, limit: 0) { dismiss() } } }
                }
            }.scrollContentBackground(.hidden).pageBackground().navigationTitle("Your monthly plan").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { if let cents = Money.parse(amount), store.saveBudget(category: category, limit: cents) { dismiss() } }.disabled((Money.parse(amount) ?? 0) <= 0).accessibilityIdentifier("save-budget") }
                }
                .onAppear { category = initialCategory ?? SpendingCategory.allCases.first(where: { c in !store.data.budgets.contains { $0.category == c } }) ?? .food; loadAmount() }
                .onChange(of: category) { _, _ in loadAmount() }
        }
    }
    private func loadAmount() { amount = store.data.budgets.first { $0.category == category }.map { Money.input($0.limit) } ?? "" }
}

struct GoalEditor: View {
    @EnvironmentObject var store: FinanceStore
    @Environment(\.dismiss) private var dismiss
    var goal: SavingsGoal?
    @State private var name = ""
    @State private var target = ""
    @State private var saved = "0.00"
    @State private var symbol = "sun.max.fill"
    @State private var showDelete = false
    private let symbols = ["sun.max.fill", "airplane", "umbrella.fill", "laptopcomputer", "house.fill", "graduationcap.fill", "heart.fill"]
    private var valid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (Money.parse(target) ?? 0) > 0 && (Money.parse(saved) ?? -1) >= 0 }
    var body: some View {
        NavigationStack {
            Form {
                Section("Something worth saving for") {
                    TextField("Goal name", text: $name).accessibilityIdentifier("goal-name")
                    HStack { Text("Target ($)"); TextField("2000.00", text: $target).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityIdentifier("goal-target") }
                    HStack { Text("Saved so far ($)"); TextField("0.00", text: $saved).keyboardType(.decimalPad).multilineTextAlignment(.trailing).accessibilityIdentifier("goal-saved") }
                }
                Section("Make it yours") {
                    HStack { ForEach(symbols, id: \.self) { item in
                        Button { symbol = item } label: { Image(systemName: item).frame(maxWidth: .infinity).frame(height: 40).background(symbol == item ? Palette.sage : .clear, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain).accessibilityLabel(item).accessibilityAddTraits(symbol == item ? .isSelected : [])
                    } }
                }
                Section { Text("Enter the total you’ve already saved. This is a progress tracker; it doesn’t move money between accounts.").font(.subheadline).foregroundStyle(Palette.muted) }
                if goal != nil { Section { Button("Delete goal", role: .destructive) { showDelete = true } } }
            }.scrollContentBackground(.hidden).pageBackground().navigationTitle(goal == nil ? "A new goal" : "Update your goal").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        guard let target = Money.parse(target), let saved = Money.parse(saved) else { return }
                        if store.saveGoal(SavingsGoal(id: goal?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), target: target, saved: saved, symbol: symbol)) { dismiss() }
                    }.disabled(!valid).accessibilityIdentifier("save-goal") }
                }
                .onAppear { if let goal { name = goal.name; target = Money.input(goal.target); saved = Money.input(goal.saved); symbol = goal.symbol } }
                .confirmationDialog("Delete this savings goal?", isPresented: $showDelete, titleVisibility: .visible) {
                    Button("Delete goal", role: .destructive) { if let goal, store.deleteGoal(goal.id) { dismiss() } }
                }
        }
    }
}
