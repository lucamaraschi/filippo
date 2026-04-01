import AppKit

final class InitialSetupWindowController: NSWindowController {
    private let itemNames: [String]
    private let onSave: (MenuBarConfig) -> Void
    private var config: MenuBarConfig
    private var popupButtons: [String: NSPopUpButton] = [:]

    init(itemNames: [String], config: MenuBarConfig, onSave: @escaping (MenuBarConfig) -> Void) {
        self.itemNames = itemNames
        self.config = config
        self.onSave = onSave

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up Filippo"
        window.center()
        window.isReleasedWhenClosed = false

        super.init(window: window)
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = label(
            "Choose how Filippo should treat the icons currently in your menu bar.",
            font: .systemFont(ofSize: 14, weight: .medium)
        )
        root.addArrangedSubview(titleLabel)

        let hintLabel = label(
            "You can review each icon below, or choose a minimal setup that hides everything except Filippo's own controls.",
            font: .systemFont(ofSize: 12)
        )
        hintLabel.textColor = .secondaryLabelColor
        root.addArrangedSubview(hintLabel)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let rows = NSStackView()
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 8
        rows.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        for name in itemNames {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 12

            let nameLabel = label(name, font: .systemFont(ofSize: 13))
            nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
            nameLabel.widthAnchor.constraint(equalToConstant: 280).isActive = true

            let popup = NSPopUpButton()
            popup.addItems(withTitles: ["Visible", "Hidden", "Disabled"])
            switch config.statusOf(name) {
            case "visible":
                popup.selectItem(withTitle: "Visible")
            case "disabled":
                popup.selectItem(withTitle: "Disabled")
            default:
                popup.selectItem(withTitle: "Hidden")
            }

            popupButtons[name] = popup
            row.addArrangedSubview(nameLabel)
            row.addArrangedSubview(popup)
            rows.addArrangedSubview(row)
        }

        scrollView.documentView = rows
        root.addArrangedSubview(scrollView)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 10

        let minimalButton = NSButton(title: "Minimal Experience", target: self, action: #selector(applyMinimalExperience))
        let saveButton = NSButton(title: "Save Setup", target: self, action: #selector(saveSetup))
        let skipButton = NSButton(title: "Not Now", target: self, action: #selector(closeWindow))

        saveButton.bezelStyle = .rounded
        minimalButton.bezelStyle = .rounded
        skipButton.bezelStyle = .rounded

        buttonRow.addArrangedSubview(minimalButton)
        buttonRow.addArrangedSubview(saveButton)
        buttonRow.addArrangedSubview(skipButton)
        root.addArrangedSubview(buttonRow)

        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -20),
            scrollView.widthAnchor.constraint(equalTo: root.widthAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 340),
        ])
    }

    private func label(_ text: String, font: NSFont) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }

    @objc private func applyMinimalExperience() {
        config.icons.visible = []
        config.icons.hidden = itemNames
        config.icons.disabled = []
        onSave(config)
        closeWindow()
    }

    @objc private func saveSetup() {
        var next = config
        next.icons.visible = []
        next.icons.hidden = []
        next.icons.disabled = []

        for name in itemNames {
            let selected = popupButtons[name]?.selectedItem?.title.lowercased() ?? "hidden"
            next.setStatus(name, status: selected)
        }

        onSave(next)
        closeWindow()
    }

    @objc private func closeWindow() {
        window?.close()
        NSApp.stopModal()
    }

    func runModal() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: window)
    }
}
