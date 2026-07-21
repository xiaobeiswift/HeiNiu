/// 工作流节点画布、端口连线和节点卡片。

import SwiftUI

/// 右侧检查器标签。
enum WorkflowInspectorTab: String, CaseIterable, Identifiable {
    case configuration
    case usage
    case run

    var id: String { rawValue }

    var title: String {
        switch self {
        case .configuration: "配置"
        case .usage: "用法"
        case .run: "运行"
        }
    }
}

/// 用户选择的待连接输出端口。
struct WorkflowPendingPort: Hashable {
    var nodeID: UUID
    var portID: String
    var title: String
}

/// 节点拖动期间只存在于画布内的临时位置。
private struct WorkflowNodeDragPreview: Equatable {
    var nodeID: UUID
    var position: WorkflowPoint
}

/// 可缩放、可滚动的工作流画布。
struct WorkflowCanvasView: View {
    @Environment(SettingsStore.self) private var settings
    let workflow: WorkflowDefinition
    let activeRun: WorkflowRun?
    @Binding var selectedNodeID: UUID?
    @Binding var selectedConnectionID: UUID?
    @Binding var inspectorTab: WorkflowInspectorTab

    let onUpdateNode: (WorkflowNode) -> Void
    let onDeleteNode: (UUID) -> Void
    let onDeleteConnection: (UUID) -> Void
    let onConnect: (UUID, String, UUID, String) -> String?
    let onUpdateViewport: (WorkflowViewport) -> Void

    @State private var zoom: Double
    @State private var scrollPosition: ScrollPosition
    @State private var pendingPort: WorkflowPendingPort?
    @State private var connectionMessage: String?
    @State private var dragPreview: WorkflowNodeDragPreview?
    @State private var panOrigin: CGPoint?

    private let nodeWidth: CGFloat = 242

    init(
        workflow: WorkflowDefinition,
        activeRun: WorkflowRun?,
        selectedNodeID: Binding<UUID?>,
        selectedConnectionID: Binding<UUID?>,
        inspectorTab: Binding<WorkflowInspectorTab>,
        onUpdateNode: @escaping (WorkflowNode) -> Void,
        onDeleteNode: @escaping (UUID) -> Void,
        onDeleteConnection: @escaping (UUID) -> Void,
        onConnect: @escaping (UUID, String, UUID, String) -> String?,
        onUpdateViewport: @escaping (WorkflowViewport) -> Void
    ) {
        self.workflow = workflow
        self.activeRun = activeRun
        _selectedNodeID = selectedNodeID
        _selectedConnectionID = selectedConnectionID
        _inspectorTab = inspectorTab
        self.onUpdateNode = onUpdateNode
        self.onDeleteNode = onDeleteNode
        self.onDeleteConnection = onDeleteConnection
        self.onConnect = onConnect
        self.onUpdateViewport = onUpdateViewport
        _zoom = State(initialValue: min(2, max(0.35, workflow.viewport.zoom)))
        _scrollPosition = State(
            initialValue: ScrollPosition(
                point: CGPoint(
                    x: max(0, workflow.viewport.offset.x),
                    y: max(0, workflow.viewport.offset.y)
                )
            )
        )
    }

    private var worldWidth: CGFloat {
        max(2_000, CGFloat(workflow.nodes.map(\.position.x).max() ?? 0) + 700)
    }

    private var worldHeight: CGFloat {
        max(1_300, CGFloat(workflow.nodes.map(\.position.y).max() ?? 0) + 500)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    WorkflowGridBackground()
                        .frame(width: worldWidth, height: worldHeight)
                        .contentShape(Rectangle())
                        .highPriorityGesture(canvasPanGesture)
                        .onTapGesture {
                            selectedNodeID = nil
                            selectedConnectionID = nil
                            pendingPort = nil
                        }
                        .help("在空白处按住拖动，可向任意方向平移画布")

                    ForEach(workflow.connections) { connection in
                        connectionView(connection)
                    }

                    ForEach(workflow.nodes) { node in
                        let displayedNode = WorkflowValidator.effectiveNode(node, settings: settings)
                        let displayedPosition = position(for: node)
                        WorkflowNodeCard(
                            node: displayedNode,
                            width: nodeWidth,
                            zoom: zoom,
                            isSelected: selectedNodeID == node.id,
                            pendingPort: pendingPort,
                            run: activeRun?.nodeRun(id: node.id),
                            onSelect: {
                                selectedNodeID = node.id
                                selectedConnectionID = nil
                            },
                            onShowUsage: {
                                selectedNodeID = node.id
                                selectedConnectionID = nil
                                inspectorTab = .usage
                            },
                            onMoveChanged: { position in
                                var transaction = Transaction()
                                transaction.animation = nil
                                withTransaction(transaction) {
                                    dragPreview = WorkflowNodeDragPreview(nodeID: node.id, position: position)
                                }
                            },
                            onMoveEnded: { position in
                                var updated = node
                                updated.position = position
                                onUpdateNode(updated)
                                dragPreview = nil
                            },
                            onDelete: { onDeleteNode(node.id) },
                            onOutputPort: { port in
                                selectedNodeID = node.id
                                selectedConnectionID = nil
                                let next = WorkflowPendingPort(nodeID: node.id, portID: port.id, title: "\(node.displayTitle) · \(port.title)")
                                pendingPort = pendingPort == next ? nil : next
                                connectionMessage = nil
                            },
                            onInputPort: { port in
                                selectedNodeID = node.id
                                selectedConnectionID = nil
                                guard let source = pendingPort else { return }
                                connectionMessage = onConnect(source.nodeID, source.portID, node.id, port.id)
                                if connectionMessage == nil { pendingPort = nil }
                            }
                        )
                        .position(
                            x: CGFloat(displayedPosition.x) + nodeWidth / 2,
                            y: CGFloat(displayedPosition.y) + nodeHeight(node) / 2
                        )
                        .zIndex(dragPreview?.nodeID == node.id ? 2 : (selectedNodeID == node.id ? 1 : 0))
                    }
                }
                .frame(width: worldWidth, height: worldHeight, alignment: .topLeading)
                .scaleEffect(zoom, anchor: .topLeading)
                .frame(width: worldWidth * zoom, height: worldHeight * zoom, alignment: .topLeading)
            }
            .scrollPosition($scrollPosition)
            .scrollIndicators(.automatic)
            .background(AppTheme.bgBase)
            .onDeleteCommand(perform: deleteSelection)
            .onScrollPhaseChange { _, newPhase, context in
                guard newPhase == .idle, panOrigin == nil else { return }
                persistCanvasOffset(context.geometry.contentOffset)
            }

            canvasToolbar

            if let pendingPort {
                HStack(spacing: 7) {
                    Image(systemName: "cable.connector")
                    Text("已选择 \(pendingPort.title)，请点击目标输入端口")
                    Button { self.pendingPort = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                }
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().stroke(AppTheme.strokeStrong))
                .padding(14)
            } else if let connectionMessage {
                Text(connectionMessage)
                    .font(.caption)
                    .foregroundStyle(AppTheme.danger)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().stroke(AppTheme.danger.opacity(0.3)))
                    .padding(14)
            }
        }
        .onChange(of: workflow.id) { _, _ in
            zoom = min(2, max(0.35, workflow.viewport.zoom))
            let offset = CGPoint(
                x: max(0, workflow.viewport.offset.x),
                y: max(0, workflow.viewport.offset.y)
            )
            scrollPosition.scrollTo(point: offset)
            pendingPort = nil
            connectionMessage = nil
            dragPreview = nil
            panOrigin = nil
        }
    }

    private var canvasPanGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                if panOrigin == nil {
                    panOrigin = scrollPosition.point ?? CGPoint(
                        x: max(0, workflow.viewport.offset.x),
                        y: max(0, workflow.viewport.offset.y)
                    )
                    selectedNodeID = nil
                    selectedConnectionID = nil
                    pendingPort = nil
                }
                guard let origin = panOrigin else { return }
                scrollPosition.scrollTo(
                    point: CGPoint(
                        x: max(0, origin.x - value.translation.width),
                        y: max(0, origin.y - value.translation.height)
                    )
                )
            }
            .onEnded { value in
                guard let origin = panOrigin else { return }
                let offset = CGPoint(
                    x: max(0, origin.x - value.translation.width),
                    y: max(0, origin.y - value.translation.height)
                )
                scrollPosition.scrollTo(point: offset)
                panOrigin = nil
                persistCanvasOffset(offset)
            }
    }

    private var canvasToolbar: some View {
        HStack(spacing: 4) {
            Button {
                zoom = max(0.35, zoom - 0.1)
                persistZoom()
            } label: { Image(systemName: "minus.magnifyingglass") }
                .help("缩小画布")
            Text("\(Int(zoom * 100))%")
                .font(.caption.monospacedDigit())
                .frame(width: 46)
            Button {
                zoom = min(2, zoom + 0.1)
                persistZoom()
            } label: { Image(systemName: "plus.magnifyingglass") }
                .help("放大画布")
            Divider().frame(height: 16)
            Button {
                zoom = 0.75
                persistZoom()
            } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                .help("适合画布")
        }
        .buttonStyle(.borderless)
        .padding(7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(AppTheme.stroke))
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private func connectionView(_ connection: WorkflowConnection) -> some View {
        if let source = workflow.nodes.first(where: { $0.id == connection.sourceNodeID }),
           let target = workflow.nodes.first(where: { $0.id == connection.targetNodeID }),
           let sourceIndex = outputPorts(source).firstIndex(where: { $0.id == connection.sourcePortID }),
           let targetIndex = inputPorts(target).firstIndex(where: { $0.id == connection.targetPortID }) {
            let sourcePosition = position(for: source)
            let targetPosition = position(for: target)
            let start = CGPoint(
                x: CGFloat(sourcePosition.x) + nodeWidth,
                y: CGFloat(sourcePosition.y) + portBaseY + CGFloat(sourceIndex) * portRowHeight
            )
            let end = CGPoint(
                x: CGFloat(targetPosition.x),
                y: CGFloat(targetPosition.y) + portBaseY + CGFloat(targetIndex) * portRowHeight
            )
            let path = connectionPath(from: start, to: end)
            let selected = selectedConnectionID == connection.id
            ZStack {
                path.stroke(
                    selected ? AppTheme.accent : AppTheme.textTertiary.opacity(0.48),
                    style: StrokeStyle(lineWidth: selected ? 3 : 2, lineCap: .round)
                )
                path.stroke(Color.primary.opacity(0.001), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .contentShape(path)
                    .onTapGesture {
                        selectedConnectionID = connection.id
                        selectedNodeID = nil
                        pendingPort = nil
                    }
            }
        }
    }

    private func connectionPath(from start: CGPoint, to end: CGPoint) -> Path {
        var path = Path()
        path.move(to: start)
        let distance = max(70, abs(end.x - start.x) * 0.45)
        path.addCurve(
            to: end,
            control1: CGPoint(x: start.x + distance, y: start.y),
            control2: CGPoint(x: end.x - distance, y: end.y)
        )
        return path
    }

    private var portBaseY: CGFloat { 102 }
    private var portRowHeight: CGFloat { 27 }

    private func position(for node: WorkflowNode) -> WorkflowPoint {
        guard dragPreview?.nodeID == node.id else { return node.position }
        return dragPreview?.position ?? node.position
    }

    private func inputPorts(_ node: WorkflowNode) -> [WorkflowPortDescriptor] {
        let effective = WorkflowValidator.effectiveNode(node, settings: settings)
        return effective.descriptor.ports(for: effective).filter { $0.direction == .input }
    }

    private func outputPorts(_ node: WorkflowNode) -> [WorkflowPortDescriptor] {
        let effective = WorkflowValidator.effectiveNode(node, settings: settings)
        return effective.descriptor.ports(for: effective).filter { $0.direction == .output }
    }

    private func nodeHeight(_ node: WorkflowNode) -> CGFloat {
        let count = max(inputPorts(node).count, outputPorts(node).count)
        return 116 + CGFloat(max(1, count)) * portRowHeight
    }

    private func deleteSelection() {
        if let selectedNodeID {
            onDeleteNode(selectedNodeID)
            self.selectedNodeID = nil
        } else if let selectedConnectionID {
            onDeleteConnection(selectedConnectionID)
            self.selectedConnectionID = nil
        }
    }

    private func persistZoom() {
        var viewport = workflow.viewport
        viewport.zoom = zoom
        if let point = scrollPosition.point {
            viewport.offset = WorkflowPoint(x: Double(max(0, point.x)), y: Double(max(0, point.y)))
        }
        onUpdateViewport(viewport)
    }

    private func persistCanvasOffset(_ point: CGPoint) {
        let offset = WorkflowPoint(
            x: Double(max(0, point.x)),
            y: Double(max(0, point.y))
        )
        guard workflow.viewport.offset != offset || workflow.viewport.zoom != zoom else { return }
        var viewport = workflow.viewport
        viewport.offset = offset
        viewport.zoom = zoom
        onUpdateViewport(viewport)
    }
}

/// 节点卡片。
private struct WorkflowNodeCard: View {
    let node: WorkflowNode
    let width: CGFloat
    let zoom: Double
    let isSelected: Bool
    let pendingPort: WorkflowPendingPort?
    let run: WorkflowNodeRun?
    let onSelect: () -> Void
    let onShowUsage: () -> Void
    let onMoveChanged: (WorkflowPoint) -> Void
    let onMoveEnded: (WorkflowPoint) -> Void
    let onDelete: () -> Void
    let onOutputPort: (WorkflowPortDescriptor) -> Void
    let onInputPort: (WorkflowPortDescriptor) -> Void

    @State private var isDragging = false

    private var inputs: [WorkflowPortDescriptor] {
        node.descriptor.ports(for: node).filter { $0.direction == .input }
    }

    private var outputs: [WorkflowPortDescriptor] {
        node.descriptor.ports(for: node).filter { $0.direction == .output }
    }

    private var rowCount: Int { max(1, max(inputs.count, outputs.count)) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(node.descriptor.tint.color.opacity(0.16))
                        .frame(width: 30, height: 30)
                    Image(systemName: node.descriptor.systemImage)
                        .foregroundStyle(node.descriptor.tint.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(node.displayTitle).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if let run {
                        Text(run.status.title)
                            .font(.caption2)
                            .foregroundStyle(run.status.color)
                    }
                }
                Spacer(minLength: 2)
                Button(action: onShowUsage) {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.plain)
                .help("查看“\(node.descriptor.title)”完整用法")
            }
            .padding(.horizontal, 11)
            .padding(.top, 9)

            Text(node.descriptor.summary)
                .font(.caption2)
                .foregroundStyle(AppTheme.textTertiary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.top, 6)
                .padding(.bottom, 8)

            Divider().opacity(0.45)

            VStack(spacing: 0) {
                ForEach(0..<rowCount, id: \.self) { index in
                    HStack(spacing: 5) {
                        if inputs.indices.contains(index) {
                            portButton(inputs[index], isInput: true)
                            Text(inputs[index].title)
                                .font(.caption2)
                                .lineLimit(1)
                        } else {
                            Spacer().frame(width: 8)
                        }
                        Spacer(minLength: 5)
                        if outputs.indices.contains(index) {
                            Text(outputs[index].title)
                                .font(.caption2)
                                .lineLimit(1)
                            portButton(outputs[index], isInput: false)
                        } else {
                            Spacer().frame(width: 8)
                        }
                    }
                    .frame(height: 27)
                    .padding(.horizontal, 7)
                }
            }
            .padding(.vertical, 5)

            if let progress = run?.progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(node.descriptor.tint.color)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }
        }
        .frame(width: width)
        .background(AppTheme.bgCard, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(isSelected ? 0.16 : 0.08), radius: isSelected ? 9 : 4, y: 2)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture(perform: onSelect)
        .highPriorityGesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        onSelect()
                    }
                    onMoveChanged(dragPosition(for: value.translation))
                }
                .onEnded { value in
                    onMoveEnded(dragPosition(for: value.translation))
                    isDragging = false
                }
        )
        .contextMenu {
            Button("查看用法", action: onShowUsage)
            Divider()
            Button("删除节点", role: .destructive, action: onDelete)
        }
    }

    private var borderColor: Color {
        if isSelected { return AppTheme.accent }
        if let run { return run.status.color.opacity(0.65) }
        return AppTheme.strokeStrong
    }

    private func dragPosition(for translation: CGSize) -> WorkflowPoint {
        WorkflowPoint(
            x: max(0, node.position.x + Double(translation.width) / zoom),
            y: max(0, node.position.y + Double(translation.height) / zoom)
        )
    }

    private func portButton(_ port: WorkflowPortDescriptor, isInput: Bool) -> some View {
        let pending = pendingPort?.nodeID == node.id && pendingPort?.portID == port.id
        return Button {
            if isInput { onInputPort(port) } else { onOutputPort(port) }
        } label: {
            Circle()
                .fill(pending ? AppTheme.accent : port.valueType.color)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("\(port.valueType.title) · \(port.isRequired ? "必填" : "可选")\n\(port.help)")
    }
}

/// 无限画布风格网格。
private struct WorkflowGridBackground: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 24
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            context.stroke(path, with: .color(Color.primary.opacity(0.045)), lineWidth: 0.7)
        }
        .background(AppTheme.bgBase)
    }
}

private extension WorkflowNodeTint {
    var color: Color {
        switch self {
        case .amber: AppTheme.accent
        case .blue: .blue
        case .purple: .purple
        case .green: AppTheme.success
        case .pink: .pink
        case .cyan: .cyan
        case .orange: .orange
        case .indigo: .indigo
        case .gray: AppTheme.textSecondary
        }
    }
}

private extension WorkflowValueType {
    var color: Color {
        switch self {
        case .text: .blue
        case .knowledgeCollection: AppTheme.success
        case .image: .pink
        case .video: .cyan
        case .audio: .orange
        case .folder: .green
        case .any: AppTheme.accent
        }
    }
}

extension WorkflowNodeRunStatus {
    var color: Color {
        switch self {
        case .pending, .skipped: AppTheme.textTertiary
        case .running: AppTheme.accent
        case .succeeded: AppTheme.success
        case .warning: .orange
        case .failed: AppTheme.danger
        case .cancelled: AppTheme.textSecondary
        }
    }
}
