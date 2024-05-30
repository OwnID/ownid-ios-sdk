import SwiftUI

public struct WelcomeView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    
    @State private var isLoginActive = false
    @State private var isRegisterActive = false
    
    public init() { }
    
    public var body: some View {
        NavigationView {
            ZStack {
                VStack {
                    HeaderView()
                    Spacer()
                }
                .ignoresSafeArea()
                VStack {
                    Text("Welcome to OwnID Demo App")
                        .font(.system(size: 20))
                        .padding(.top, 30)
                    Group {
                        NavigationLink(destination: RegisterView(),
                                       isActive: $isRegisterActive) {
                            BlueButton(text: "Register") {
                                self.isRegisterActive = true
                            }
                        }
                        NavigationLink(destination: LogInView(),
                                       isActive: $isLoginActive) {
                            BlueButton(text: "Login") {
                                self.isLoginActive = true
                            }
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.vertical, 10)
                }
            }
        }
    }
}
