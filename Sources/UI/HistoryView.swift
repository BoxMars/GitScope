import SwiftUI

struct GraphCell: View {
    var row: GraphRow
    var isMerge: Bool
    var laneCount: Int
    var height: CGFloat

    private static let maxLane = GraphLayout.maxVisibleLanes - 1

    private func x(_ lane: Int) -> CGFloat {
        Theme.laneWidth / 2 + CGFloat(min(max(lane, 0), Self.maxLane)) * Theme.laneWidth
    }

    var body: some View {
        Canvas { context, size in
            let nodeY = size.height / 2
            func curve(from p0: CGPoint, to p1: CGPoint) -> Path {
                var path = Path()
                path.move(to: p0)
                let dy = (p1.y - p0.y)
                path.addCurve(to: p1,
                              control1: CGPoint(x: p0.x, y: p0.y + dy * 0.6),
                              control2: CGPoint(x: p1.x, y: p1.y - dy * 0.6))
                return path
            }

            if row.continuesDown {
                var path = Path()
                path.move(to: CGPoint(x: x(row.lane), y: nodeY))
                path.addLine(to: CGPoint(x: x(row.lane), y: size.height))
                context.stroke(path, with: .color(Theme.graphColor(row.color).opacity(0.9)), lineWidth: 1.6)
            }

            for lane in row.through {
                var path = Path()
                path.move(to: CGPoint(x: x(lane.lane), y: 0))
                path.addLine(to: CGPoint(x: x(lane.lane), y: size.height))
                context.stroke(path, with: .color(Theme.graphColor(lane.color).opacity(0.9)), lineWidth: 1.6)
            }

            for lane in row.incoming {
                let path = curve(from: CGPoint(x: x(lane.lane), y: 0),
                                 to: CGPoint(x: x(row.lane), y: nodeY))
                context.stroke(path, with: .color(Theme.graphColor(lane.color)), lineWidth: 1.6)
            }

            for lane in row.outgoing {
                let path = curve(from: CGPoint(x: x(row.lane), y: nodeY),
                                 to: CGPoint(x: x(lane.lane), y: size.height))
                context.stroke(path, with: .color(Theme.graphColor(lane.color)), lineWidth: 1.6)
            }

            if isMerge {
                let rect = CGRect(x: x(row.lane) - 4, y: nodeY - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: rect), with: .color(Theme.contentBackground))
                context.stroke(Path(ellipseIn: rect), with: .color(Theme.graphColor(row.color)), lineWidth: 2)
            } else {
                let rect = CGRect(x: x(row.lane) - 4, y: nodeY - 4, width: 8, height: 8)
                context.fill(Path(ellipseIn: rect), with: .color(Theme.graphColor(row.color)))
                context.stroke(Path(ellipseIn: rect), with: .color(Theme.graphColor(row.color)), lineWidth: 1)
            }
        }
        .frame(width: max(CGFloat(min(laneCount, GraphLayout.maxVisibleLanes)) * Theme.laneWidth, Theme.laneWidth), height: height)
    }
}

struct CommitRowView: View {
    var commit: Commit
    var row: GraphRow?
    var laneCount: Int
    var isSelected: Bool
    var isHighlighted: Bool

    var body: some View {
        HStack(spacing: 6) {
            if let row {
                GraphCell(row: row, isMerge: commit.isMerge, laneCount: laneCount, height: Theme.commitRowHeight)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(commit.subject.isEmpty ? "(no message)" : commit.subject)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                    ForEach(commit.refs.prefix(2)) { ref in
                        RefBadge(ref: ref).fixedSize()
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 5) {
                    Text(commit.author)
                        .lineLimit(1)
                    Text("·")
                    Text(commit.relativeAuthorDate)
                    Text("·")
                    Text(commit.shortHash)
                        .font(Theme.monoSmall)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.trailing, 8)
        .frame(height: Theme.commitRowHeight)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isSelected ? Theme.selectionBackground : (isHighlighted ? Color.primary.opacity(0.05) : Color.clear))
                .padding(.horizontal, 2)
        )
        .contentShape(Rectangle())
    }
}

struct HistoryListView: View {
    @ObservedObject var session: RepoSession
    @State private var hoveredHash: String?
    @State private var branchSheet: BranchSheetMode?
    @State private var tagTarget: Commit?
    @State private var resetTarget: Commit?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.subtleBorder)
            if session.displayCommits.isEmpty {
                EmptyHint(icon: "clock", title: "No commits",
                          subtitle: session.isLoading ? "Loading…" : "This repository has no commits yet.")
            } else {
                ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(session.displayCommits) { commit in
                            CommitRowView(commit: commit,
                                          row: session.graph.rows[commit.hash],
                                          laneCount: session.graph.laneCount,
                                          isSelected: session.selection == .commit(commit.hash),
                                          isHighlighted: hoveredHash == commit.hash)
                                .onHover { hovering in
                                    hoveredHash = hovering ? commit.hash : (hoveredHash == commit.hash ? nil : hoveredHash)
                                }
                                .onTapGesture {
                                    Task { await session.select(commit: commit) }
                                }
                                .id(commit.hash)
                                .contextMenu { contextMenu(for: commit) }
                        }
                        if session.hasMore {
                            Button("Load more commits") {
                                Task { await session.loadMore() }
                            }
                            .buttonStyle(.link)
                            .padding(10)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                }
                .background(Theme.contentBackground)
                .onChange(of: session.selection) { _, newValue in
                    if case .commit(let hash) = newValue {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(hash, anchor: .center)
                        }
                    }
                }
                .onAppear {
                    if case .commit(let hash) = session.selection {
                        proxy.scrollTo(hash, anchor: .center)
                    }
                }
                }
            }
        }
        .sheet(item: $branchSheet) { mode in
            NewBranchSheet(session: session, mode: mode)
        }
        .sheet(item: $tagTarget) { commit in
            NewTagSheet(session: session, targetHash: commit.hash)
        }
        .confirmationDialog("Reset current branch", isPresented: Binding(
            get: { resetTarget != nil },
            set: { if !$0 { resetTarget = nil } }
        )) {
            ForEach(RepoSession.ResetMode.allCases) { mode in
                Button("Reset \(mode.label) to \(resetTarget?.shortHash ?? "")") {
                    if let target = resetTarget {
                        Task { await session.reset(to: target.hash, mode: mode) }
                    }
                    resetTarget = nil
                }
            }
            Button("Cancel", role: .cancel) { resetTarget = nil }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField("Filter commits", text: $session.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if let ref = session.filterRef {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                    Text(ref).font(.system(size: 10, weight: .medium)).lineLimit(1)
                    Button {
                        Task { await session.setFilterRef(nil) }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 8))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
            }
            Spacer(minLength: 4)
            if session.isLoading {
                ProgressView().controlSize(.mini).scaleEffect(0.7)
            }
            Text("\(session.displayCommits.count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(Theme.toolbarBackground)
    }

    @ViewBuilder
    private func contextMenu(for commit: Commit) -> some View {
        Button("Checkout \(commit.shortHash)") {
            Task { await session.checkoutCommit(commit.hash) }
        }
        Button("Create branch here…") {
            branchSheet = .create(startPoint: commit.hash)
        }
        Button("Create tag here…") {
            tagTarget = commit
        }
        Divider()
        Button("Cherry-pick onto current branch") {
            Task { await session.cherryPick(commit.hash) }
        }
        Button("Revert commit") {
            Task { await session.revert(commit.hash) }
        }
        Divider()
        Menu("Reset current branch to here") {
            ForEach(RepoSession.ResetMode.allCases) { mode in
                Button("\(mode.label) reset") {
                    resetTarget = commit
                }
            }
        }
        Divider()
        Button("Copy patch") {
            Task { await session.copyPatch(for: commit.hash) }
        }
        Button("Save patch…") {
            Task { await session.savePatch(for: commit.hash) }
        }
        Divider()
        Button("Copy hash") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(commit.hash, forType: .string)
        }
        Button("Copy subject") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(commit.subject, forType: .string)
        }
    }
}

enum BranchSheetMode: Identifiable {
    case create(startPoint: String?)
    case rename(Branch)

    var id: String {
        switch self {
        case .create(let start): return "create-\(start ?? "head")"
        case .rename(let branch): return "rename-\(branch.fullName)"
        }
    }
}
