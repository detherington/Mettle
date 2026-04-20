import SwiftUI

struct EmptyStateView: View {
    let isSearching: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone.gen3.slash")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)

            Text(isSearching ? "Looking for iPhone…" : "No iPhone connected")
                .font(.title2)
                .fontWeight(.semibold)

            VStack(alignment: .leading, spacing: 6) {
                Label("Connect your iPhone via cable.", systemImage: "1.circle")
                Label("Unlock the iPhone.", systemImage: "2.circle")
                Label("Tap Trust on \"Trust This Computer?\"", systemImage: "3.circle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.top, 4)

            if isSearching {
                ProgressView()
                    .controlSize(.small)
                    .padding(.top, 8)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.9))
    }
}
