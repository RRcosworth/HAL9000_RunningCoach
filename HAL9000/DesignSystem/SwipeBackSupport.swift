import SwiftUI
import UIKit

struct SwipeBackSupport: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ViewProbe {
        let view = ViewProbe()
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ uiView: ViewProbe, context: Context) {
        uiView.coordinator = context.coordinator
        uiView.enableSwipeBackSoon()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var navigationController: UINavigationController?

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }

    final class ViewProbe: UIView {
        weak var coordinator: Coordinator?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            enableSwipeBackSoon()
        }

        func enableSwipeBackSoon() {
            DispatchQueue.main.async { [weak self] in
                self?.enableSwipeBack()
            }
        }

        private func enableSwipeBack() {
            guard let coordinator, let navigationController = findNavigationController() else {
                return
            }

            coordinator.navigationController = navigationController
            navigationController.interactivePopGestureRecognizer?.isEnabled = true
            navigationController.interactivePopGestureRecognizer?.delegate = coordinator
        }

        private func findNavigationController() -> UINavigationController? {
            if let controller = nearestViewController(),
               let navigationController = controller.navigationController {
                return navigationController
            }

            guard let rootViewController = window?.rootViewController else {
                return nil
            }

            return rootViewController.deepestNavigationController()
        }

        private func nearestViewController() -> UIViewController? {
            sequence(first: next) { $0?.next }
                .first { $0 is UIViewController } as? UIViewController
        }
    }
}

private extension UIViewController {
    func deepestNavigationController() -> UINavigationController? {
        if let navigationController = self as? UINavigationController {
            if let presented = navigationController.presentedViewController,
               let presentedNavigation = presented.deepestNavigationController() {
                return presentedNavigation
            }
            return navigationController
        }

        if let presented = presentedViewController,
           let presentedNavigation = presented.deepestNavigationController() {
            return presentedNavigation
        }

        for child in children.reversed() {
            if let navigationController = child.deepestNavigationController() {
                return navigationController
            }
        }

        return nil
    }
}

extension View {
    func supportsSwipeBack() -> some View {
        background {
            SwipeBackSupport()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        }
    }
}
