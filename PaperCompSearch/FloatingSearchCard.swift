import SwiftUI

/// Floating chrome for circle search. The host overlay is full-size; only this card receives touches.
public struct FloatingSearchCard<Content: View>: View {
    private let anchor: CGRect
    private let title: String
    private let onClose: () -> Void
    private let startMinimized: Bool
    private let content: Content

    @AppStorage("searchCardPos.portrait") private var portraitPosition = ""
    @AppStorage("searchCardPos.landscape") private var landscapePosition = ""
    @AppStorage("searchCardSize.portrait") private var portraitSize = ""
    @AppStorage("searchCardSize.landscape") private var landscapeSize = ""
    @AppStorage(SearchCardStyle.storageKey) private var styleRaw = SearchCardStyle.defaultValue.rawValue
    @State private var cardOrigin: CGPoint?
    @State private var cardSize: CGSize?
    @State private var minimized = false
    @State private var expanded = false
    @State private var dragTranslation: CGSize = .zero
    @State private var resizeTranslation: CGSize = .zero
    @State private var showSettings = false
    @State private var busy = false

    public init(anchor: CGRect, title: String, onClose: @escaping () -> Void,
                startMinimized: Bool = false, @ViewBuilder content: () -> Content) {
        self.anchor = anchor
        self.title = title
        self.onClose = onClose
        self.startMinimized = startMinimized
        self.content = content()
    }

    private var palette: SearchCardPalette { SearchCardPalette.resolve(styleRaw: styleRaw) }

    public var body: some View {
        GeometryReader { proxy in
            let safe = proxy.safeAreaInsets
            let bounds = SearchCardPlacement.safeBounds(
                size: proxy.size,
                top: safe.top,
                leading: safe.leading,
                bottom: safe.bottom,
                trailing: safe.trailing
            )
            let landscape = proxy.size.width > proxy.size.height
            let baseSize = resolvedSize(bounds: bounds, landscape: landscape)
            let displaySize = CGSize(
                width: baseSize.width + resizeTranslation.width,
                height: baseSize.height + resizeTranslation.height
            )
            let clampedDisplay = expanded
                ? SearchCardPlacement.expandedSize(in: bounds)
                : SearchCardPlacement.clampSize(displaySize, in: bounds)
            let baseOrigin = expanded
                ? SearchCardPlacement.expandedOrigin(size: clampedDisplay, in: bounds)
                : (cardOrigin ?? rememberedOrigin(bounds: bounds, cardSize: clampedDisplay))
            let displayOrigin = expanded
                ? baseOrigin
                : CGPoint(x: baseOrigin.x + dragTranslation.width, y: baseOrigin.y + dragTranslation.height)

            ZStack(alignment: .topLeading) {
                if minimized {
                    minimizedBubble(at: displayOrigin, bounds: bounds, landscape: landscape)
                } else {
                    expandedCard(bounds: bounds, origin: displayOrigin, cardSize: clampedDisplay,
                                 landscape: landscape, baseOrigin: baseOrigin, baseSize: baseSize)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .environment(\.searchCardPalette, palette)
            .environment(\.searchCardWidth, clampedDisplay.width)
            .onAppear {
                if startMinimized { minimized = true }
                if cardSize == nil {
                    cardSize = rememberedSize(bounds: bounds, landscape: landscape)
                }
                if cardOrigin == nil {
                    let size = cardSize ?? SearchCardPlacement.defaultSize(in: bounds)
                    cardOrigin = SearchCardPlacement.initialOrigin(
                        anchor: anchor,
                        cardSize: size,
                        maxHeight: size.height,
                        bounds: bounds,
                        remembered: rememberedPoint(bounds: bounds)
                    )
                }
            }
            .onChange(of: anchor) { _, _ in
                let size = resolvedSize(bounds: bounds, landscape: landscape)
                cardOrigin = SearchCardPlacement.initialOrigin(
                    anchor: anchor,
                    cardSize: size,
                    maxHeight: size.height,
                    bounds: bounds,
                    remembered: rememberedPoint(bounds: bounds)
                )
            }
            .onPreferenceChange(SearchCardBusyKey.self) { busy = $0 }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private func rememberedPoint(bounds: CGRect) -> CGPoint? {
        let stored = bounds.width > bounds.height ? landscapePosition : portraitPosition
        guard !stored.isEmpty else { return nil }
        return SearchCardPlacement.decode(stored, in: bounds)
    }

    private func rememberedSize(bounds: CGRect, landscape: Bool) -> CGSize {
        let stored = landscape ? landscapeSize : portraitSize
        if let decoded = SearchCardPlacement.decodeSize(stored) {
            return SearchCardPlacement.clampSize(decoded, in: bounds)
        }
        return SearchCardPlacement.defaultSize(in: bounds)
    }

    private func resolvedSize(bounds: CGRect, landscape: Bool) -> CGSize {
        if expanded { return SearchCardPlacement.expandedSize(in: bounds) }
        return SearchCardPlacement.clampSize(cardSize ?? rememberedSize(bounds: bounds, landscape: landscape), in: bounds)
    }

    private func rememberedOrigin(bounds: CGRect, cardSize: CGSize) -> CGPoint {
        SearchCardPlacement.initialOrigin(
            anchor: anchor,
            cardSize: cardSize,
            maxHeight: cardSize.height,
            bounds: bounds,
            remembered: rememberedPoint(bounds: bounds)
        )
    }

    private func persistOrigin(_ point: CGPoint, bounds: CGRect, landscape: Bool) {
        let encoded = SearchCardPlacement.encode(point, in: bounds)
        if landscape { landscapePosition = encoded } else { portraitPosition = encoded }
    }

    private func persistSize(_ size: CGSize, landscape: Bool) {
        let encoded = SearchCardPlacement.encodeSize(size)
        if landscape { landscapeSize = encoded } else { portraitSize = encoded }
    }

    @ViewBuilder
    private func expandedCard(bounds: CGRect, origin: CGPoint, cardSize: CGSize,
                              landscape: Bool, baseOrigin: CGPoint, baseSize: CGSize) -> some View {
        VStack(spacing: 0) {
            cardChromeHeader(landscape: landscape, baseOrigin: baseOrigin, bounds: bounds, cardSize: cardSize)
            Rectangle().fill(palette.deep).frame(height: 0.5)
            content
                .searchCardBusy(busy)
                .frame(width: cardSize.width, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: cardSize.width, height: cardSize.height, alignment: .top)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            if palette.showsAccentBorder {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.accent, lineWidth: 1)
            }
        }
        .shadow(color: Theme.ink.opacity(palette.isDark ? 0.28 : 0.22), radius: 24, y: 8)
        .overlay(alignment: .bottomTrailing) {
            if !expanded { resizeHandle(bounds: bounds, landscape: landscape, baseSize: baseSize) }
        }
        .contentShape(.rect(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search.card")
        .background { SearchCardHitAnchor() }
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: SearchCardFrameKey.self, value: geo.frame(in: .global))
            }
        }
        .padding(.leading, origin.x)
        .padding(.top, origin.y)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(palette.ink)
    }

    @ViewBuilder
    private func minimizedBubble(at origin: CGPoint, bounds: CGRect, landscape: Bool) -> some View {
        let size = SearchCardPlacement.bubbleSize
        Button {
            withAnimation(.spring(duration: 0.35)) { minimized = false }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                if busy {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 10, height: 10)
                        .offset(x: 4, y: -4)
                        .opacity(busy ? 1 : 0)
                        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: busy)
                }
            }
            .frame(width: size, height: size)
            .background(palette.surface, in: .circle)
            .shadow(color: Theme.ink.opacity(0.22), radius: 16, y: 6)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(cardDrag(bounds: bounds, cardSize: CGSize(width: size, height: size),
                                      landscape: landscape, base: origin))
        .background { SearchCardHitAnchor() }
        .padding(.leading, origin.x)
        .padding(.top, origin.y)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func cardChromeHeader(landscape: Bool, baseOrigin: CGPoint, bounds: CGRect, cardSize: CGSize) -> some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(palette.deep)
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .contentShape(Rectangle())
                .gesture(cardDrag(bounds: bounds, cardSize: cardSize, landscape: landscape, base: baseOrigin))
                .accessibilityLabel("Drag search card")
            HStack(spacing: 10) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button {
                    withAnimation(.spring(duration: 0.35)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.inkSoft)
                .accessibilityLabel(expanded ? "Collapse to card" : "Expand to side sheet")
                .accessibilityIdentifier("search.card.expand")
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.inkSoft)
                .accessibilityLabel("Settings")
                Button { withAnimation(.spring(duration: 0.35)) { minimized = true } } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.inkSoft)
                .accessibilityLabel("Minimize")
                .accessibilityIdentifier("search.card.minimize")
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.inkSoft)
                .accessibilityLabel("Close")
                .accessibilityAddTraits(.isButton)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(palette.surface)
    }

    private func resizeHandle(bounds: CGRect, landscape: Bool, baseSize: CGSize) -> some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(palette.inkSoft)
            .rotationEffect(.degrees(90))
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { resizeTranslation = $0.translation }
                    .onEnded { value in
                        let next = SearchCardPlacement.clampSize(
                            CGSize(width: baseSize.width + value.translation.width,
                                   height: baseSize.height + value.translation.height),
                            in: bounds
                        )
                        cardSize = next
                        persistSize(next, landscape: landscape)
                        resizeTranslation = .zero
                    }
            )
            .padding(6)
            .accessibilityLabel("Resize search card")
            .accessibilityIdentifier("search.card.resize")
    }

    private func cardDrag(bounds: CGRect, cardSize: CGSize, landscape: Bool, base: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { dragTranslation = $0.translation }
            .onEnded { value in
                let next = SearchCardPlacement.clamp(
                    CGPoint(x: base.x + value.translation.width, y: base.y + value.translation.height),
                    size: cardSize,
                    in: bounds
                )
                cardOrigin = next
                persistOrigin(next, bounds: bounds, landscape: landscape)
                dragTranslation = .zero
            }
    }
}

public struct SearchCardFrameKey: PreferenceKey {
    public static let defaultValue: CGRect = .zero
    public static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next.width > 1 { value = next }
    }
}

public struct SearchCardBusyKey: PreferenceKey {
    public static let defaultValue = false
    public static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

public extension View {
    func searchCardBusy(_ busy: Bool) -> some View {
        preference(key: SearchCardBusyKey.self, value: busy)
    }
}
