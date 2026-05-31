import SwiftUI

// MARK: - Node positions for the topology map
private struct NodeLayout {
    var device: NetworkDevice
    var position: CGPoint
    var level: Int        // 0=internet, 1=router, 2=devices
}

// MARK: - NetworkMapView
struct NetworkMapView: View {
    @EnvironmentObject var state: AppState
    @State private var selectedNode: NetworkDevice? = nil
    @State private var hoveredNode: NetworkDevice? = nil
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @GestureState private var magnifyBy: CGFloat = 1.0

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background
                Color(red: 0.06, green: 0.07, blue: 0.09)

                // Grid dots
                Canvas { ctx, size in
                    drawGrid(ctx: ctx, size: size)
                }
                .opacity(0.3)

                // Map content
                mapContent(in: geo.size)
                    .scaleEffect(scale * magnifyBy)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .updating($magnifyBy) { value, state, _ in state = value }
                            .onEnded { value in
                                scale = max(0.5, min(3.0, scale * value))
                            }
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in offset = value.translation }
                    )

                // Title bar
                VStack {
                    HStack {
                        Text(L10n.Map.title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                        legendView
                        Divider().frame(height: 16).opacity(0.3)
                        Button {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                scale = 1.0; offset = .zero
                            }
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .help(L10n.Map.resetView)
                        .accessibilityLabel(L10n.Map.resetView)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.08, green: 0.09, blue: 0.11).opacity(0.9))
                    Spacer()
                }
            }
        }
        .onChange(of: state.selectedDevice?.id) { _, _ in selectedNode = state.selectedDevice }
    }

    // MARK: - Map Content
    @ViewBuilder
    private func mapContent(in size: CGSize) -> some View {
        let nodes = computeLayout(in: size)
        let nodeMap = Dictionary(uniqueKeysWithValues: nodes.map { ($0.device.id, $0) })

        ZStack {
            // Draw edges first
            ForEach(nodes, id: \.device.id) { node in
                if let parentIP = node.device.parentIP,
                   let parentDevice = state.filteredDevices.first(where: { $0.ip == parentIP }),
                   let parentNode = nodeMap[parentDevice.id] {
                    EdgeLine(
                        from: parentNode.position,
                        to: node.position,
                        isAlert: node.device.status == .alert
                    )
                }
            }

            // Internet node (always at top)
            let internetPos = CGPoint(x: size.width / 2, y: 80)
            InternetNode(position: internetPos)

            // Edge from Internet to Router
            if let router = nodes.first(where: { $0.level == 1 }) {
                EdgeLine(from: internetPos, to: router.position, isAlert: false)
            }

            // Device nodes
            ForEach(nodes, id: \.device.id) { node in
                DeviceNode(
                    device: node.device,
                    position: node.position,
                    isSelected: selectedNode?.id == node.device.id,
                    isHovered: hoveredNode?.id == node.device.id
                )
                .opacity(node.device.scanState == .cached ? 0.55 : 1.0)
                .onTapGesture { toggleSelection(node.device) }
                .onHover { isHover in
                    hoveredNode = isHover ? node.device : nil
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(nodeAccessibilityLabel(node.device))
                .accessibilityHint(L10n.A11y.nodeHint)
                .accessibilityAddTraits(
                    selectedNode?.id == node.device.id ? [.isButton, .isSelected] : .isButton
                )
                .accessibilityAction { toggleSelection(node.device) }
            }

            // Empty state
            if state.filteredDevices.isEmpty && !state.scanStatus.isScanning {
                emptyStateOverlay(in: size)
            }

            // Scanning overlay
            if state.scanStatus.isScanning {
                scanningOverlay(in: size)
            }
        }
    }

    // MARK: - Layout computation
    private func computeLayout(in size: CGSize) -> [NodeLayout] {
        var layouts: [NodeLayout] = []
        let centerX = size.width / 2
        let routerY: CGFloat = 200

        // Level 1: Router/Gateway
        let routers = state.filteredDevices.filter { $0.effectiveType == .router }
        for (i, router) in routers.enumerated() {
            let x = centerX + CGFloat(i - routers.count / 2) * 120
            layouts.append(NodeLayout(device: router, position: CGPoint(x: x, y: routerY), level: 1))
        }

        // Level 2: Other devices
        let otherDevices = state.filteredDevices.filter { $0.effectiveType != .router }
        let rowCount  = max(1, Int(ceil(Double(otherDevices.count) / 5.0)))
        let perRow    = Int(ceil(Double(otherDevices.count) / Double(rowCount)))
        let startY    = routerY + 150

        for (idx, device) in otherDevices.enumerated() {
            let row  = idx / perRow
            let col  = idx % perRow
            let totalInRow = min(perRow, otherDevices.count - row * perRow)
            let startX = centerX - CGFloat(totalInRow - 1) * 110 / 2
            let x = startX + CGFloat(col) * 110
            let y = startY + CGFloat(row) * 130
            layouts.append(NodeLayout(device: device, position: CGPoint(x: x, y: y), level: 2))
        }

        return layouts
    }

    // MARK: - Selection & accessibilité
    private func toggleSelection(_ device: NetworkDevice) {
        withAnimation(.spring(response: 0.3)) {
            selectedNode = selectedNode?.id == device.id ? nil : device
            state.selectedDevice = selectedNode
        }
    }

    /// Libellé VoiceOver d'un nœud : « iPhone de Paul, 192.168.1.5, Sûr, 2 alertes »
    private func nodeAccessibilityLabel(_ device: NetworkDevice) -> String {
        var parts = [device.effectiveType.localizedName,
                     device.displayName,
                     device.ip,
                     device.status.localizedName]
        if device.alertCount > 0 { parts.append(L10n.A11y.alerts(device.alertCount)) }
        return parts.joined(separator: ", ")
    }

    // MARK: - Empty state
    private func emptyStateOverlay(in size: CGSize) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "network.slash")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.15))
            Text(L10n.Map.emptyTitle)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.25))
            Text(L10n.Map.emptySubtitle)
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.15))
        }
        .position(x: size.width / 2, y: size.height / 2)
    }

    // MARK: - Scanning overlay
    private func scanningOverlay(in size: CGSize) -> some View {
        VStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(0.8)
                .tint(.blue)
            Text(state.scanStatus.message)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.1, green: 0.11, blue: 0.14).opacity(0.9))
        )
        .position(x: size.width / 2, y: size.height - 80)
    }

    // MARK: - Legend
    private var legendView: some View {
        HStack(spacing: 16) {
            ForEach([
                (L10n.Map.legendSafe, Color(red: 0.2, green: 0.8, blue: 0.4)),
                (L10n.Map.legendUnknown, Color(red: 1.0, green: 0.6, blue: 0.0)),
                (L10n.Map.legendAlert, Color(red: 0.9, green: 0.2, blue: 0.2))
            ], id: \.0) { item in
                HStack(spacing: 5) {
                    Circle().fill(item.1).frame(width: 9, height: 9)
                    Text(item.0)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
    }

    // MARK: - Grid drawing
    private func drawGrid(ctx: GraphicsContext, size: CGSize) {
        let spacing: CGFloat = 30
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
        ctx.stroke(path, with: .color(Color.white.opacity(0.04)), lineWidth: 0.5)
    }
}

// MARK: - Edge Line
struct EdgeLine: View {
    let from: CGPoint
    let to: CGPoint
    let isAlert: Bool

    var body: some View {
        Path { path in
            path.move(to: from)
            // Curved line
            let midY = (from.y + to.y) / 2
            path.addCurve(
                to: to,
                control1: CGPoint(x: from.x, y: midY),
                control2: CGPoint(x: to.x, y: midY)
            )
        }
        .stroke(
            isAlert ? Color.red.opacity(0.7) : Color.white.opacity(0.12),
            style: StrokeStyle(
                lineWidth: isAlert ? 1.5 : 1.0,
                dash: isAlert ? [] : [4, 4]
            )
        )
    }
}

// MARK: - Internet Node
struct InternetNode: View {
    let position: CGPoint

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 62, height: 62)
                Circle()
                    .stroke(Color.blue.opacity(0.5), lineWidth: 1.5)
                    .frame(width: 62, height: 62)
                Image(systemName: "globe")
                    .font(.system(size: 26))
                    .foregroundColor(.blue)
            }
            Text(L10n.Map.internet)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
        }
        .position(position)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.A11y.internet)
    }
}

// MARK: - Device Node
struct DeviceNode: View {
    @ObservedObject var device: NetworkDevice
    let position: CGPoint
    let isSelected: Bool
    let isHovered: Bool

    private var nodeSize: CGFloat { isSelected ? 56 : (isHovered ? 52 : 48) }

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(device.status.color.opacity(isSelected ? 0.9 : 0.4), lineWidth: isSelected ? 2.5 : 1.5)
                    .frame(width: nodeSize, height: nodeSize)

                // Background
                Circle()
                    .fill(device.effectiveType.color.opacity(0.12))
                    .frame(width: nodeSize - 4, height: nodeSize - 4)

                // Icon
                Image(systemName: device.effectiveType.icon)
                    .font(.system(size: nodeSize * 0.36, weight: .medium))
                    .foregroundColor(device.effectiveType.color)

                // Alert badge
                if device.alertCount > 0 {
                    VStack {
                        HStack {
                            Spacer()
                            ZStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 14, height: 14)
                                Text("\(device.alertCount)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        Spacer()
                    }
                    .frame(width: nodeSize, height: nodeSize)
                }

                // Current device indicator
                if device.isCurrentDevice {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.blue)
                            Spacer()
                        }
                    }
                    .frame(width: nodeSize, height: nodeSize)
                    .offset(x: -2, y: 2)
                }
            }
            .shadow(color: device.status.color.opacity(isSelected ? 0.5 : 0.2), radius: isSelected ? 8 : 4)

            // Label
            VStack(spacing: 2) {
                Text(device.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .frame(maxWidth: 110)
                Text(device.shortIP)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
        .position(position)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

