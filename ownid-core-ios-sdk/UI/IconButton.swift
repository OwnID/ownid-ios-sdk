import Foundation
import SwiftUI

extension OwnID.UISDK {
    struct IconButton: View {
        let visualConfig: VisualLookConfig
        let actionHandler: (() -> Void)
        let authType: AuthType
        
        @Binding var shouldShowTooltip: Bool
        @Binding var isLoading: Bool
        @Binding var buttonState: ButtonState
        
        @Environment(\.colorScheme) var colorScheme
        @Environment(\.layoutDirection) var direction
        
        var body: some View {
            HStack(spacing: 8) {
                switch visualConfig.iconButtonConfig.widgetPosition {
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
        if visualConfig.iconButtonConfig.orViewConfig.isEnabled {
            OwnID.UISDK.OrView(textSize: visualConfig.iconButtonConfig.orViewConfig.textSize,
                               fontFamily: visualConfig.iconButtonConfig.orViewConfig.fontFamily,
                               textColor: visualConfig.iconButtonConfig.orViewConfig.textColor)
        }
    }
    
    @ViewBuilder
    func buttonAndTooltipView() -> some View {
        if visualConfig.iconButtonConfig.tooltipConfig.isEnabled, shouldShowTooltip, buttonState.isTooltipShown, !isLoading {
            if #available(iOS 16.0, *) {
                tooltipOnTopOfButtonView()
                    .zIndex(1)
            } else {
                legacyTooltip()
                    .zIndex(1)
            }
        } else {
            imageView()
        }
    }
    
    func variantImage() -> some View {
        let image = Image(Constants.imageName, bundle: .resourceBundle)
            .resizable()
            .renderingMode(.template)
            .foregroundColor(visualConfig.iconButtonConfig.iconColor)
            .frame(width: visualConfig.iconButtonConfig.height - 16, height: visualConfig.iconButtonConfig.height - 16)
        return image
    }
    
    @ViewBuilder
    func buttonContents() -> some View {
        ZStack {
            variantImage()
                .layoutPriority(1)
                .opacity(isLoading ? 0 : 1)
            if visualConfig.iconButtonConfig.loaderViewConfig.isEnabled {
                OwnID.UISDK.SpinnerLoaderView(spinnerColor: visualConfig.iconButtonConfig.loaderViewConfig.spinnerColor,
                                              circleColor: visualConfig.iconButtonConfig.loaderViewConfig.circleColor,
                                              viewBackgroundColor: visualConfig.iconButtonConfig.backgroundColor,
                                              isLoading: $isLoading)
                .padding(2)
                .opacity(isLoading ? 1 : 0)
            }
        }
    }
    
    @ViewBuilder
    func imageView() -> some View {
        OwnID.UISDK.BorderAndHighlightButton(viewState: $buttonState,
                                             buttonViewConfig: visualConfig.iconButtonConfig,
                                             action: actionHandler,
                                             content: buttonContents())
        .frame(width: visualConfig.iconButtonConfig.height, height: visualConfig.iconButtonConfig.height)
        .layoutPriority(1)
    }
    
    @ViewBuilder
    func tooltipOnTopOfButtonView() -> some View {
        if #available(iOS 16.0, *) {
            OwnID.UISDK.TooltipContainerLayout(tooltipPosition: visualConfig.iconButtonConfig.tooltipConfig.tooltipPosition) {
                OwnID.UISDK.TooltipTextAndArrowLayout(tooltipConfig: visualConfig.iconButtonConfig.tooltipConfig,
                                                      isRTL: direction == .rightToLeft) {
                    OwnID.UISDK.RectangleWithTextView(authType: authType,
                                                      tooltipConfig: visualConfig.iconButtonConfig.tooltipConfig)
                        .popupTextContainerType(.text)
                    OwnID.UISDK.BeakView(tooltipConfig: visualConfig.iconButtonConfig.tooltipConfig)
                        .rotationEffect(.degrees(visualConfig.iconButtonConfig.tooltipConfig.tooltipPosition.beakViewRotationAngle))
                        .popupTextContainerType(.beak)
                }
                .compositingGroup()
                .shadow(color: colorScheme == .dark ? .clear : .black.opacity(0.05), radius: 5, y: 4)
                .popupContainerType(.textAndArrowContainer)
                Button(action: { shouldShowTooltip = false }) {
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
    
    @ViewBuilder
    func legacyTooltip() -> some View {
        let tooltipConfig = visualConfig.iconButtonConfig.tooltipConfig
        let constant = OwnID.UISDK.ATConstant(axisMode: OwnID.UISDK.ATAxisMode.mode(configPosition: tooltipConfig.tooltipPosition),
                                              border: OwnID.UISDK.ATBorderConstant(color: tooltipConfig.borderColor),
                                              shadow: OwnID.UISDK.ATShadowConstant(color: .black.opacity(0.05)))
        ZStack {
            Text(" ")
                .frame(width: visualConfig.iconButtonConfig.height, height: visualConfig.iconButtonConfig.height)
                .axisToolTip(isPresented: $shouldShowTooltip, constant: constant) {
                    visualConfig.iconButtonConfig.tooltipConfig.backgroundColor
                } foreground: {
                    Text(localizedKey: .tooltip(type: authType.rawValue))
                        .foregroundColor(tooltipConfig.textColor)
                        .font(tooltipFont)
                        .padding()
                }
            imageView()
        }
    }
    
    private var tooltipFont: Font {
        let tooltipConfig = visualConfig.iconButtonConfig.tooltipConfig
        if let fontFamily = tooltipConfig.fontFamily {
            return .custom(fontFamily, size: tooltipConfig.textSize)
        } else {
            return .system(size: tooltipConfig.textSize)
        }
    }
}
