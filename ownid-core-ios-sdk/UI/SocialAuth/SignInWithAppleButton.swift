import SwiftUI
import AuthenticationServices

extension OwnID.UISDK {
    public struct SignInWithAppleButton: UIViewRepresentable {
        let type: ASAuthorizationAppleIDButton.ButtonType
        let style: ASAuthorizationAppleIDButton.Style
        
        var onTap: () -> Void
        
        public init(type: ASAuthorizationAppleIDButton.ButtonType = .default,
                    style: ASAuthorizationAppleIDButton.Style = .black,
                    onTap: @escaping () -> Void) {
            self.type = type
            self.style = style
            self.onTap = onTap
        }
        
        public func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
            let appleIDButton = ASAuthorizationAppleIDButton(type: type, style: style)
            
            appleIDButton.addTarget(context.coordinator,
                                    action: #selector(Coordinator.didTapButton),
                                    for: .touchUpInside)
            return appleIDButton
        }
        
        public func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        }
        
        public func makeCoordinator() -> Coordinator {
            Coordinator(onTap: onTap)
        }
        
        public class Coordinator: NSObject {
            let onTap: () -> Void
            
            init(onTap: @escaping () -> Void) {
                self.onTap = onTap
            }
            
            @objc func didTapButton() {
                onTap()
            }
        }
    }
}
