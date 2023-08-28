import SwiftUI
import Combine

public extension OwnID.UISDK {
    struct OwnIDView: View {
        private let visualConfig: VisualLookConfig
        
        private let coordinateSpaceName = String(describing: OwnID.UISDK.BorderAndHighlightButton.self)
        @Binding private var isTooltipPresented: Bool
        @Binding private var isLoading: Bool
        @Binding private var buttonState: ButtonState
        
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
                    shouldShowTooltip: Binding<Bool>,
                    isLoading: Binding<Bool>) {
            _isTooltipPresented = shouldShowTooltip
            _isLoading = isLoading
            _buttonState = viewState
            self.visualConfig = visualConfig
            OwnID.CoreSDK.shared.currentMetricInformation = visualConfig.convertToCurrentMetric()
        }
        
        public var body: some View {
            switch visualConfig.buttonViewConfig.variant {
            case .authButton:
                AuthButton(visualConfig: visualConfig,
                           actionHandler: { resultPublisher.send(()) },
                           isLoading: $isLoading,
                           buttonState: $buttonState)
                
            case .iconButton:
                IconButton(visualConfig: visualConfig,
                           actionHandler: { resultPublisher.send(()) },
                           isTooltipPresented: $isTooltipPresented,
                           isLoading: $isLoading,
                           buttonState: $buttonState)
                .modifier(AccessibilityLabelModifier(accessibilityLabel: skipPassword))
            }
        }
    }
}
