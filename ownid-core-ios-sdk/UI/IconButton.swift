import Foundation
import SwiftUI

extension OwnID.UISDK {
    struct IconButton: View {
        let visualConfig: VisualLookConfig
        let actionHandler: (() -> Void)
        
        @Binding var isTooltipPresented: Bool
        @Binding var isLoading: Bool
        @Binding var buttonState: ButtonState
        
        @Environment(\.colorScheme) var colorScheme
        @Environment(\.layoutDirection) var direction
        
        var body: some View {
            HStack(spacing: 8) {
                switch visualConfig.widgetPosition {
                case .trailing:
                    orView()
                    buttonAndTooltipView()
                    
                case .leading:
                    buttonAndTooltipView()
                    orView()
                }
            }
        }
    }
}

private extension OwnID.UISDK.IconButton {
    private enum Constants {
        static let imageName = "faceidImage"
    }
    
    @ViewBuilder
    func orView() -> some View {
        if visualConfig.orViewConfig.isEnabled {
            OwnID.UISDK.OrView(textSize: visualConfig.orViewConfig.textSize,
                               lineHeight: visualConfig.orViewConfig.lineHeight,
                               textColor: visualConfig.orViewConfig.textColor)
        }
    }
    
    @ViewBuilder
    func buttonAndTooltipView() -> some View {
        if isTooltipPresented, buttonState.isTooltipShown, !isLoading, #available(iOS 16.0, *) {
            tooltipOnTopOfButtonView()
                .zIndex(1)
        } else {
            imageView()
        }
    }
    
    func variantImage() -> some View {
        let image = Image(Constants.imageName, bundle: .resourceBundle)
            .resizable()
            .renderingMode(.template)
            .frame(width: visualConfig.buttonViewConfig.iconHeight, height: visualConfig.buttonViewConfig.iconHeight)
            .foregroundColor(visualConfig.buttonViewConfig.iconColor)
        return image
    }
    
    @ViewBuilder
    func buttonContents() -> some View {
        ZStack {
            variantImage()
                .layoutPriority(1)
                .opacity(isLoading ? 0 : 1)
            OwnID.UISDK.SpinnerLoaderView(spinnerColor: visualConfig.loaderViewConfig.color,
                                          spinnerBackgroundColor: visualConfig.loaderViewConfig.backgroundColor,
                                          viewBackgroundColor: visualConfig.buttonViewConfig.backgroundColor)
            .opacity(isLoading ? 1 : 0)
        }
    }
    
    @ViewBuilder
    func imageView() -> some View {
        OwnID.UISDK.BorderAndHighlightButton(viewState: $buttonState,
                                             buttonViewConfig: visualConfig.buttonViewConfig,
                                             action: actionHandler,
                                             content: buttonContents())
        .layoutPriority(1)
    }
    
    @ViewBuilder
    func tooltipOnTopOfButtonView() -> some View {
        if #available(iOS 16.0, *) {
            OwnID.UISDK.TooltipContainerLayout(tooltipPosition: visualConfig.tooltipVisualLookConfig.tooltipPosition) {
                OwnID.UISDK.TooltipTextAndArrowLayout(tooltipVisualLookConfig: visualConfig.tooltipVisualLookConfig, isRTL: direction == .rightToLeft) {
                    OwnID.UISDK.RectangleWithTextView(tooltipVisualLookConfig: visualConfig.tooltipVisualLookConfig)
                        .popupTextContainerType(.text)
                    OwnID.UISDK.BeakView(tooltipVisualLookConfig: visualConfig.tooltipVisualLookConfig)
                        .rotationEffect(.degrees(visualConfig.tooltipVisualLookConfig.tooltipPosition.beakViewRotationAngle))
                        .popupTextContainerType(.beak)
                }
                .compositingGroup()
                .shadow(color: colorScheme == .dark ? .clear : visualConfig.tooltipVisualLookConfig.shadowColor.opacity(0.05), radius: 5, y: 4)
                .popupContainerType(.textAndArrowContainer)
                Button(action: { isTooltipPresented = false }) {
                    Text("")
                        .foregroundColor(.clear)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .popupContainerType(.dismissButton)
                imageView()
                    .popupContainerType(.ownIdButton)
            }
        }
    }
}
