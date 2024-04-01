import SwiftUI

extension OwnID.UISDK {
    struct OrView: View {
        @State private var isTranslationChanged = false
        let textSize: CGFloat
        let fontFamily: String?
        let textColor: Color
        
        init(textSize: CGFloat, fontFamily: String?, textColor: Color) {
            self.textSize = textSize
            self.fontFamily = fontFamily
            self.textColor = textColor
        }
        
        var body: some View {
            Text(localizedKey: .or)
                .font(font)
                .foregroundColor(textColor)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .onReceive(OwnID.CoreSDK.shared.translationsModule.translationsChangePublisher) {
                    isTranslationChanged.toggle()
                }
                .overlay(Text("\(String(isTranslationChanged))").foregroundColor(.clear), alignment: .bottom)
        }
        
        private var font: Font {
            if let fontFamily {
                .custom(fontFamily, size: textSize)
            } else {
                .system(size: textSize)
            }
        }
    }
}
