import SwiftUI

extension OwnID.UISDK {
    struct RectangleWithTextView: View {
        private let radius: CGFloat = 6
        @State private var isTranslationChanged = false
        
        private let tooltipConfig: TooltipConfig
        private let authType: AuthType
        
        init(authType: AuthType,
             tooltipConfig: TooltipConfig) {
            self.authType = authType
            self.tooltipConfig = tooltipConfig
        }
        
        var body: some View {
            Text(localizedKey: .tooltip(type: authType.rawValue))
                .foregroundColor(tooltipConfig.textColor)
                .font(font)
                .onReceive(OwnID.CoreSDK.shared.translationsModule.translationsChangePublisher) {
                    isTranslationChanged.toggle()
                }
                .padding(.init(top: 10, leading: 16, bottom: 10, trailing: 16))
                .background(
                    RoundedRectangle(cornerRadius: radius)
                        .fill(tooltipConfig.backgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: radius)
                        .stroke(tooltipConfig.borderColor, lineWidth: 1)
                )
                .overlay(Text("\(String(isTranslationChanged))").foregroundColor(.clear), alignment: .bottom)
        }
        
        private var font: Font {
            if let fontFamily = tooltipConfig.fontFamily {
                .custom(fontFamily, size: tooltipConfig.textSize)
            } else {
                .system(size: tooltipConfig.textSize)
            }
        }
    }
}
