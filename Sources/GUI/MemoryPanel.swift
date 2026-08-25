// MemoryPanel.swift
// Adventurers Harness — Native Memory Tab
//
// Browses/searches/adds knowledge packets in AdventurersCore.KnowledgeRegistry — the persistent,
// zero-dependency replacement for the old Docker-based Hindsight memory server. Nothing here talks
// to Docker or any local HTTP server; it's a thin UI over the same actor the agent loop already
// queries via matchPackets(for:).

import SwiftUI
import AdventurersCore

public struct MemoryPanelView: View {
    @State private var packets: [KnowledgePacket] = []
    @State private var searchText = ""
    @State private var selectedCategoryFilter: String = "All"
    @State private var isShowingAddSheet = false
    @State private var isDeduplicating = false

    private let categoryFilters = ["All", "World Facts", "Mental Models", "Harness Safety", "Languages", "Ingested"]

    public init() {}

    private var filteredPackets: [KnowledgePacket] {
        var list = packets
        if selectedCategoryFilter != "All" {
            list = list.filter { packet in
                switch selectedCategoryFilter {
                case "World Facts":
                    return packet.category.lowercased().contains("world") || packet.title.lowercased().contains("world fact")
                case "Mental Models":
                    return packet.category.lowercased().contains("mental") || packet.title.lowercased().contains("mental model") || packet.title.lowercased().contains("architecture")
                case "Harness Safety":
                    return packet.category.lowercased().contains("safety") || packet.tags.contains("safety")
                case "Languages":
                    return packet.category.lowercased().contains("language") || packet.category.lowercased().contains("framework")
                case "Ingested":
                    return packet.category.lowercased().contains("ingest") || packet.category.lowercased().contains("notes")
                default:
                    return true
                }
            }
        }

        guard !searchText.isEmpty else { return list }
        let query = searchText.lowercased()
        return list.filter {
            $0.title.lowercased().contains(query)
                || $0.summary.lowercased().contains(query)
                || $0.tags.contains { $0.lowercased().contains(query) }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            // Cognitive Category Filter Bar
            categoryFilterBar

            Divider().overlay(Color.adDivider)

            if filteredPackets.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredPackets) { packet in
                            PacketCard(packet: packet) {
                                Task {
                                    await KnowledgeRegistry.shared.deletePacket(id: packet.id)
                                    await reload()
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(Color.adBackground)
        .task { await reload() }
        .sheet(isPresented: $isShowingAddSheet) {
            AddPacketSheet {
                Task { await reload() }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 16))
                .foregroundStyle(Color.adOrange)

            VStack(alignment: .leading, spacing: 2) {
                Text("Unified Cognitive Memory")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color.adTextPrimary)
                Text("\(packets.count) knowledge pages · Biomimetic 4-Tier Hierarchy · Accelerate Vector Index")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.adTextTertiary)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.adTextTertiary)
                TextField("Search memory...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.adElevated)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .frame(width: 200)

            Button {
                Task {
                    isDeduplicating = true
                    await KnowledgeRegistry.shared.deduplicatePackets()
                    await reload()
                    isDeduplicating = false
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isDeduplicating ? "arrow.triangle.2.circlepath" : "sparkles")
                    Text("Dedupe")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.adTextSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.adElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Run deduplication pass to prune duplicate records")

            Button {
                isShowingAddSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                    Text("Add Memory")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.adOrange)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color.adNavy)
    }

    private var categoryFilterBar: some View {
        HStack(spacing: 8) {
            ForEach(categoryFilters, id: \.self) { filter in
                Button {
                    selectedCategoryFilter = filter
                } label: {
                    Text(filter)
                        .font(.system(size: 11, weight: selectedCategoryFilter == filter ? .semibold : .regular))
                        .foregroundStyle(selectedCategoryFilter == filter ? Color.adOrange : Color.adTextSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(selectedCategoryFilter == filter ? Color.adOrange.opacity(0.15) : Color.clear)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.adBackground.opacity(0.8))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 28))
                .foregroundStyle(Color.adTextTertiary)
            Text(searchText.isEmpty ? "No knowledge packets in \(selectedCategoryFilter)" : "No matches for \"\(searchText)\"")
                .font(.system(size: 12))
                .foregroundStyle(Color.adTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reload() async {
        packets = await KnowledgeRegistry.shared.allPackets()
    }
}

// MARK: - Packet Card

private struct PacketCard: View {
    let packet: KnowledgePacket
    let onDelete: () -> Void
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(packet.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.adTextPrimary)
                    Text(packet.category)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.adTextTertiary)
                }

                Spacer()

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.adTextTertiary)
                }
                .buttonStyle(.plain)
                .help("Delete this packet")
            }

            Text(packet.summary)
                .font(.system(size: 11))
                .foregroundStyle(Color.adTextSecondary)
                .lineLimit(isExpanded ? nil : 2)

            if isExpanded && !packet.content.isEmpty {
                Text(packet.content)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.adTextSecondary)
                    .textSelection(.enabled)
                    .padding(8)
                    .background(Color.adBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if !packet.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(packet.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.adInfo)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.adInfo.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
        }
        .padding(12)
        .background(Color.adCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.adDivider, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() }
        }
    }
}

// MARK: - Add Packet Sheet

private struct AddPacketSheet: View {
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var category = "Notes"
    @State private var tagsText = ""
    @State private var content = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Memory")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.adTextPrimary)

            TextField("Title", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(8)
                .background(Color.adElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            TextField("Category (e.g. Notes, Preferences, Facts)", text: $category)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(8)
                .background(Color.adElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            TextField("Tags, comma-separated", text: $tagsText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(8)
                .background(Color.adElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            TextEditor(text: $content)
                .font(.system(size: 12))
                .frame(height: 140)
                .padding(6)
                .background(Color.adElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .scrollContentBackground(.hidden)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.adTextSecondary)
                Button("Save") {
                    let tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    Task {
                        await KnowledgeRegistry.shared.ingest(title: title, content: content, category: category, tags: tags)
                        onSaved()
                        dismiss()
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(title.isEmpty || content.isEmpty ? Color.adElevated : Color.adOrange)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .disabled(title.isEmpty || content.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 420)
        .background(Color.adBackground)
    }
}
