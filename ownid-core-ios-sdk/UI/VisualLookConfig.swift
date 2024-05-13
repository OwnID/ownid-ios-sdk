import SwiftUI

public extension OwnID.UISDK {
    struct OTPViewConfig: Equatable {
        public init(authButtonConfig: OwnID.UISDK.AuthButtonViewConfig = .init(),
                    loaderViewConfig: OwnID.UISDK.LoaderViewConfig = .init()) {
            self.authButtonConfig = authButtonConfig
            self.loaderViewConfig = loaderViewConfig
        }
        
        public var authButtonConfig: AuthButtonViewConfig
        public var loaderViewConfig: LoaderViewConfig
    }
    
    struct LoaderViewConfig: Equatable {
        public init(isEnabled: Bool = true,
                    spinnerColor: Color = OwnID.Colors.spinnerColor,
                    circleColor: Color = OwnID.Colors.spinnerBackgroundColor) {
            self.isEnabled = isEnabled
            self.spinnerColor = spinnerColor
            self.circleColor = circleColor
        }
        
        public var isEnabled: Bool
        public var spinnerColor: Color
        public var circleColor: Color
    }
    
    enum WidgetType: Equatable {
        case iconButton
        case authButton
    }
    
    struct AuthButtonViewConfig: Equatable {
        public init(height: CGFloat = 44.0,
                    textSize: CGFloat = 14.0,
                    fontFamily: String? = nil,
                    textColor: Color = .white,
                    backgroundColor: Color = OwnID.Colors.blue,
                    loaderHeight: CGFloat = 24.0,
                    loaderViewConfig: LoaderViewConfig = LoaderViewConfig(spinnerColor: OwnID.Colors.authButtonSpinnerColor,
                                                                          circleColor: OwnID.Colors.authButtonSpinnerBackgroundColor)) {
            self.height = height
            self.textSize = textSize
            self.fontFamily = fontFamily
            self.textColor = textColor
            self.backgroundColor = backgroundColor
            self.loaderHeight = loaderHeight
            self.loaderViewConfig = loaderViewConfig
        }
        
        public var height: CGFloat
        public var textSize: CGFloat
        public var fontFamily: String?
        public var textColor: Color
        public var backgroundColor: Color
        public var loaderHeight: CGFloat
        public var loaderViewConfig: LoaderViewConfig
    }
    
    enum WidgetPosition: String {
        case leading
        case trailing
    }
    
    struct OrViewConfig: Equatable {
        public init(isEnabled: Bool = true,
                    textSize: CGFloat = 16.0,
                    fontFamily: String? = nil,
                    textColor: Color = OwnID.Colors.textGrey) {
            self.isEnabled = isEnabled
            self.textSize = textSize
            self.fontFamily = fontFamily
            self.textColor = textColor
        }
        
        public var isEnabled: Bool
        public var textSize: CGFloat
        public var fontFamily: String?
        public var textColor: Color
    }
    
    struct IconButtonViewConfig: Equatable {
        public init(widgetPosition: WidgetPosition = .leading,
                    height: CGFloat = 44.0,
                    iconColor: Color = OwnID.Colors.biometricsButtonImageColor,
                    borderColor: Color = OwnID.Colors.biometricsButtonBorder,
                    backgroundColor: Color = OwnID.Colors.biometricsButtonBackground,
                    orViewConfig: OrViewConfig = OrViewConfig(),
                    loaderViewConfig: LoaderViewConfig = LoaderViewConfig(),
                    tooltipConfig: TooltipConfig = TooltipConfig()) {
            self.widgetPosition = widgetPosition
            self.height = height
            self.iconColor = iconColor
            self.borderColor = borderColor
            self.backgroundColor = backgroundColor
            self.orViewConfig = orViewConfig
            self.loaderViewConfig = loaderViewConfig
            self.tooltipConfig = tooltipConfig
        }
        
        public var widgetPosition: WidgetPosition
        public var height: CGFloat
        public var iconColor: Color
        public var borderColor: Color
        public var backgroundColor: Color
        public var orViewConfig: OrViewConfig
        public var loaderViewConfig: LoaderViewConfig
        public var tooltipConfig: TooltipConfig
    }
    
    struct VisualLookConfig: Equatable {
        public init(widgetType: WidgetType = .iconButton,
                    iconButtonConfig: IconButtonViewConfig = IconButtonViewConfig(),
                    authButtonConfig: AuthButtonViewConfig = AuthButtonViewConfig()) {
            self.widgetType = widgetType
            self.iconButtonConfig = iconButtonConfig
            self.authButtonConfig = authButtonConfig
        }
        
        public var widgetType: WidgetType
        public var iconButtonConfig: IconButtonViewConfig
        public var authButtonConfig: AuthButtonViewConfig
    }
}

extension OwnID.UISDK.VisualLookConfig {
    func convertToCurrentMetric() -> OwnID.CoreSDK.CurrentMetricInformation {
        var current = OwnID.CoreSDK.CurrentMetricInformation()
        switch iconButtonConfig.widgetPosition {
        case .leading:
            current.widgetPositionType = .start
            
        case .trailing:
            current.widgetPositionType = .end
        }
        
        switch widgetType {
        case .iconButton:
            current.widgetType = .faceid
        case .authButton:
            current.widgetType = .auth
        }
        return current
    }
}
