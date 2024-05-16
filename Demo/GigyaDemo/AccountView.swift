import SwiftUI
import Gigya

public struct AccountModel: Identifiable, Decodable {
    public init(name: String, email: String) {
        self.name = name
        self.email = email
    }
    
    public var id = UUID().uuidString
    public let name: String
    public let email: String
}

public struct AccountView: View {
    public init(model: AccountModel) {
        self.model = model
    }
    
    let model: AccountModel
    @Environment(\.presentationMode) var presentationMode
    @EnvironmentObject var coordinator: AppCoordinator
    
    public var body: some View {
        VStack {
            Text("Welcome \(model.name)!")
                .font(.headline)
                .padding(.bottom, 20)
            
            VStack(spacing: 0) {
                Text("Name")
                    .bold()
                Text(model.name)
                    .padding(.bottom, 2)
                Text("Email")
                    .bold()
                Text(model.email)
            }
            .padding(.bottom)
            Button("Close", action: {
                coordinator.showLogInView()
                Gigya.sharedInstance().logout()
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}
