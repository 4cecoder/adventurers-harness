// Components.swift
// Adventurers Harness — Reusable TUI Components
//
// A library of production-grade SwiftUI components built on top of the
// ADTheme tokens. Every component is self-contained, previewable, and
// designed for macOS 15+ with Swift 6 concurrency safety.
//
// macOS 15+ · Swift 6 · Sendable-safe

import SwiftUI

// MARK: - AdventurersButton

/// A versatile button with four visual styles.
struct AdventurersButton: View {
    enum Style {
        case primary
        case secondary
        case ghost
        case destructive
    }

    let title: String
    let style: Style
    var icon: String? = nil
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ADSpacing.xs) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 14, height: 14)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                }

                Text(title)
                    .font(.adLabel)
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, ADSpacing.md)
            .padding(.vertical, ADSpacing.sm)
            .background(backgroundColor, in: RoundedRectangle(cornerRadius: ADCorner.sm))
            .overlay(
                RoundedRectangle(cornerRadius: ADCorner.sm)
                    .strokeBorder(borderColor, lineWidth: style == .ghost ? 0 : 1)
            )
            .adGlow(glowColor, radius: 8, isActive: style == .primary && isEnabled)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1.0 : 0.5)
    }

    // MARK: - Style-dependent colors

    private var foregroundColor: Color {
        switch style {
        case .primary:      return .white
        case .secondary:    return .adTextPrimary
        case .ghost:        return .adTextSecondary
        case .destructive:  return .white
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:      return .adOrange
        case .secondary:    return Color.adOverlay
        case .ghost:        return Color.clear
        case .destructive:  return .adError
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary:      return .adOrange
        case .secondary:    return Color.white.opacity(0.08)
        case .ghost:        return .clear
        case .destructive:  return .adError
        }
    }

    private var glowColor: Color {
        switch style {
        case .primary:      return .adOrange
        case .secondary:    return .clear
        case .ghost:        return .clear
        case .destructive:  return .adError
        }
    }
}

// MARK: - BadgeView

/// A small colored label for status, category, or count indicators.
struct BadgeView: View {
    let text: String
    var color: Color = .adOrange
    var size: Size = .normal

    enum Size {
        case small, normal

        var font: Font {
            switch self {
            case .small:  return .system(size: 9, weight: .semibold, design: .rounded)
            case .normal: return .adLabel
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .small:  return 5
            case .normal: return ADSpacing.sm
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .small:  return 2
            case .normal: return 3
            }
        }
    }

    var body: some View {
        Text(text.uppercased())
            .font(size.font)
            .foregroundStyle(color)
            .padding(.horizontal, size.horizontalPadding)
            .padding(.vertical, size.verticalPadding)
            .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: ADCorner.sm))
    }
}

// MARK: - StatusDot

struct StatusDot: View {
    let color: Color
    var size: CGFloat = 8
    var isPulsing: Bool = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.3), radius: 2, x: 0, y: 0)
    }
}

// MARK: - AvatarView

/// Displays an agent's avatar — either an image or generated initials.
struct AvatarView: View {
    let name: String
    var imageURL: URL? = nil
    var size: CGFloat = 32
    var borderColor: Color? = nil

    var body: some View {
        Group {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        initialsView
                    case .empty:
                        ProgressView()
                            .scaleEffect(0.5)
                    @unknown default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(
            Circle()
                .strokeBorder(borderColor ?? Color.clear, lineWidth: 2)
        )
    }

    private var initialsView: some View {
        Text(initials)
            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .background(
                Circle()
                    .fill(Color(hex: UInt32(abs(name.hashValue % 0xFFFFFF))))
            )
    }

    private var initials: String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1))
        }
        return String(name.prefix(2))
    }
}

// MARK: - CardView

/// An elevated, interactive card with hover highlight.
struct CardView<Content: View>: View {
    var isHighlighted: Bool = false
    var accentColor: Color = .adOrange
    @ViewBuilder let content: () -> Content

    @State private var isHovering = false

    var body: some View {
        content()
            .padding(ADSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: ADCorner.md)
                    .fill(Color.adCard)
                    .overlay(
                        RoundedRectangle(cornerRadius: ADCorner.md)
                            .strokeBorder(
                                isHighlighted
                                    ? accentColor.opacity(0.5)
                                    : Color.white.opacity(0.04),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(
                color: isHovering
                    ? Color.black.opacity(0.35)
                    : Color.black.opacity(0.15),
                radius: isHovering ? 12 : 6,
                y: isHovering ? 4 : 2
            )
            .scaleEffect(isHovering ? 1.01 : 1.0)
            .animation(.easeInOut(duration: 0.18), value: isHovering)
            .onHover { isHovering = $0 }
    }
}

// MARK: - SearchField

/// A styled search field with magnifying glass icon and clear button.
struct SearchField: View {
    @Binding var text: String
    var placeholder: String = "Search…"
    var onSubmit: (() -> Void)? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: ADSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.adTextTertiary)
                .font(.system(size: 13))

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.adBody)
                .foregroundStyle(Color.adTextPrimary)
                .focused($isFocused)
                .onSubmit { onSubmit?() }

            if !text.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { text = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.adTextTertiary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, ADSpacing.md)
        .padding(.vertical, ADSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: ADCorner.sm)
                .fill(Color.adOverlay)
                .overlay(
                    RoundedRectangle(cornerRadius: ADCorner.sm)
                        .strokeBorder(
                            isFocused ? Color.adOrange.opacity(0.5) : Color.white.opacity(0.06),
                            lineWidth: 1
                        )
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .animation(.easeInOut(duration: 0.15), value: text.isEmpty)
    }
}

// MARK: - TogglePill

/// A segmented toggle styled as a pill — alternative to native Picker.
struct TogglePill: View {
    let options: [String]
    @Binding var selectedIndex: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, label in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedIndex = index
                    }
                } label: {
                    Text(label)
                        .font(.adLabel)
                        .foregroundStyle(
                            selectedIndex == index
                                ? .white
                                : .adTextSecondary
                        )
                        .padding(.horizontal, ADSpacing.md)
                        .padding(.vertical, ADSpacing.xs + 2)
                        .background(
                            selectedIndex == index
                                ? Color.adOrange
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: ADCorner.pill)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.adOverlay, in: RoundedRectangle(cornerRadius: ADCorner.pill))
    }
}

// MARK: - ProgressRing

/// A circular progress indicator with optional center label.
struct ProgressRing: View {
    var progress: Double // 0 … 1
    var lineWidth: CGFloat = 4
    var size: CGFloat = 44
    var color: Color = .adOrange
    var trackColor: Color = .adOverlay
    var showLabel: Bool = false

    var body: some View {
        ZStack {
            // Track
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)

            // Progress arc
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [color.opacity(0.6), color]),
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.4), value: progress)

            // Center label
            if showLabel {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: size * 0.24, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.adTextPrimary)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - AlertBanner

/// A slide-in banner for success, warning, error, or info alerts.
struct AlertBanner: View {
    enum Kind {
        case success, warning, error, info

        var color: Color {
            switch self {
            case .success: return .adSuccess
            case .warning: return .adWarning
            case .error:   return .adError
            case .info:    return .adInfo
            }
        }

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error:   return "xmark.octagon.fill"
            case .info:    return "info.circle.fill"
            }
        }
    }

    let kind: Kind
    let message: String
    var onDismiss: (() -> Void)? = nil

    @State private var isShowing = false

    var body: some View {
        HStack(spacing: ADSpacing.md) {
            Image(systemName: kind.icon)
                .foregroundStyle(kind.color)
                .font(.system(size: 16))

            Text(message)
                .font(.adBody)
                .foregroundStyle(Color.adTextPrimary)
                .lineLimit(2)

            Spacer()

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.adTextTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(ADSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: ADCorner.md)
                .fill(Color.adCard)
                .overlay(
                    RoundedRectangle(cornerRadius: ADCorner.md)
                        .strokeBorder(kind.color.opacity(0.3), lineWidth: 1)
                )
        )
        .shadow(color: kind.color.opacity(0.2), radius: 12, y: 4)
        .offset(x: isShowing ? 0 : 400)
        .opacity(isShowing ? 1 : 0)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: isShowing)
        .onAppear {
            Task { @MainActor in
                isShowing = true
            }
        }
    }
}

// MARK: - SkeletonView

/// A reusable skeleton placeholder — gray shimmering bar.
struct SkeletonView: View {
    var height: CGFloat = 12
    var width: CGFloat? = nil
    var cornerRadius: CGFloat = ADCorner.sm

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.adOverlay)
            .frame(height: height)
            .frame(maxWidth: width)
            .adSkeleton(cornerRadius: cornerRadius)
    }
}


// MARK: - GateStatusBadge

/// Displays a gate's pass/fail status with its color.
struct GateStatusBadge: View {
    let gate: GateType
    var passed: Bool? = nil // nil = pending

    var body: some View {
        HStack(spacing: ADSpacing.xs) {
            if let passed {
                Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(passed ? Color.adSuccess : Color.adError)
                    .font(.system(size: 11))
            } else {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 11, height: 11)
            }

            Text(gate.displayName)
                .font(.adLabel)
                .foregroundStyle(gate.color)
        }
        .padding(.horizontal, ADSpacing.sm)
        .padding(.vertical, ADSpacing.xs)
        .background(gate.color.opacity(0.12), in: RoundedRectangle(cornerRadius: ADCorner.sm))
    }
}

// MARK: - PermissionRow

/// A single row in the permission list, showing gate, risk, and toggle.
struct PermissionRow: View {
    let title: String
    let gate: GateType
    let risk: PermissionRiskLevel
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: ADSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.adBody)
                    .foregroundStyle(Color.adTextPrimary)

                HStack(spacing: ADSpacing.sm) {
                    GateStatusBadge(gate: gate)
                    BadgeView(text: risk.label, color: risk.displayColor, size: .small)
                }
            }

            Spacer()

            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(.adOrange)
        }
        .padding(.vertical, ADSpacing.xs)
        .adRiskBorder(risk)
    }
}

// MARK: - AgentStatusCard

/// A card displaying agent status — avatar, name, role, and activity.
struct AgentStatusCard: View {
    let name: String
    var role: String = "Agent"
    var status: AgentStatus = .idle
    var taskDescription: String? = nil
    var imageURL: URL? = nil

    enum AgentStatus: Sendable {
        case idle
        case working
        case error

        var dotColor: Color {
            switch self {
            case .idle:    return .adTextTertiary
            case .working: return .adSuccess
            case .error:   return .adError
            }
        }

        var label: String {
            switch self {
            case .idle:    return "Idle"
            case .working: return "Working"
            case .error:   return "Error"
            }
        }
    }

    var body: some View {
        CardView {
            HStack(spacing: ADSpacing.md) {
                AvatarView(name: name, imageURL: imageURL, size: 40)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: ADSpacing.sm) {
                        Text(name)
                            .font(.adSubhead)
                            .foregroundStyle(Color.adTextPrimary)

                        StatusDot(color: status.dotColor, size: 7)
                    }

                    Text(role)
                        .font(.adCaption)
                        .foregroundStyle(Color.adTextSecondary)

                    if let task = taskDescription {
                        Text(task)
                            .font(.adCaption)
                            .foregroundStyle(Color.adTextTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()
            }
        }
    }
}

// MARK: - MiniLogLine

/// A single line of monospaced log output, styled for readability.
struct MiniLogLine: View {
    let timestamp: String
    let message: String
    var level: LogLevel = .info

    enum LogLevel: Sendable {
        case debug, info, warning, error

        var color: Color {
            switch self {
            case .debug:   return .adTextTertiary
            case .info:    return .adTextSecondary
            case .warning: return .adWarning
            case .error:   return .adError
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: ADSpacing.sm) {
            Text(timestamp)
                .font(.adCode)
                .foregroundStyle(Color.adTextTertiary)
                .frame(width: 70, alignment: .leading)

            Text(message)
                .font(.adCode)
                .foregroundStyle(level.color)
                .lineLimit(3)
        }
    }
}

// MARK: - Model Capacity Metadata

public struct ModelCapacityInfo: Sendable {
    public let label: String
    public let monthlyCapacity: String
    public let badgeColor: Color
    public let tierName: String
}

public func modelCapacityInfo(for model: String) -> ModelCapacityInfo? {
    let lower = model.lowercased()
    if lower.contains("mimo-v2.5") && !lower.contains("pro") {
        return ModelCapacityInfo(label: "150k/mo", monthlyCapacity: "150,400 req/mo", badgeColor: .adSuccess, tierName: "Cheapest")
    } else if lower.contains("deepseek-v4-flash") {
        return ModelCapacityInfo(label: "38k/mo", monthlyCapacity: "37,800 req/mo", badgeColor: .adSuccess, tierName: "Ultra Fast")
    } else if lower.contains("qwen3.7-plus") || lower.contains("hy3") {
        return ModelCapacityInfo(label: "21.6k/mo", monthlyCapacity: "21,600 req/mo", badgeColor: .adSuccess, tierName: "High Throughput")
    } else if lower.contains("minimax-m2.7") {
        return ModelCapacityInfo(label: "17k/mo", monthlyCapacity: "17,000 req/mo", badgeColor: .adSuccess, tierName: "High Throughput")
    } else if lower.contains("qwen3.6-plus") || lower.contains("mimo-v2.5-pro") || lower.contains("minimax-m3") {
        return ModelCapacityInfo(label: "16k/mo", monthlyCapacity: "16,000 req/mo", badgeColor: .adSuccess, tierName: "Balanced")
    } else if lower.contains("gpt-5.6-luna") {
        return ModelCapacityInfo(label: "10k/mo", monthlyCapacity: "10,250 req/mo", badgeColor: .adInfo, tierName: "Balanced")
    } else if lower.contains("kimi-k2.7") {
        return ModelCapacityInfo(label: "6.7k/mo", monthlyCapacity: "6,750 req/mo", badgeColor: .adInfo, tierName: "Agentic Code")
    } else if lower.contains("kimi-k2.6") {
        return ModelCapacityInfo(label: "5.7k/mo", monthlyCapacity: "5,750 req/mo", badgeColor: .adInfo, tierName: "Agentic Code")
    } else if lower.contains("deepseek-v4-pro") {
        return ModelCapacityInfo(label: "5.2k/mo", monthlyCapacity: "5,200 req/mo", badgeColor: .adInfo, tierName: "Reasoning")
    } else if lower.contains("glm-5.2") || lower.contains("glm-5.1") {
        return ModelCapacityInfo(label: "4.3k/mo", monthlyCapacity: "4,300 req/mo", badgeColor: .adInfo, tierName: "Reasoning")
    } else if lower.contains("qwen3.7-max") {
        return ModelCapacityInfo(label: "1.7k/mo", monthlyCapacity: "1,690 req/mo", badgeColor: .adOrange, tierName: "Frontier")
    } else if lower.contains("glm-5.3") {
        return ModelCapacityInfo(label: "1.1k/mo", monthlyCapacity: "1,080 req/mo", badgeColor: .adOrange, tierName: "Flagship Reasoning")
    } else if lower.contains("qwen3.8-max") {
        return ModelCapacityInfo(label: "810/mo", monthlyCapacity: "810 req/mo", badgeColor: .adWarning, tierName: "Flagship")
    } else if lower.contains("grok-4.5") {
        return ModelCapacityInfo(label: "600/mo", monthlyCapacity: "600 req/mo", badgeColor: .adWarning, tierName: "Frontier")
    } else if lower.contains("kimi-k3") {
        return ModelCapacityInfo(label: "490/mo", monthlyCapacity: "490 req/mo", badgeColor: .adWarning, tierName: "Flagship")
    }
    return nil
}

// MARK: - Paginated Searchable Combobox

public struct PaginatedSearchableCombobox: View {
    @Binding public var selection: String
    public let title: String
    public let items: [String]
    public let pageSize: Int
    public var onRefresh: (() -> Void)?

    @State private var isPresented = false
    @State private var searchQuery = ""
    @State private var currentPage = 0
    @State private var selectedCategory: ModelCategory = .all

    public enum ModelCategory: String, CaseIterable, Identifiable {
        case all = "All"
        case cheapest = "Cheapest"
        case coding = "Coding"
        case reasoning = "Reasoning"
        case fast = "Fast"

        public var id: String { rawValue }
    }

    public init(
        selection: Binding<String>,
        title: String = "Select Model",
        items: [String],
        pageSize: Int = 8,
        onRefresh: (() -> Void)? = nil
    ) {
        self._selection = selection
        self.title = title
        self.items = items
        self.pageSize = pageSize
        self.onRefresh = onRefresh
    }

    private var filteredItems: [String] {
        items.filter { item in
            let queryMatch = searchQuery.isEmpty || item.localizedCaseInsensitiveContains(searchQuery)
            let categoryMatch: Bool
            let lower = item.lowercased()
            switch selectedCategory {
            case .all:
                categoryMatch = true
            case .cheapest:
                categoryMatch = lower.contains("mimo") || lower.contains("flash") || lower.contains("plus") || lower.contains("hy3") || lower.contains("mini")
            case .coding:
                categoryMatch = lower.contains("code") || lower.contains("coder") || lower.contains("glm") || lower.contains("sonnet") || lower.contains("kimi")
            case .reasoning:
                categoryMatch = lower.contains("reason") || lower.contains("r1") || lower.contains("o1") || lower.contains("o3") || lower.contains("thinking") || lower.contains("grok") || lower.contains("5.3") || lower.contains("5.2")
            case .fast:
                categoryMatch = lower.contains("flash") || lower.contains("mini") || lower.contains("haiku") || lower.contains("fast") || lower.contains("air")
            }
            return queryMatch && categoryMatch
        }
    }

    private var totalPages: Int {
        max(1, Int(ceil(Double(filteredItems.count) / Double(pageSize))))
    }

    private var paginatedItems: [String] {
        let start = min(currentPage * pageSize, max(0, filteredItems.count - 1))
        let end = min(start + pageSize, filteredItems.count)
        guard start < end else { return [] }
        return Array(filteredItems[start..<end])
    }

    public var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.adSuccess)
                    .frame(width: 6, height: 6)

                Text(selection.isEmpty ? "Select Model" : selection)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.adTextPrimary)
                    .lineLimit(1)

                if let info = modelCapacityInfo(for: selection) {
                    Text(info.label)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(info.badgeColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(info.badgeColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.adTextTertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.adElevated)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.adDivider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(spacing: 0) {
                // Header & Search
                VStack(spacing: 8) {
                    HStack {
                        Text(title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.adTextPrimary)
                        Spacer()
                        if let onRefresh {
                            Button {
                                onRefresh()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Color.adOrange)
                            }
                            .buttonStyle(.plain)
                            .help("Refresh models from API")
                        }
                    }

                    // Search Field
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.adTextTertiary)

                        TextField("Search \(items.count) models...", text: $searchQuery)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .onChange(of: searchQuery) { _, _ in
                                currentPage = 0
                            }

                        if !searchQuery.isEmpty {
                            Button {
                                searchQuery = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.adTextTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.adBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.adDivider, lineWidth: 1)
                    )

                    // Category Filter Pills
                    HStack(spacing: 4) {
                        ForEach(ModelCategory.allCases) { cat in
                            Button {
                                selectedCategory = cat
                                currentPage = 0
                            } label: {
                                Text(cat.rawValue)
                                    .font(.system(size: 9, weight: selectedCategory == cat ? .bold : .medium))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(selectedCategory == cat ? Color.adOrange.opacity(0.2) : Color.adElevated)
                                    .foregroundStyle(selectedCategory == cat ? Color.adOrange : Color.adTextSecondary)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(10)
                .background(Color.adNavy)

                Divider()

                // Items List
                if paginatedItems.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "tray")
                            .font(.system(size: 18))
                            .foregroundStyle(Color.adTextTertiary)
                        Text("No matching models found")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.adTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                } else {
                    ScrollView {
                        VStack(spacing: 2) {
                            ForEach(paginatedItems, id: \.self) { item in
                                Button {
                                    selection = item
                                    isPresented = false
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(item)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(selection == item ? Color.adOrange : Color.adTextPrimary)
                                            .lineLimit(1)

                                        Spacer()

                                        if let info = modelCapacityInfo(for: item) {
                                            Text(info.label)
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(info.badgeColor)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(info.badgeColor.opacity(0.12))
                                                .clipShape(RoundedRectangle(cornerRadius: 3))
                                        }

                                        if selection == item {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(Color.adOrange)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(selection == item ? Color.adOrange.opacity(0.12) : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 240)
                }

                Divider()

                // Pagination Footer
                HStack {
                    Text("\(filteredItems.count) models")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.adTextTertiary)

                    Spacer()

                    HStack(spacing: 6) {
                        Button {
                            if currentPage > 0 { currentPage -= 1 }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(currentPage > 0 ? Color.adTextPrimary : Color.adTextTertiary)
                        }
                        .buttonStyle(.plain)
                        .disabled(currentPage == 0)

                        Text("Page \(currentPage + 1) of \(totalPages)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.adTextSecondary)

                        Button {
                            if currentPage < totalPages - 1 { currentPage += 1 }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(currentPage < totalPages - 1 ? Color.adTextPrimary : Color.adTextTertiary)
                        }
                        .buttonStyle(.plain)
                        .disabled(currentPage >= totalPages - 1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.adNavy)
            }
            .frame(width: 320)
            .background(Color.adBackground)
        }
    }
}

// MARK: - Preview Provider

#if DEBUG
struct Theme_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VStack(spacing: ADSpacing.xl) {
                // Buttons
                SectionHeader(title: "Buttons", subtitle: "")
                HStack {
                    AdventurersButton(title: "Primary", style: .primary) {}
                    AdventurersButton(title: "Secondary", style: .secondary) {}
                    AdventurersButton(title: "Ghost", style: .ghost) {}
                    AdventurersButton(title: "Destructive", style: .destructive) {}
                }

                // Badges
                SectionHeader(title: "Badges", subtitle: "")
                HStack {
                    BadgeView(text: "Syntax", color: .adSyntaxGate)
                    BadgeView(text: "Memory", color: .adMemoryGate)
                    BadgeView(text: "Active", color: .adSuccess)
                    BadgeView(text: "Warning", color: .adWarning, size: .small)
                }

                // Status dots
                SectionHeader(title: "Status Dots", subtitle: "")
                HStack {
                    StatusDot(color: .adSuccess)
                    StatusDot(color: .adWarning, isPulsing: true)
                    StatusDot(color: .adError, size: 12)
                    StatusDot(color: .adTextTertiary)
                }

                // Progress rings
                SectionHeader(title: "Progress Rings", subtitle: "")
                HStack {
                    ProgressRing(progress: 0.7, showLabel: true)
                    ProgressRing(progress: 0.35, size: 60, color: .adSuccess, showLabel: true)
                    ProgressRing(progress: 0.9, lineWidth: 6, size: 52, color: .adInfo)
                }

                // Search
                SectionHeader(title: "Search Field", subtitle: "")
                SearchField(text: .constant(""), placeholder: "Search agents…")

                // Toggle pill
                SectionHeader(title: "Toggle Pill", subtitle: "")
                TogglePill(options: ["All", "Active", "Idle", "Error"], selectedIndex: .constant(0))

                // Alert banner
                SectionHeader(title: "Alert Banner", subtitle: "")
                AlertBanner(kind: .success, message: "Gate passed: Compilation complete.")

                // Agent card
                SectionHeader(title: "Agent Status Card", subtitle: "")
                AgentStatusCard(
                    name: "Navigator",
                    role: "Code Agent",
                    status: .working,
                    taskDescription: "Analyzing auth module…"
                )

                // Gate badges
                SectionHeader(title: "Gate Status Badges", subtitle: "")
                HStack {
                    GateStatusBadge(gate: .syntax, passed: true)
                    GateStatusBadge(gate: .compilation, passed: false)
                    GateStatusBadge(gate: .memory)
                }

                // Skeleton
                SectionHeader(title: "Skeleton Loading", subtitle: "")
                VStack(alignment: .leading, spacing: ADSpacing.sm) {
                    SkeletonView(height: 14, width: 200)
                    SkeletonView(height: 10)
                    SkeletonView(height: 10, width: 160)
                }

                // Log lines
                SectionHeader(title: "Log Lines", subtitle: "")
                VStack(alignment: .leading) {
                    MiniLogLine(timestamp: "12:34:01", message: "Gate syntax: passed", level: .info)
                    MiniLogLine(timestamp: "12:34:02", message: "Warning: retrying connection", level: .warning)
                    MiniLogLine(timestamp: "12:34:03", message: "Error: compilation failed", level: .error)
                }
            }
            .padding(ADSpacing.xl)
        }
        .frame(width: 600, height: 900)
        .background(Color.adBackground)
    }
}
#endif
