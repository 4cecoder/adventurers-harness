// TUI - SkillsPanel
// Skills management panel inspired by Codex's skill system:
// "Bundles instructions, resources, and scripts so the agent can reliably complete tasks."

import SwiftUI

// MARK: - Skill Model

/// A skill bundles instructions, resources, and scripts so the agent can reliably complete tasks.
public struct Skill: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var description: String
    public var category: SkillCategory
    public var isEnabled: Bool
    public var version: String
    public var lastUsed: Date?
    public var instructions: String
    public var resources: [SkillResource]
    public var scripts: [SkillScript]
    public var group: SkillGroup

    public init(
        id: UUID = UUID(),
        name: String,
        description: String,
        category: SkillCategory,
        isEnabled: Bool = true,
        version: String = "1.0.0",
        lastUsed: Date? = nil,
        instructions: String = "",
        resources: [SkillResource] = [],
        scripts: [SkillScript] = [],
        group: SkillGroup = .custom
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
        self.isEnabled = isEnabled
        self.version = version
        self.lastUsed = lastUsed
        self.instructions = instructions
        self.resources = resources
        self.scripts = scripts
        self.group = group
    }
}

// MARK: - Skill Category

/// Skill categories with associated SF Symbol icons and accent colors.
public enum SkillCategory: String, CaseIterable, Codable, Sendable {
    case codeGeneration = "Code Generation"
    case testing = "Testing"
    case deployment = "Deployment"
    case documentation = "Documentation"
    case research = "Research"
    case custom = "Custom"

    public var icon: String {
        switch self {
        case .codeGeneration: "chevron.left.forwardslash.chevron.right"
        case .testing: "checkmark.shield"
        case .deployment: "arrow.up.circle"
        case .documentation: "doc.text"
        case .research: "magnifyingglass"
        case .custom: "wrench.and.screwdriver"
        }
    }

    public var color: String {
        switch self {
        case .codeGeneration: "blue"
        case .testing: "green"
        case .deployment: "orange"
        case .documentation: "purple"
        case .research: "teal"
        case .custom: "gray"
        }
    }

    public var accentColor: Color {
        switch self {
        case .codeGeneration: .blue
        case .testing: .green
        case .deployment: .orange
        case .documentation: .purple
        case .research: .teal
        case .custom: .gray
        }
    }
}

// MARK: - Skill Group

/// Organizes skills into built-in or user-created groups.
public enum SkillGroup: String, CaseIterable, Codable, Sendable {
    case builtIn = "Built-in"
    case custom = "Custom"

    public var displayName: String { rawValue }
}

// MARK: - Skill Resource

/// A resource bundled with a skill (file, URL, or inline content).
public struct SkillResource: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var type: ResourceType
    public var path: String

    public init(id: UUID = UUID(), name: String, type: ResourceType, path: String) {
        self.id = id
        self.name = name
        self.type = type
        self.path = path
    }

    public enum ResourceType: String, Codable, Sendable {
        case file, url, inline
    }
}

// MARK: - Skill Script

/// A script bundled with a skill for execution.
public struct SkillScript: Identifiable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var language: String
    public var content: String
    public var isExecutable: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        language: String = "bash",
        content: String = "",
        isExecutable: Bool = true
    ) {
        self.id = id
        self.name = name
        self.language = language
        self.content = content
        self.isExecutable = isExecutable
    }
}

// MARK: - Skill Store

/// Observable store managing the collection of skills.
/// Persists state and supports import/export operations.
@MainActor
@Observable
public final class SkillStore {
    public var skills: [Skill] = Skill.builtInSamples
    public var searchText: String = ""
    public var selectedCategory: SkillCategory? = nil
    public var selectedSkill: Skill? = nil
    public var isDetailOpen: Bool = false

    public init() {}

    // MARK: - Filtered Queries

    /// Skills filtered by search text and category.
    public var filteredSkills: [Skill] {
        skills.filter { skill in
            let matchesSearch = searchText.isEmpty
                || skill.name.localizedCaseInsensitiveContains(searchText)
                || skill.description.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = selectedCategory == nil || skill.category == selectedCategory
            return matchesSearch && matchesCategory
        }
    }

    /// Skills grouped by their SkillGroup.
    public var groupedSkills: [(SkillGroup, [Skill])] {
        let grouped = Dictionary(grouping: filteredSkills, by: \.group)
        return SkillGroup.allCases.compactMap { group in
            guard let items = grouped[group], !items.isEmpty else { return nil }
            return (group, items)
        }
    }

    /// Count of currently enabled skills.
    public var enabledCount: Int {
        skills.filter(\.isEnabled).count
    }

    // MARK: - Mutations

    public func toggleSkill(_ skill: Skill) {
        guard let index = skills.firstIndex(where: { $0.id == skill.id }) else { return }
        skills[index].isEnabled.toggle()
    }

    public func updateLastUsed(_ skill: Skill) {
        guard let index = skills.firstIndex(where: { $0.id == skill.id }) else { return }
        skills[index].lastUsed = Date()
    }

    public func addSkill(_ skill: Skill) {
        skills.append(skill)
    }

    public func removeSkill(_ skill: Skill) {
        skills.removeAll { $0.id == skill.id }
    }

    public func moveSkill(from source: IndexSet, to destination: Int, in group: SkillGroup) {
        var groupSkills = skills.filter { $0.group == group }
        groupSkills.move(fromOffsets: source, toOffset: destination)

        // Rebuild the full array preserving group order
        var reordered: [Skill] = []
        for g in SkillGroup.allCases {
            if g == group {
                reordered.append(contentsOf: groupSkills)
            } else {
                reordered.append(contentsOf: skills.filter { $0.group == g })
            }
        }
        skills = reordered
    }

    // MARK: - Import / Export

    public func exportSkills() -> Data? {
        try? JSONEncoder().encode(skills)
    }

    public func importSkills(from data: Data) -> Bool {
        guard let decoded = try? JSONDecoder().decode([Skill].self, from: data) else { return false }
        let existingIDs = Set(skills.map(\.id))
        let newSkills = decoded.filter { !existingIDs.contains($0.id) }
        skills.append(contentsOf: newSkills)
        return true
    }
}

// MARK: - Skill Card View

/// A single skill card displaying name, description, category, toggle, and version.
/// Features hover elevation, active glow, and smooth toggle animation.
public struct SkillCardView: View {
    let skill: Skill
    let onToggle: () -> Void
    let onTap: () -> Void

    @State private var isHovered = false

    public init(skill: Skill, onToggle: @escaping () -> Void, onTap: @escaping () -> Void) {
        self.skill = skill
        self.onToggle = onToggle
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                // Top row: icon + version badge
                HStack {
                    Image(systemName: skill.category.icon)
                        .font(.title3)
                        .foregroundStyle(skill.category.accentColor)
                        .frame(width: 28, height: 28)

                    Spacer()

                    Text(skill.version)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(skill.category.accentColor.opacity(0.15))
                        )
                        .foregroundStyle(skill.category.accentColor)
                }

                // Name
                Text(skill.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                // Description
                Text(skill.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxHeight: .infinity, alignment: .top)

                Divider()

                // Bottom row: toggle + last used + group badge
                HStack {
                    // Enable/disable toggle
                    Toggle("", isOn: Binding(
                        get: { skill.isEnabled },
                        set: { _ in onToggle() }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()

                    Spacer()

                    // Last used timestamp
                    if let lastUsed = skill.lastUsed {
                        Text(lastUsed.relativeFormatted)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    // Group badge
                    Text(skill.group.displayName)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(skill.group == .builtIn
                                    ? Color.accentColor.opacity(0.12)
                                    : Color.secondary.opacity(0.12))
                        )
                        .foregroundStyle(skill.group == .builtIn ? .accent : .secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 160)
            .background(cardBackground)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(
            color: skill.isEnabled
                ? skill.category.accentColor.opacity(isHovered ? 0.35 : 0.15)
                : .clear,
            radius: isHovered ? 8 : 4,
            y: isHovered ? 4 : 2
        )
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.background)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        skill.isEnabled
                            ? skill.category.accentColor.opacity(0.4)
                            : Color.secondary.opacity(0.2),
                        lineWidth: skill.isEnabled ? 1.5 : 1
                    )
            )
            .overlay(
                // Active glow border
                skill.isEnabled
                    ? RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            skill.category.accentColor.opacity(0.12),
                            lineWidth: 4
                        )
                    : nil
            )
    }
}

// MARK: - Skill Detail View

/// Sheet presenting full skill details: instructions, resources, scripts, and configuration.
public struct SkillDetailView: View {
    let skill: Skill
    let onToggle: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    public init(skill: Skill, onToggle: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.skill = skill
        self.onToggle = onToggle
        self.onDelete = onDelete
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                headerSection

                // Toggle + Meta
                configurationSection

                // Instructions preview
                instructionsSection

                // Resources list
                if !skill.resources.isEmpty {
                    resourcesSection
                }

                // Scripts
                if !skill.scripts.isEmpty {
                    scriptsSection
                }
            }
            .padding(28)
        }
        .navigationTitle(skill.name)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .destructiveAction) {
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            }
        }
        .frame(minWidth: 520, minHeight: 480)
    }

    // MARK: - Sections

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: skill.category.icon)
                    .font(.largeTitle)
                    .foregroundStyle(skill.category.accentColor)
                VStack(alignment: .leading) {
                    Text(skill.name)
                        .font(.title2.bold())
                    Text(skill.category.rawValue)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("v\(skill.version)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(skill.category.accentColor.opacity(0.12))
                    )
                    .foregroundStyle(skill.category.accentColor)
            }

            Text(skill.description)
                .font(.body)
                .foregroundStyle(.secondary)

            if let lastUsed = skill.lastUsed {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text("Last used \(lastUsed.relativeFormatted)")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
    }

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configuration")
                .font(.headline)

            HStack {
                Label(
                    skill.isEnabled ? "Enabled" : "Disabled",
                    systemImage: skill.isEnabled ? "checkmark.circle.fill" : "xmark.circle"
                )
                .foregroundStyle(skill.isEnabled ? .green : .secondary)

                Spacer()

                Toggle("Active", isOn: Binding(
                    get: { skill.isEnabled },
                    set: { _ in onToggle() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.06))
            )

            HStack {
                Label(skill.group.displayName, systemImage: "folder")
                Spacer()
                Label(skill.category.rawValue, systemImage: skill.category.icon)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Instructions Preview")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(skill.instructions.isEmpty ? "No instructions provided." : skill.instructions)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(skill.instructions.isEmpty ? .tertiary : .primary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(nsColor: .controlBackgroundColor))
                    )
            }
            .frame(maxHeight: 200)
        }
    }

    private var resourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Resources")
                .font(.headline)

            ForEach(skill.resources) { resource in
                HStack {
                    Image(systemName: resourceIcon(for: resource.type))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    Text(resource.name)
                        .font(.callout)
                    Spacer()
                    Text(resource.path)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.06))
                )
            }
        }
    }

    private var scriptsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scripts")
                .font(.headline)

            ForEach(skill.scripts) { script in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(script.name)
                            .font(.callout.weight(.medium))
                        Text(script.language)
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.blue.opacity(0.12)))
                            .foregroundStyle(.blue)
                        if script.isExecutable {
                            Image(systemName: "play.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }

                    Text(script.content.isEmpty ? "# empty script" : script.content)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.06))
                )
            }
        }
    }

    private func resourceIcon(for type: SkillResource.ResourceType) -> String {
        switch type {
        case .file: "doc"
        case .url: "link"
        case .inline: "text.alignleft"
        }
    }
}

// MARK: - Create New Skill Card

/// Placeholder card with dashed border and + icon for creating new skills.
public struct CreateSkillCardView: View {
    let action: () -> Void
    @State private var isHovered = false

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: "plus.circle.dashed")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Create New Skill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 160)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        style: StrokeStyle(
                            lineWidth: 2,
                            dash: [8, 6],
                            lineCap: .round
                        )
                    )
                    .foregroundStyle(isHovered ? .accent : .tertiary)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Skills Panel View

/// Main skills management panel with search, category filtering, grid layout, and drag-to-reorder.
public struct SkillsPanelView: View {
    @State private var store = SkillStore()
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var showCreateSheet = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Search and filter bar
            searchBar
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            Divider()

            // Category pills
            categoryPills
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

            Divider()

            // Skills grid
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if store.groupedSkills.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.groupedSkills, id: \.0) { group, skills in
                            groupSection(group: group, skills: skills)
                        }
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Skills")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    isImporting = true
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }

                Button {
                    isExporting = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }

                Button {
                    showCreateSheet = true
                } label: {
                    Label("New Skill", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $store.isDetailOpen) {
            if let skill = store.selectedSkill {
                SkillDetailView(
                    skill: skill,
                    onToggle: { store.toggleSkill(skill) },
                    onDelete: { store.removeSkill(skill) }
                )
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            createSkillSheet
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
        .fileExporter(
            isPresented: $isExporting,
            document: SkillsExportDocument(skills: store.skills),
            contentType: .json,
            defaultFilename: "adventurers-skills"
        ) { _ in }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search skills...", text: $store.searchText)
                .textFieldStyle(.plain)

            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()
                .frame(height: 20)

            Text("\(store.enabledCount)/\(store.skills.count) active")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    // MARK: - Category Pills

    private var categoryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryPill(nil, label: "All")

                ForEach(SkillCategory.allCases, id: \.self) { category in
                    categoryPill(category, label: category.rawValue)
                }
            }
        }
    }

    private func categoryPill(_ category: SkillCategory?, label: String) -> some View {
        let isSelected = store.selectedCategory == category
        let color = category?.accentColor ?? .accentColor

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                store.selectedCategory = category
            }
        } label: {
            HStack(spacing: 4) {
                if let category {
                    Image(systemName: category.icon)
                        .font(.caption)
                }
                Text(label)
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? color.opacity(0.2) : Color.secondary.opacity(0.1))
            )
            .foregroundStyle(isSelected ? color : .secondary)
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? color.opacity(0.4) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Group Section

    private func groupSection(group: SkillGroup, skills: [Skill]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Group header
            HStack {
                Image(systemName: group == .builtIn ? "lock.shield" : "person.crop.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(group.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("(\(skills.count))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // 2-column grid
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)],
                spacing: 14
            ) {
                ForEach(skills) { skill in
                    SkillCardView(
                        skill: skill,
                        onToggle: { store.toggleSkill(skill) },
                        onTap: {
                            store.selectedSkill = skill
                            store.isDetailOpen = true
                        }
                    )
                    .onDrag {
                        NSItemProvider(object: skill.id.uuidString as NSString)
                    }
                }

                // "Create New Skill" card
                CreateSkillCardView {
                    showCreateSheet = true
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No skills found")
                .font(.title3.weight(.medium))
            Text("Create a new skill or adjust your filters.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }

    // MARK: - Create Skill Sheet

    private var createSkillSheet: some View {
        NavigationStack {
            CreateSkillForm { skill in
                store.addSkill(skill)
                showCreateSheet = false
            }
        }
    }

    // MARK: - Import Handling

    private func handleImport(_ result: Result<[URL], Error>) {
        guard let urls = try? result.get(),
              let url = urls.first,
              let data = try? Data(contentsOf: url) else { return }
        _ = store.importSkills(from: data)
    }
}

// MARK: - Create Skill Form

/// Form for creating a new skill with name, description, category, and instructions.
public struct CreateSkillForm: View {
    let onCreate: (Skill) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var description = ""
    @State private var category: SkillCategory = .custom
    @State private var instructions = ""
    @State private var version = "1.0.0"

    public init(onCreate: @escaping (Skill) -> Void) {
        self.onCreate = onCreate
    }

    public var body: some View {
        Form {
            Section("Basic Info") {
                TextField("Skill Name", text: $name)
                TextField("Description", text: $description, axis: .vertical)
                    .lineLimit(3...6)
                TextField("Version", text: $version)
            }

            Section("Category") {
                Picker("Category", selection: $category) {
                    ForEach(SkillCategory.allCases, id: \.self) { cat in
                        Label(cat.rawValue, systemImage: cat.icon)
                            .tag(cat)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Instructions") {
                TextEditor(text: $instructions)
                    .font(.system(.caption, design: .monospaced))
                    .frame(minHeight: 120)
                    .scrollContentBackground(.visible)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("New Skill")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    let skill = Skill(
                        name: name,
                        description: description,
                        category: category,
                        version: version,
                        instructions: instructions,
                        group: .custom
                    )
                    onCreate(skill)
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .frame(minWidth: 420, minHeight: 440)
    }
}

// MARK: - Export Document

/// FileDocument for exporting skills as JSON.
public struct SkillsExportDocument: FileDocument {
    public static var readableContentTypes: [UTType] { [.json] }

    public let skills: [Skill]

    public init(skills: [Skill]) {
        self.skills = skills
    }

    public init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let decoded = try? JSONDecoder().decode([Skill].self, from: data) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.skills = decoded
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = try JSONEncoder().encode(skills)
        return FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Date Formatting

extension Date {
    /// Human-readable relative time string (e.g., "2 hours ago", "Just now").
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - Preview Provider

#if DEBUG
struct SkillsPanelView_Previews: PreviewProvider {
    static var previews: some View {
        SkillsPanelView()
            .frame(minWidth: 720, minHeight: 560)
    }
}
#endif

// MARK: - Built-in Skill Samples

extension Skill {
    /// Pre-populated built-in skills for demonstration and development.
    static let builtInSamples: [Skill] = [
        Skill(
            name: "Swift Code Generator",
            description: "Generates Swift code following Apple's API design guidelines with full documentation markup.",
            category: .codeGeneration,
            version: "2.1.0",
            lastUsed: Date().addingTimeInterval(-3600),
            instructions: "Generate Swift code with # available Swift 5.9+ features. Include doc comments, handle errors with typed throws, use async/await where applicable.",
            resources: [
                SkillResource(name: "Swift Style Guide", type: .url, path: "https://swift.org/documentation/api-design-guidelines/"),
                SkillResource(name: "Stdlib Reference", type: .url, path: "https://developer.apple.com/documentation/swift/swift-standard-library"),
            ],
            scripts: [
                SkillScript(name: "lint-check.sh", language: "bash", content: "swiftlint lint --strict --reporter github-actions-logging"),
            ],
            group: .builtIn
        ),
        Skill(
            name: "Test Synthesizer",
            description: "Creates XCTest suites with async test patterns, mocking, and 80%+ coverage targets.",
            category: .testing,
            version: "1.4.0",
            lastUsed: Date().addingTimeInterval(-86400),
            instructions: "Generate XCTest classes using async/await, swift-testing macros where available, mock objects with protocol conformance.",
            resources: [
                SkillResource(name: "XCTest Docs", type: .url, path: "https://developer.apple.com/documentation/xctest"),
            ],
            scripts: [
                SkillScript(name: "coverage-report.sh", language: "bash", content: "xcodebuild test -enableCodeCoverage YES | xcpretty"),
            ],
            group: .builtIn
        ),
        Skill(
            name: "Vapor Deployer",
            description: "Packages server-side Swift for Docker and Linux deployment with Nginx reverse proxy.",
            category: .deployment,
            version: "1.0.0",
            instructions: "Create Dockerfile with Swift 5.9 image, multi-stage build, Nginx config, docker-compose.yml.",
            group: .builtIn
        ),
        Skill(
            name: "DocC Builder",
            description: "Generates DocC documentation bundles with code snippets and tutorials.",
            category: .documentation,
            version: "1.2.0",
            instructions: "Create .docc bundles with articles, tutorials, and symbol documentation. Include code examples.",
            group: .builtIn
        ),
        Skill(
            name: "API Researcher",
            description: "Investigates Apple frameworks and third-party APIs for capability assessment.",
            category: .research,
            version: "1.0.0",
            instructions: "Research Apple and third-party APIs, compare alternatives, assess availability and deprecation status.",
            group: .builtIn
        ),
        Skill(
            name: "Custom Linter Rules",
            description: "User-defined SwiftLint rules for project-specific coding standards.",
            category: .custom,
            version: "0.1.0",
            lastUsed: Date().addingTimeInterval(-172800),
            instructions: "Define custom SwiftLint rules, configure opt-in rules, manage .swiftlint.yml.",
            group: .custom
        ),
    ]
}
