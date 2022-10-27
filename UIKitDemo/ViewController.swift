import UIKit
import SwiftUI
import Combine
import OwnIDGigyaSDK
import DemoComponents

final class ViewController: UIViewController {
    @IBOutlet weak var emailTextField: UITextField!
    @IBOutlet weak var passwordTextField: UITextField!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    let ownIDViewModel = OwnID.GigyaSDK.registrationViewModel(instance: GigyaShared.instance)
    private var userEmail = ""
    var bag = Set<AnyCancellable>()
    private lazy var ownIdButton = makeOwnIDButton()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        subscribe(to: ownIDViewModel.eventPublisher)
        activityIndicator.isHidden = true
        emailTextField.addTarget(self, action: #selector(ViewController.textFieldDidChange(_:)), for: .editingChanged)
        addChild(ownIdButton)
        view.addSubview(ownIdButton.view)
        ownIdButton.didMove(toParent: self)
        
        NSLayoutConstraint.activate([
            ownIdButton.view.topAnchor.constraint(equalTo: passwordTextField.topAnchor),
            ownIdButton.view.leadingAnchor.constraint(equalTo: passwordTextField.trailingAnchor, constant: 10),
            ownIdButton.view.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    func makeOwnIDButton() -> UIHostingController<OwnID.FlowsSDK.RegisterView> {
        let headerView = OwnID.GigyaSDK.createRegisterView(viewModel: ownIDViewModel, email: emailBinding)
        let headerVC = UIHostingController(rootView: headerView)
        headerVC.view.translatesAutoresizingMaskIntoConstraints = false
        return headerVC
    }
    
    var emailBinding: Binding<String> {
        Binding(
            get: { self.userEmail },
            set: { _ in }
        )
    }
    
    @objc func textFieldDidChange(_ textField: UITextField) {
        userEmail = textField.text ?? ""
    }
    
    @IBAction func registerTapped(_ sender: UIButton) {
        ownIDViewModel.register(with: userEmail)
    }
    
    func subscribe(to eventsPublisher: OwnID.RegistrationPublisher) {
           eventsPublisher
               .sink { [unowned self] event in
                   switch event {
                   case .success(let event):
                       switch event {
                       // Event when user successfully
                       // finishes Skip Password
                       // in OwnID Web App
                       case .readyToRegister:
                           activityIndicator.isHidden = true
                           activityIndicator.stopAnimating()

                       // Event when OwnID creates Firebase
                       // account and logs in user
                       case .userRegisteredAndLoggedIn:
                           break
                         
                       case .loading:
                           activityIndicator.isHidden = false
                           activityIndicator.startAnimating()
                           
                       case .resetTapped:
                           print(OwnID.FlowsSDK.RegistrationEvent.resetTapped)
                       }

                   case .failure(let error):
                       activityIndicator.isHidden = true
                       activityIndicator.stopAnimating()
                       print(error.localizedDescription)
                   }
               }
               .store(in: &bag)
       }
}

