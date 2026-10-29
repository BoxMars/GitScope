import SwiftUI

struct GraphLegend: View {
    var onClose: (() -> Void)? = nil

    private func row(color: Color, ring: Bool = false, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                if ring {
                    Circle().stroke(color, lineWidth: 2).frame(width: 9, height: 9)
                } else {
                    Circle().fill(color).frame(width: 9, height: 9)
                }
            }
            .frame(width: 14, height: 16)
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("怎么看这张图")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .help("Close legend")
                }
            }
            row(color: Theme.graphColor(0), text: "每条竖线是一条提交链；同一条线上的圆点，后一个是前一个的父提交。")
            row(color: Theme.graphColor(1), text: "彩色曲线表示另一条分支的提交接进来，换色只是为了区分泳道。")
            row(color: Theme.graphColor(0), ring: true, text: "空心圆是 merge 提交：两个父提交，一条线向下、一条曲线分出去。")
            Text("最上面是最新提交，越往下越早。")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.hunkBackground)
    }
}

struct GraphCell: View {
    var row: GraphRow
    var isMerge: Bool
    var laneCount: Int
    var height: CGFloat
    var maxWidth: CGFloat = 150
    var simplified: Bool = false

    /// Shrink lanes to fit the available column instead of clamping them onto
    /// the last lane (which drew every extra branch on top of each other).
    private var laneWidth: CGFloat {
        guard laneCount > 0 else { return Theme.laneWidth }
        return max(1.6, min(Theme.laneWidth, maxWidth / CGFloat(laneCount)))
    }

    private var nodeRadius: CGFloat { simplified ? 4 : min(4, max(1, laneWidth * 0.34)) }
    private var lineWidth: CGFloat { simplified ? 1.6 : min(1.6, max(0.9, laneWidth * 0.14)) }

    private func x(_ lane: Int) -> CGFloat {
        let step = simplified ? Theme.laneWidth : laneWidth
        return step / 2 + CGFloat(max(lane, 0)) * step
    }

    var body: some View {
        Canvas { context, size in
            let nodeY = size.height / 2
            if simplified {
                if row.hasIncoming {
                    var path = Path()
                    path.move(to: CGPoint(x: x(0), y: 0))
                    path.addLine(to: CGPoint(x: x(0), y: nodeY - nodeRadius))
                    context.stroke(path, with: .color(Theme.graphColor(row.color).opacity(0.9)), lineWidth: lineWidth)
                }
                if row.continuesDown {
                    var path = Path()
                    path.move(to: CGPoint(x: x(0), y: nodeY + nodeRadius))
                    path.addLine(to: CGPoint(x: x(0), y: size.height))
                    context.stroke(path, with: .color(Theme.graphColor(row.color).opacity(0.9)), lineWidth: lineWidth)
                }
                let rect = CGRect(x: x(0) - nodeRadius, y: nodeY - nodeRadius, width: nodeRadius * 2, height: nodeRadius * 2)
                if isMerge {
                    context.fill(Path(ellipseIn: rect), with: .color(Theme.contentBackground))
                    context.stroke(Path(ellipseIn: rect), with: .color(Theme.graphColor(row.color)), lineWidth: max(1, lineWidth + 0.2))
                } else {
                    context.fill(Path(ellipseIn: rect), with: .color(Theme.graphColor(row.color)))
                }
                return
            }
            func curve(from p0: CGPoint, to p1: CGPoint) -> Path {
                var path = Path()
                path.move(to: p0)
                let dy = (p1.y - p0.y)
                path.addCurve(to: p1,
                              control1: CGPoint(x: p0.x, y: p0.y + dy * 0.6),
                              control2: CGPoint(x: p1.x, y: p1.y - dy * 0.6))
                return path
            }

            if row.hasIncoming {
                var path = Path()
                path.move(to: CGPoint(x: x(row.lane), y: 0))
                path.addLine(to: CGPoint(x: x(row.lane), y: nodeY - 4))
                context.stroke(path, with: .color(Theme.graphColor(row.color).opacity(0.9)), lineWidth: lineWidth)
            }

            if row.continuesDown {
                var path = Path()
                path.move(to: CGPoint(x: x(row.lane), y: nodeY + 4))
                path.addLine(to: CGPoint(x: x(row.lane), y: size.height))
                context.stroke(path, with: .color(Theme.graphColor(row.color).opacity(0.9)), lineWidth: lineWidth)
            }

            for lane in row.through {
                var path = Path()
                path.move(to: CGPoint(x: x(lane.lane), y: 0))
                path.addLine(to: CGPoint(x: x(lane.lane), y: size.height))
                context.stroke(path, with: .color(Theme.graphColor(lane.color).opacity(0.9)), lineWidth: lineWidth)
            }

            for lane in row.incoming {
                let path = curve(from: CGPoint(x: x(lane.lane), y: 0),
                                 to: CGPoint(x: x(row.lane), y: nodeY))
                context.stroke(path, with: .color(Theme.graphColor(lane.color)), lineWidth: lineWidth)
            }

            for lane in row.outgoing {
                let path = curve(from: CGPoint(x: x(row.lane), y: nodeY),
                                 to: CGPoint(x: x(lane.lane), y: size.height))
                context.stroke(path, with: .color(Theme.graphColor(lane.color)), lineWidth: lineWidth)
            }

            if isMerge {
                let rect = CGRect(x: x(row.lane) - nodeRadius, y: nodeY - nodeRadius, width: nodeRadius * 2, height: nodeRadius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(Theme.contentBackground))
                context.stroke(Path(ellipseIn: rect), with: .color(Theme.graphColor(row.color)), lineWidth: max(1, lineWidth + 0.2))
            } else {
                let rect = CGRect(x: x(row.lane) - nodeRadius, y: nodeY - nodeRadius, width: nodeRadius * 2, height: nodeRadius * 2)
                context.fill(Path(ellipseIn: rect), with: .color(Theme.graphColor(row.color)))
                context.stroke(Path(ellipseIn: rect), with: .color(Theme.graphColor(row.color)), lineWidth: max(0.8, lineWidth * 0.6))
            }
        }
        .frame(width: simplified ? Theme.laneWidth : max(laneWidth * CGFloat(max(laneCount, 1)), Theme.laneWidth), height: height)
    }
}

struct CommitRowView: View {
    var commit: Commit
    var row: GraphRow?
    var laneCount: Int
    var isSelected: Bool
    var isHighlighted: Bool
    var graphMaxWidth: CGFloat = 150
    var simplifiedGraph: Bool = false
    var linear: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if let row, !linear {
                GraphCell(row: row, isMerge: commit.isMerge, laneCount: laneCount, height: Theme.commitRowHeight, maxWidth: graphMaxWidth, simplified: simplifiedGraph)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(commit.subject.isEmpty ? "(no message)" : commit.subject)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                    ForEach(commit.refs.prefix(graphMaxWidth < 120 ? 0 : 2)) { ref in
                        RefBadge(ref: ref)
                            .frame(maxWidth: graphMaxWidth < 120 ? 64 : 110, alignment: .leading)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 5) {
                    Text(commit.author)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text("·")
                    Text(commit.relativeAuthorDate)
                    Text("·")
                    Text(commit.shortHash)
                        .font(Theme.monoSmall)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
    var graphMaxWidth: CGFloat = 150
    var simplifiedGraph: Bool = false
    var linear: Bool = false
    var showsFilterChip: Bool = true
    @ObservedObject var session: RepoSession
    @State private var hoveredHash: String?
    @State private var branchSheet: BranchSheetMode?
    @State private var showGraphHelp = false
    @State private var tagTarget: Commit?
    @State private var resetTarget: Commit?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.subtleBorder)
            if showGraphHelp {
                GraphLegend(onClose: { withAnimation(.easeInOut(duration: 0.12)) { showGraphHelp = false } })
                Divider().overlay(Theme.subtleBorder)
            }
            if session.displayCommits.isEmpty {
                if !session.hasLoaded {
                    VStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Loading history…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EmptyHint(icon: "clock", title: "No commits",
                              subtitle: "This repository has no commits yet.")
                }
            } else {
                ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(session.displayCommits.enumerated()), id: \.element.id) { index, commit in
                            CommitRowView(commit: commit,
                                          row: session.graph.rows[commit.hash],
                                          laneCount: session.graph.laneCount,
                                          isSelected: session.selection == .commit(commit.hash),
                                          isHighlighted: hoveredHash == commit.hash,
                                          graphMaxWidth: graphMaxWidth,
                                          simplifiedGraph: simplifiedGraph,
                                          linear: linear)
                                .onHover { hovering in
                                    hoveredHash = hovering ? commit.hash : (hoveredHash == commit.hash ? nil : hoveredHash)
                                }
                                .onTapGesture {
                                    Task { await session.select(commit: commit) }
                                }
                                .id(commit.hash)
                                .onAppear {
                                    if session.searchText.isEmpty,
                                       index >= session.commits.count - 30 {
                                        session.autoLoadMoreIfNeeded()
                                    }
                                }
                                .contextMenu { contextMenu(for: commit) }
                        }
                        if session.hasMore {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.mini)
                                Text("Loading more commits…")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                Button("Load now") { Task { await session.loadMore() } }
                                    .buttonStyle(.link)
                                    .font(.system(size: 10))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(10)
                            .onAppear { session.autoLoadMoreIfNeeded() }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                }
                .background(Theme.contentBackground)
                .softTopEdge()
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
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 14, height: 16)

            TextField("Filter commits", text: $session.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .frame(height: 16)

            if !session.searchText.isEmpty {
                Button {
                    session.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }

            if let ref = session.filterRef, showsFilterChip {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.branch").font(.system(size: 9))
                    Text(ref).font(.system(size: 10, weight: .medium)).lineLimit(1)
                    Button {
                        Task { await session.setFilterRef(nil) }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 8))
                    }
                    .buttonStyle(.plain)
                    .help("Clear branch filter")
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Theme.accent.opacity(0.10), in: Capsule())
            }

            Spacer(minLength: 4)

            if session.isLoading {
                ProgressView().controlSize(.mini).scaleEffect(0.7)
            }
            Button {
                showGraphHelp.toggle()
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("What do the lines mean?")
            .padding(.horizontal, 2)

            if !session.searchText.isEmpty || session.filterRef != nil {
                Text("\(session.displayCommits.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Theme.contentBackground)
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
