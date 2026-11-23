import AppKit

/// Desenha o rótulo da barra de status:
/// [ícone RAM] X.X GB   [ícone CPU] XX%
enum MenuBarIcon {
    struct Item {
        let symbolName: String
        let text: String
        let minTextSample: String
        let percent: Double
        let warnThreshold: Double
        let criticalThreshold: Double
    }

    static func image(
        ramText: String,
        ramPercent: Double,
        cpuText: String,
        cpuPercent: Double,
        monochrome: Bool = false
    ) -> NSImage {
        let items = [
            Item(
                symbolName: "memorychip",
                text: ramText,
                minTextSample: "0.0 GB",
                percent: ramPercent,
                warnThreshold: 75,
                criticalThreshold: 90
            ),
            Item(
                symbolName: "cpu",
                text: cpuText,
                minTextSample: "99%",
                percent: cpuPercent,
                warnThreshold: 70,
                criticalThreshold: 90
            )
        ]

        let height: CGFloat = 18
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        let iconSize: CGFloat = 11.5
        let iconGap: CGFloat = 3.5

        if monochrome {
            return renderMonochrome(
                items: items,
                height: height,
                font: font,
                iconSize: iconSize,
                iconGap: iconGap
            )
        } else {
            return renderBadges(
                items: items,
                height: height,
                font: font,
                iconSize: iconSize,
                iconGap: iconGap
            )
        }
    }

    // MARK: - Estilo Badges (harmoniza com outros monitores da barra de status)

    private static func renderBadges(
        items: [Item],
        height: CGFloat,
        font: NSFont,
        iconSize: CGFloat,
        iconGap: CGFloat
    ) -> NSImage {
        let padX: CGFloat = 5
        let itemGap: CGFloat = 4
        let pillH: CGFloat = 16

        let textSizes = items.map { ($0.text as NSString).size(withAttributes: [.font: font]) }
        let minTextWidths = items.map { ($0.minTextSample as NSString).size(withAttributes: [.font: font]).width }
        let slotWidths = zip(textSizes, minTextWidths).map { max($0.width, $1) }
        let pillWidths = slotWidths.map { padX + iconSize + iconGap + $0 + padX }
        let totalWidth = pillWidths.reduce(0, +) + itemGap * CGFloat(max(items.count - 1, 0))

        let img = NSImage(size: NSSize(width: ceil(totalWidth), height: height), flipped: true) { _ in
            var x: CGFloat = 0

            for (i, item) in items.enumerated() {
                let pillW = pillWidths[i]
                let pillRect = NSRect(x: x, y: (height - pillH) / 2, width: pillW, height: pillH)
                let path = NSBezierPath(roundedRect: pillRect, xRadius: 4, yRadius: 4)

                let bgColor: NSColor
                if item.percent >= item.criticalThreshold {
                    bgColor = .systemRed
                } else if item.percent >= item.warnThreshold {
                    bgColor = .systemOrange
                } else {
                    bgColor = NSColor(white: 0.38, alpha: 1)
                }

                bgColor.setFill()
                path.fill()

                // Ícone SF Symbol branco à esquerda do valor
                drawSymbol(
                    named: item.symbolName,
                    color: .white,
                    in: NSRect(
                        x: pillRect.minX + padX,
                        y: pillRect.minY + (pillH - iconSize) / 2,
                        width: iconSize,
                        height: iconSize
                    )
                )

                // Valor alinhado à direita dentro da largura estável para evitar tremulação
                let tSize = textSizes[i]
                let textSlotX = pillRect.minX + padX + iconSize + iconGap
                let textX = textSlotX + (slotWidths[i] - tSize.width)
                let textY = pillRect.minY + (pillH - tSize.height) / 2

                (item.text as NSString).draw(
                    at: CGPoint(x: textX, y: textY),
                    withAttributes: [.font: font, .foregroundColor: NSColor.white]
                )

                x = pillRect.maxX + itemGap
            }
            return true
        }
        img.isTemplate = false
        return img
    }

    // MARK: - Estilo Monocromático Nativo (adapta automaticamente a modo claro/escuro)

    private static func renderMonochrome(
        items: [Item],
        height: CGFloat,
        font: NSFont,
        iconSize: CGFloat,
        iconGap: CGFloat
    ) -> NSImage {
        let itemGap: CGFloat = 8
        let textSizes = items.map { ($0.text as NSString).size(withAttributes: [.font: font]) }
        let minTextWidths = items.map { ($0.minTextSample as NSString).size(withAttributes: [.font: font]).width }
        let slotWidths = zip(textSizes, minTextWidths).map { max($0.width, $1) }
        let itemWidths = slotWidths.map { iconSize + iconGap + $0 }
        let totalWidth = itemWidths.reduce(0, +) + itemGap * CGFloat(max(items.count - 1, 0))

        let img = NSImage(size: NSSize(width: ceil(totalWidth), height: height), flipped: true) { _ in
            var x: CGFloat = 0

            for (i, item) in items.enumerated() {
                drawSymbol(
                    named: item.symbolName,
                    color: .black,
                    in: NSRect(
                        x: x,
                        y: (height - iconSize) / 2,
                        width: iconSize,
                        height: iconSize
                    )
                )

                let tSize = textSizes[i]
                let textSlotX = x + iconSize + iconGap
                let textX = textSlotX + (slotWidths[i] - tSize.width)
                let textY = (height - tSize.height) / 2

                (item.text as NSString).draw(
                    at: CGPoint(x: textX, y: textY),
                    withAttributes: [.font: font, .foregroundColor: NSColor.black]
                )

                x += itemWidths[i] + itemGap
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    // MARK: - Desenho de SF Symbol respeitando coordenadas invertidas (flipped)

    private static func drawSymbol(named name: String, color: NSColor, in rect: NSRect) {
        let baseConfig = NSImage.SymbolConfiguration(pointSize: rect.height, weight: .semibold)
        let colorConfig = NSImage.SymbolConfiguration(paletteColors: [color])
        let config = baseConfig.applying(colorConfig)

        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else {
            return
        }

        // Mantém a proporção original do SF Symbol centralizado dentro de `rect`
        let sSize = symbol.size
        guard sSize.width > 0, sSize.height > 0 else { return }
        let scale = min(rect.width / sSize.width, rect.height / sSize.height)
        let drawW = sSize.width * scale
        let drawH = sSize.height * scale
        let drawRect = NSRect(
            x: rect.minX + (rect.width - drawW) / 2,
            y: rect.minY + (rect.height - drawH) / 2,
            width: drawW,
            height: drawH
        )

        symbol.draw(
            in: drawRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0,
            respectFlipped: true,
            hints: nil
        )
    }
}
