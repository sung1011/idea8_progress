import SwiftUI

/// 主面板和设置共用的两个页签。
enum PanelTab: String, CaseIterable, Identifiable {
    case work
    case retirement

    var id: String { rawValue }

    var title: String {
        switch self {
        case .work:
            return "工作"
        case .retirement:
            return "退休"
        }
    }
}

struct PanelTabBar: View {
    @Binding var selection: PanelTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PanelTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func tabButton(_ tab: PanelTab) -> some View {
        let selected = selection == tab
        return Button {
            selection = tab
        } label: {
            VStack(spacing: 7) {
                Text(tab.title)
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                Rectangle()
                    .fill(selected ? Color.blue : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
