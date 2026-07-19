#if os(iOS)
import UIKit

/// One-tap strip for ASM symbols that live on the system keyboard's second symbols page.
final class AssemblySymbolAccessoryBar: UIView {
    /// Immediate / hex / math / strings / hi-lo / labels / comments / indirection.
    private static let symbols = [
        "#", "$", "+", "=", "%", "\"", "'", "<", ">", ":", ";", "*", "(", ")", "[", "]",
    ]

    private let onSymbol: (String) -> Void

    init(onSymbol: @escaping (String) -> Void) {
        self.onSymbol = onSymbol
        // Fixed height — UIKit sizes accessory views from the frame at attach time.
        super.init(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        autoresizingMask = .flexibleWidth
        backgroundColor = .secondarySystemBackground
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private func build() {
        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.alwaysBounceHorizontal = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        let font = UIFont.monospacedSystemFont(ofSize: 18, weight: .medium)
        for symbol in Self.symbols {
            var config = UIButton.Configuration.gray()
            config.title = symbol
            config.baseForegroundColor = .label
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = font
                return outgoing
            }
            let button = UIButton(configuration: config)
            button.addTarget(self, action: #selector(symbolTapped(_:)), for: .touchUpInside)
            stack.addArrangedSubview(button)
        }

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -8),
            stack.centerYAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerYAnchor),
            stack.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    @objc private func symbolTapped(_ sender: UIButton) {
        let title = sender.configuration?.title ?? sender.title(for: .normal)
        guard let title, !title.isEmpty else { return }
        onSymbol(title)
    }
}
#endif
