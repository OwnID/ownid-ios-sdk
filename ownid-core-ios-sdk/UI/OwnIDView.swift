import SwiftUI
import Combine

extension OwnID.UISDK {
    final class DebouncedAction {
        private let input = PassthroughSubject<Void, Never>()
        private let action: () -> Void
        private var cancellable: AnyCancellable?

        init(action: @escaping () -> Void) {
            self.action = action
            subscribe()
        }

        func send() {
            input.send(())
        }

        func cancelPending() {
            cancellable?.cancel()
            subscribe()
        }

        private func subscribe() {
            cancellable = input
                .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
                .sink(receiveValue: action)
        }
    }
}

public extension OwnID.UISDK {
    enum AuthType: String {
        case login, register
    }
    
    struct OwnIDView: View {
        private let visualConfig: VisualLookConfig
        
        private let coordinateSpaceName = String(describing: OwnID.UISDK.BorderAndHighlightButton.self)
        @Binding private var shouldShowTooltip: Bool
        @Binding private var isLoading: Bool
        @Binding private var buttonState: ButtonState
        
        private let authType: AuthType
        private let actionHandler: (() -> Void)?
        private let resultPublisher = PassthroughSubject<Void, Never>()
        
        public var eventPublisher: OwnID.UISDK.EventPubliser {
            resultPublisher
                .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
                .eraseToAnyPublisher()
        }
        
        private var skipPassword: String {
            OwnID.CoreSDK.TranslationsSDK.TranslationKey.skipPassword.localized()
        }
        
        public init(viewState: Binding<ButtonState>,
                    visualConfig: VisualLookConfig,
                    authType: AuthType,
                    shouldShowTooltip: Binding<Bool>,
                    isLoading: Binding<Bool>) {
            self.init(viewState: viewState,
                      visualConfig: visualConfig,
                      authType: authType,
                      shouldShowTooltip: shouldShowTooltip,
                      isLoading: isLoading,
                      actionHandler: nil)
        }

        init(viewState: Binding<ButtonState>,
             visualConfig: VisualLookConfig,
             authType: AuthType,
             shouldShowTooltip: Binding<Bool>,
             isLoading: Binding<Bool>,
             actionHandler: (() -> Void)?) {
            _shouldShowTooltip = shouldShowTooltip
            _isLoading = isLoading
            _buttonState = viewState
            self.authType = authType
            self.visualConfig = visualConfig
            self.actionHandler = actionHandler
            OwnID.CoreSDK.shared.currentMetricInformation = visualConfig.convertToCurrentMetric()
        }
        
        public var body: some View {
            switch visualConfig.widgetType {
            case .authButton:
                AuthButton(visualConfig: visualConfig,
                           actionHandler: sendAction,
                           isLoading: $isLoading,
                           buttonState: $buttonState)
                
            case .iconButton:
                IconButton(visualConfig: visualConfig,
                           actionHandler: sendAction,
                           authType: authType,
                           shouldShowTooltip: $shouldShowTooltip,
                           isLoading: $isLoading,
                           buttonState: $buttonState)
                .modifier(AccessibilityLabelModifier(accessibilityLabel: skipPassword))
            }
        }

        private func sendAction() {
            guard !isLoading else { return }
            actionHandler?() ?? resultPublisher.send(())
        }
    }
}
