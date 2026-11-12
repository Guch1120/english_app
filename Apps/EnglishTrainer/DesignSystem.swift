import SwiftUI
import DeviceDiagnostics

/// Shared visual building blocks. Keep these free of learning or inference logic.

/// Wraps children onto as many lines as needed, so word chips and tags stay readable at large text sizes.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width ?? .greatestFiniteMagnitude, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangement(width: bounds.width, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func arrangement(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if size.width > width {
                size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            }
            if x > 0 && x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            usedWidth = max(usedWidth, x - spacing)
        }
        return (CGSize(width: usedWidth, height: y + lineHeight), frames)
    }
}

/// Small capsule tag used for category, difficulty and status metadata.
struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color = .teal

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.15), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// One number with a caption, used for learning statistics.
struct StatTile: View {
    let value: String
    let label: String
    let systemImage: String
    var tint: Color = .teal
    /// Full wording for VoiceOver when the visible caption is abbreviated to fit a narrow tile.
    var spokenLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: systemImage).font(.subheadline).foregroundStyle(tint)
            Text(value).font(.title3.bold()).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption).foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(10)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(spokenLabel ?? label) \(value)")
    }
}

/// Large tappable card for a primary entry point on the home screen.
struct ActionTile: View {
    let title: String
    let subtitle: String
    let systemImage: String
    var tint: Color = .teal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage).font(.title2).foregroundStyle(tint)
                .frame(height: 30, alignment: .center)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Icon-over-caption control for secondary playback actions that share one row.
struct TransportButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.body.weight(.semibold))
                Text(title).font(.caption).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(title)
    }
}

/// Filled, full-width style for the single most important action of a screen.
struct PrimaryActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        // An explicit stack: a prominent button inside a Form drops a Label's icon.
        HStack(spacing: 10) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.title3.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: 52)
    }
}

extension ProcessInfo.ThermalState {
    /// User-facing wording; raw enum names are not meaningful to learners.
    var localizedTitle: String {
        switch self {
        case .nominal: "通常"
        case .fair: "やや高い"
        case .serious: "高い"
        case .critical: "非常に高い"
        @unknown default: "不明"
        }
    }
}

extension DiagnosticThermalState {
    /// Same wording as the live thermal state, for stored diagnostic records.
    var localizedTitle: String {
        switch self {
        case .nominal: "通常"
        case .fair: "やや高い"
        case .serious: "高い"
        case .critical: "非常に高い"
        case .unavailable: "不明"
        }
    }
}
