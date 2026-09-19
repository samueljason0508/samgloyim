import SwiftUI

enum Palette {
    static let background = Color(hex: 0xF6F5EF)
    static let paper = Color(hex: 0xFFFFFF)
    static let ink = Color(hex: 0x203B32)
    static let forest = Color(hex: 0x285445)
    static let muted = Color(hex: 0x78817A)
    static let sage = Color(hex: 0xDFE8DC)
    static let lime = Color(hex: 0xD8EDAC)
    static let orange = Color(hex: 0xC16D43)
    static let peach = Color(hex: 0xF8E5D7)
    static let line = Color(hex: 0xE6E7DF)
    static let colors: [Color] = [forest, orange, Color(hex: 0x7A8D65), Color(hex: 0xB8A3C2), Color(hex: 0x8AA4B1), Color(hex: 0xD4BC82), Color(hex: 0x9DAE91), Color(hex: 0xCB8C85), Color(hex: 0xAAA89F)]
}

extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
}

extension SpendingCategory {
    var color: Color { Palette.colors[Self.allCases.firstIndex(of: self) ?? 0] }
}

extension View {
    func pocketCard(padding: CGFloat = 20) -> some View {
        self.padding(padding).background(Palette.paper, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.line.opacity(0.75), lineWidth: 1))
    }
    func pageBackground() -> some View { self.background(Palette.background.ignoresSafeArea()).foregroundStyle(Palette.ink) }
}

struct PageHeader: View {
    var eyebrow: String
    var title: String
    var symbol: String = "plus"
    var accessibility: String = "Add transaction"
    var action: () -> Void
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text(eyebrow.uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced)).tracking(2).foregroundStyle(Palette.muted)
                Text(title).font(.system(size: 32, weight: .regular, design: .serif)).tracking(-0.7)
            }
            Spacer()
            Button(action: action) { Image(systemName: symbol).font(.system(size: 18, weight: .medium)).frame(width: 46, height: 46).background(.white, in: Circle()).overlay(Circle().stroke(Palette.line)) }
                .accessibilityLabel(accessibility)
        }.padding(.top, 12)
    }
}

struct SectionHeading: View {
    var title: String
    var detail: String? = nil
    var action: (() -> Void)? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 20, weight: .semibold)).tracking(-0.5)
            Spacer()
            if let detail {
                if let action { Button(action: action) { Text(detail).font(.system(size: 12, weight: .semibold)) } }
                else { Text(detail).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted) }
            }
        }
    }
}

struct MonthSelector: View {
    @EnvironmentObject var store: FinanceStore
    var body: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "calendar").foregroundStyle(Palette.muted)
                Text(store.selectedMonth.formatted(.dateTime.month(.wide).year())).fontWeight(.medium)
            }.font(.system(size: 13))
            Spacer()
            Button { store.moveMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 36, height: 36) }.accessibilityLabel("Previous month")
            Button { store.moveMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 36, height: 36) }.accessibilityLabel("Next month")
        }.font(.system(size: 12, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 3)
            .background(.white.opacity(0.75), in: Capsule())
    }
}

struct AccountFilter: View {
    @EnvironmentObject var store: FinanceStore
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All accounts", symbol: "square.grid.2x2", selected: store.selectedAccountID == nil) { store.selectedAccountID = nil }
                ForEach(store.data.accounts) { account in
                    chip(account.name, symbol: account.symbol, selected: store.selectedAccountID == account.id) { store.selectedAccountID = account.id }
                }
            }.padding(.vertical, 1)
        }
    }
    private func chip(_ title: String, symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 11)
                .background(selected ? Palette.forest : .white, in: Capsule())
                .foregroundStyle(selected ? .white : Palette.ink)
                .overlay(Capsule().stroke(selected ? .clear : Palette.line))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct CategoryIcon: View {
    var category: SpendingCategory
    var size: CGFloat = 44
    var body: some View {
        Image(systemName: category.symbol).font(.system(size: size * 0.36, weight: .medium))
            .foregroundStyle(category.color).frame(width: size, height: size)
            .background(category.color.opacity(0.11), in: RoundedRectangle(cornerRadius: size * 0.31))
    }
}

struct TransactionRow: View {
    @EnvironmentObject var store: FinanceStore
    let transaction: Transaction
    var body: some View {
        HStack(spacing: 12) {
            if transaction.kind == .income {
                Image(systemName: "arrow.down.left").font(.system(size: 17, weight: .medium)).frame(width: 44, height: 44).background(Palette.sage, in: RoundedRectangle(cornerRadius: 14))
            } else { CategoryIcon(category: transaction.category) }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Text(transaction.merchant).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    if transaction.receipt != nil {
                        Image(systemName: "paperclip").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.forest)
                            .accessibilityLabel("Receipt attached")
                    }
                }
                Text("\(transaction.kind == .income ? "Income" : transaction.category.rawValue) · \(store.account(transaction.accountID)?.name ?? "Account")")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                Text("\(transaction.kind == .income ? "+" : "−")\(Money.format(transaction.amount))").font(.system(size: 14, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(transaction.kind == .income ? Palette.forest : Palette.ink)
                Text(transaction.date.formatted(.dateTime.month(.abbreviated).day())).font(.system(size: 10)).foregroundStyle(Palette.muted)
            }
        }.padding(.vertical, 7).contentShape(Rectangle())
    }
}

struct PrimaryButton: View {
    var title: String
    var symbol: String? = nil
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) { Text(title); if let symbol { Image(systemName: symbol) } }
                .font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 17)
                .foregroundStyle(.white).background(Palette.forest, in: RoundedRectangle(cornerRadius: 17))
        }.buttonStyle(.plain)
    }
}

struct EmptyState: View {
    var symbol: String
    var title: String
    var detail: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(Palette.forest).padding(20).background(Palette.sage, in: Circle())
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(Palette.muted).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 30)
    }
}

struct ProgressTrack: View {
    var value: Double
    var color: Color = Palette.forest
    var height: CGFloat = 6
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.12))
                Capsule().fill(color).frame(width: geometry.size.width * min(max(value, 0), 1))
            }
        }.frame(height: height).accessibilityValue("\(Int(min(max(value, 0), 1) * 100)) percent")
    }
}
