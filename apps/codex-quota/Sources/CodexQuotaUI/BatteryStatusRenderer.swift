import AppKit

public struct StatusPresentation {
    public let image: NSImage
    public let batteryImage: NSImage
    public let accessibilityLabel: String

    public init(
        image: NSImage,
        batteryImage: NSImage,
        accessibilityLabel: String
    ) {
        self.image = image
        self.batteryImage = batteryImage
        self.accessibilityLabel = accessibilityLabel
    }
}

public struct BatteryStatusRenderer {
    public init() {}

    public func presentation(
        style: BatteryStyle,
        remainingPercent: Int?,
        showsCodexLabel: Bool
    ) -> StatusPresentation {
        let presentation = presentation(
            style: style,
            remainingPercent: remainingPercent,
            identityMode: showsCodexLabel ? .text : .hidden,
            compactReset: nil
        )
        let percent = remainingPercent.map { min(max($0, 0), 100) }
        return StatusPresentation(
            image: presentation.image,
            batteryImage: presentation.batteryImage,
            accessibilityLabel: baseAccessibilityLabel(percent: percent)
        )
    }

    public func presentation(
        style: BatteryStyle,
        remainingPercent: Int?,
        identityMode: StatusIdentityMode,
        compactReset: String?
    ) -> StatusPresentation {
        let percent = remainingPercent.map { min(max($0, 0), 100) }
        let batteryImage: NSImage
        switch style {
        case .native:
            batteryImage = nativeImage(percent: percent)
        case .embedded:
            batteryImage = embeddedImage(percent: percent)
        case .segmented:
            batteryImage = segmentedImage(percent: percent)
        }
        batteryImage.isTemplate = true

        let image = statusImage(
            style: style,
            percent: percent,
            identityMode: identityMode,
            compactReset: compactReset,
            batteryImage: batteryImage
        )
        var accessibilityLabel = baseAccessibilityLabel(percent: percent)
        if let compactReset {
            accessibilityLabel += "，下次重置 \(compactReset)"
        }
        switch identityMode {
        case .text:
            accessibilityLabel += "，显示 Codex 文字"
        case .logo:
            accessibilityLabel += "，显示 OpenAI Logo"
        case .hidden:
            accessibilityLabel += "，不显示标识"
        }

        return StatusPresentation(
            image: image,
            batteryImage: batteryImage,
            accessibilityLabel: accessibilityLabel
        )
    }

    private func baseAccessibilityLabel(percent: Int?) -> String {
        percent.map { "Codex 剩余额度 \($0)%" } ?? "Codex 剩余额度未知"
    }

    private func statusImage(
        style: BatteryStyle,
        percent: Int?,
        identityMode: StatusIdentityMode,
        compactReset: String?,
        batteryImage: NSImage
    ) -> NSImage {
        let height: CGFloat = 18
        let horizontalMargin: CGFloat = 1
        let gap: CGFloat = 4
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuBarFont(ofSize: 0),
            .foregroundColor: NSColor.black.withAlphaComponent(0.9)
        ]
        let label = NSAttributedString(string: "Codex", attributes: attributes)
        let percentage = NSAttributedString(
            string: percent.map { "\($0)%" } ?? "--%",
            attributes: attributes
        )
        let suffix = compactReset.map {
            NSAttributedString(string: $0, attributes: attributes)
        }
        let logoImage = identityMode == .logo ? OpenAILogoRenderer.image() : nil
        let labelWidth = ceil(label.size().width)
        let percentageWidth = ceil(percentage.size().width)
        let suffixWidth = suffix.map { ceil($0.size().width) } ?? 0
        let drawsPercentage = style != .embedded

        var width = horizontalMargin * 2 + batteryImage.size.width
        switch identityMode {
        case .text:
            width += labelWidth + gap
        case .logo:
            width += 17 + gap
        case .hidden:
            break
        }
        if drawsPercentage {
            width += gap + percentageWidth
        }
        if suffix != nil {
            width += gap + suffixWidth
        }

        let composed = image(size: NSSize(width: width, height: height)) { _ in
            var x = horizontalMargin
            switch identityMode {
            case .text:
                label.draw(at: NSPoint(
                    x: x,
                    y: floor((height - label.size().height) / 2)
                ))
                x += labelWidth + gap
            case .logo:
                logoImage?.draw(
                    at: NSPoint(x: x, y: floor((height - 17) / 2)),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1
                )
                x += 17 + gap
            case .hidden:
                break
            }

            batteryImage.draw(
                at: NSPoint(
                    x: x,
                    y: floor((height - batteryImage.size.height) / 2)
                ),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
            x += batteryImage.size.width

            if drawsPercentage {
                x += gap
                percentage.draw(at: NSPoint(
                    x: x,
                    y: floor((height - percentage.size().height) / 2)
                ))
                x += percentageWidth
            }

            if let suffix {
                x += gap
                suffix.draw(at: NSPoint(
                    x: x,
                    y: floor((height - suffix.size().height) / 2)
                ))
            }
        }
        composed.isTemplate = true
        return composed
    }

    private func nativeImage(percent: Int?) -> NSImage {
        image(size: NSSize(width: 36, height: 16)) { _ in
            drawBatteryOutline(body: NSRect(x: 1.75, y: 1.75, width: 29.5, height: 12.5))
            drawTerminal(NSRect(x: 32.75, y: 5, width: 2.25, height: 6))

            guard let percent, percent > 0 else {
                return
            }
            let interior = NSRect(x: 3.5, y: 3.5, width: 26.5, height: 9)
            let fill = NSRect(
                x: interior.minX,
                y: interior.minY,
                width: interior.width * CGFloat(percent) / 100,
                height: interior.height
            )
            NSColor.black.withAlphaComponent(0.82).setFill()
            NSBezierPath(roundedRect: fill, xRadius: 1.5, yRadius: 1.5).fill()
        }
    }

    private func embeddedImage(percent: Int?) -> NSImage {
        image(size: NSSize(width: 34, height: 18)) { _ in
            let badge = NSBezierPath(
                roundedRect: NSRect(x: 2, y: 2, width: 30, height: 14),
                xRadius: 4,
                yRadius: 4
            )
            NSColor.black.withAlphaComponent(0.16).setFill()
            badge.fill()
            NSColor.black.withAlphaComponent(0.78).setStroke()
            badge.lineWidth = 1.5
            badge.stroke()

            let value = percent.map(String.init) ?? "--"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
                .foregroundColor: NSColor.black.withAlphaComponent(0.9)
            ]
            let attributedValue = NSAttributedString(string: value, attributes: attributes)
            let valueSize = attributedValue.size()
            attributedValue.draw(at: NSPoint(
                x: 17 - valueSize.width / 2,
                y: 9 - valueSize.height / 2
            ))
        }
    }

    private func segmentedImage(percent: Int?) -> NSImage {
        image(size: NSSize(width: 40, height: 16)) { _ in
            drawBatteryOutline(body: NSRect(x: 1.75, y: 1.75, width: 32.5, height: 12.5))
            drawTerminal(NSRect(x: 35.75, y: 5, width: 2.25, height: 6))

            let filledCount: Int
            if let percent, percent > 0 {
                filledCount = (percent + 19) / 20
            } else {
                filledCount = 0
            }

            let segmentWidth: CGFloat = 5
            for index in 0..<5 {
                let rect = NSRect(
                    x: 3.5 + CGFloat(index) * 6,
                    y: 3.5,
                    width: segmentWidth,
                    height: 9
                )
                let alpha: CGFloat = index < filledCount ? 0.84 : 0.14
                NSColor.black.withAlphaComponent(alpha).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1).fill()
            }
        }
    }

    private func image(
        size: NSSize,
        drawingHandler: @escaping (NSRect) -> Void
    ) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            drawingHandler(rect)
            return true
        }
    }

    private func drawBatteryOutline(body: NSRect) {
        let path = NSBezierPath(roundedRect: body, xRadius: 3, yRadius: 3)
        path.lineWidth = 1.5
        NSColor.black.withAlphaComponent(0.78).setStroke()
        path.stroke()
    }

    private func drawTerminal(_ rect: NSRect) {
        NSColor.black.withAlphaComponent(0.78).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 1.25, yRadius: 1.25).fill()
    }
}
