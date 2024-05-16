import SwiftUI

struct LoggedOutCoordinatorView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    
    var body: some View {
        navigation()
            .onAppear(perform: {
                coordinator.showLogInView()
            })
    }
    
    func navigation() -> some View {
        VStack {
            HStack(spacing: 0) {
                loginButtonView()
                registerButtonView()
            }
            .frame(minWidth: 0, maxWidth: .infinity)
            .padding()
            .padding(.leading, 30)
            .padding(.trailing, 30)
            .padding(.bottom)
            contentView()
                .padding(.leading)
                .padding(.trailing)
                .padding(.bottom)
        }
    }
    
    @ViewBuilder
    func contentView() -> some View {
        switch coordinator.appState.loggedOutState {
        case .conflictingAccounts(_):
            EmptyView()
            
        case .logIn:
            LogInView()
            
        case .register:
            RegisterView()
            
        case .initial:
            EmptyView()
        }
    }
    
    @ViewBuilder
    func loginButtonView() -> some View {
        let view = VStack {
            Button(action: { coordinator.showLogInView() }, label: {
                logInText()
            })
        }
            .frame(minWidth: 0, maxWidth: .infinity)

        switch coordinator.appState.loggedOutState {
        case .logIn, .conflictingAccounts:
            view
                .bottomLine(color: Color("blue"))

        case .register:
            view
                .bottomLine(color: Color("bottomLine"))

        case .initial:
            view
        }
    }
    
    @ViewBuilder
    func logInText() -> some View {
        let text = Text("Log in")
        switch coordinator.appState.loggedOutState {
        case .logIn, .conflictingAccounts:
            text
                .applyTextStyling(isActive: true)
            
        case .register:
            text
                .applyTextStyling(isActive: false)
            
        case .initial:
            text
        }
    }
    
    @ViewBuilder
    func registerButtonView() -> some View {
        let view = VStack {
            Button(action: { coordinator.showRegisterView() }, label: {
                registerText()
            })
        }
            .frame(minWidth: 0, maxWidth: .infinity)
        
        switch coordinator.appState.loggedOutState {
        case .logIn, .conflictingAccounts:
            view
                .bottomLine(color: Color("bottomLine"))
            
        case .register:
            view
                .bottomLine(color: Color("blue"))
            
        case .initial:
            view
        }
    }
    
    @ViewBuilder
    func registerText() -> some View {
        let text = Text("Create Account")
        switch coordinator.appState.loggedOutState {
        case .logIn, .conflictingAccounts:
            text
                .applyTextStyling(isActive: false)
            
        case .register:
            text
                .applyTextStyling(isActive: true)
            
        case .initial:
            text
        }
    }
}

extension Text {
    func applyTextStyling(isActive: Bool) -> some View {
        self
        .foregroundColor(isActive ? Color("blue") : Color("textGray"))
        .font(.system(size: 14, weight: .bold))
    }
}

public extension View {
    func bottomLine(color: Color) -> some View {
        self
            .overlay(Rectangle().frame(height: 2).offset(y: 10), alignment: .bottom)
            .foregroundColor(color)
    }
}
