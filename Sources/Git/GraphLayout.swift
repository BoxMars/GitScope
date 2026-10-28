import Foundation

struct GraphRow {
    var lane: Int
    var color: Int
    /// Vertical lines that run the full height of this row.
    var through: [(lane: Int, color: Int)] = []
    /// Lanes that curve into this commit from above (secondary parents / merges).
    var incoming: [(lane: Int, color: Int)] = []
    /// Lanes that leave this commit and curve to a lane below (merge parents).
    var outgoing: [(lane: Int, color: Int)] = []
    /// Own lane continues downwards (commit has a first parent).
    var continuesDown: Bool = false
}

struct GraphLayout {
    var rows: [String: GraphRow] = [:]
    var laneCount: Int = 1

    static let paletteCount = 10
    static let maxVisibleLanes = 8

    static func compute(commits: [Commit]) -> GraphLayout {
        var layout = GraphLayout()
        let loaded = Set(commits.map(\.hash))
        var lanes: [String?] = []
        var colors: [Int] = []
        var nextColor = 0

        func colorForNewLane() -> Int {
            defer { nextColor = (nextColor + 1) % paletteCount }
            return nextColor
        }

        func allocateLane() -> Int {
            if let free = lanes.firstIndex(where: { $0 == nil }) {
                return free
            }
            lanes.append(nil)
            colors.append(0)
            return lanes.count - 1
        }

        for commit in commits {
            var laneIndex = lanes.firstIndex(where: { $0 == commit.hash })
            if laneIndex == nil {
                let allocated = allocateLane()
                lanes[allocated] = commit.hash
                colors[allocated] = colorForNewLane()
                laneIndex = allocated
            }
            let lane = laneIndex!
            var row = GraphRow(lane: lane, color: colors[lane])

            // Lanes merging into this commit (other lanes that also expected it).
            for j in lanes.indices where j != lane && lanes[j] == commit.hash {
                row.incoming.append((j, colors[j]))
                lanes[j] = nil
            }

            // Pass-through lanes: were present before this row, still present after.
            let before = lanes
            for j in lanes.indices where j != lane && before[j] != nil && lanes[j] != nil {
                row.through.append((j, colors[j]))
            }

            if commit.parents.isEmpty {
                lanes[lane] = nil
            } else {
                let firstParent = commit.parents[0]
                if !loaded.contains(firstParent) {
                    lanes[lane] = nil
                } else if let existing = lanes.firstIndex(where: { $0 == firstParent }), existing != lane {
                    // The first parent is already tracked on another lane: curve into it
                    // and release this lane.
                    row.outgoing.append((existing, colors[existing]))
                    lanes[lane] = nil
                } else {
                    lanes[lane] = firstParent
                    row.continuesDown = true
                }
                for parent in commit.parents.dropFirst() where loaded.contains(parent) {
                    var parentLane = lanes.firstIndex(where: { $0 == parent })
                    if parentLane == nil {
                        let allocated = allocateLane()
                        lanes[allocated] = parent
                        colors[allocated] = colorForNewLane()
                        parentLane = allocated
                    }
                    row.outgoing.append((parentLane!, colors[parentLane!]))
                }
            }

            layout.rows[commit.hash] = row
            layout.laneCount = max(layout.laneCount, lanes.count)
        }
        return layout
    }
}
