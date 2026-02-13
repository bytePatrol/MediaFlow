import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Logo
            HStack(spacing: 10) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.mfPrimary)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Text("Media")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                        Text("Flow")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.mfPrimary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            Divider()
                .background(Color.mfGlassBorder)

            // Nav Items
            VStack(spacing: 4) {
                ForEach(NavigationItem.allCases) { item in
                    SidebarNavButton(item: item, isSelected: appState.selectedNavItem == item) {
                        appState.selectedNavItem = item
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)

            Spacer()

            // Connection Status
            Divider()
                .background(Color.mfGlassBorder)

            HStack(spacing: 8) {
                Circle()
                    .fill(appState.isBackendOnline ? Color.mfSuccess : Color.mfError)
                    .frame(width: 8, height: 8)
                Text(appState.isBackendOnline ? "Backend Connected" : "Backend Offline")
                    .font(.mfCaption)
                    .foregroundColor(.mfTextSecondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color.mfSurface)
    }
}

struct SidebarNavButton: View {
    let item: NavigationItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: item.isSubItem ? 8 : 10) {
                Image(systemName: item.icon)
                    .font(.system(size: item.isSubItem ? 12 : 14, weight: .medium))
                    .frame(width: item.isSubItem ? 16 : 20)
                Text(item.label)
                    .font(.system(size: item.isSubItem ? 12 : 13, weight: isSelected ? .semibold : .medium))
                Spacer()
                if item == .processing {
                    // Active jobs badge could go here
                }
            }
            .foregroundColor(isSelected ? .mfPrimary : .mfTextSecondary)
            .padding(.leading, item.isSubItem ? 24 : 12)
            .padding(.trailing, 12)
            .padding(.vertical, item.isSubItem ? 6 : 8)
            .background(isSelected ? Color.mfPrimary.opacity(0.1) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
