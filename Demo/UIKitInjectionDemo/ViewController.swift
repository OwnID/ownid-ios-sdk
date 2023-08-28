import UIKit
import SwiftUI
import Combine
import OwnIDGigyaSDK
import Gigya

final class ViewController: UIViewController {
    @IBOutlet weak var emailTextField: UITextField!
    @IBOutlet weak var passwordTextField: UITextField!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    var ownIDViewModel: OwnID.FlowsSDK.RegisterView.ViewModel!
    var bag = Set<AnyCancellable>()
    private lazy var ownIdButton = makeOwnIDButton()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        let ownIDViewModel = OwnID.GigyaSDK.registrationViewModel(instance: Gigya.sharedInstance())
                self.ownIDViewModel = ownIDViewModel
        subscribe(to: ownIDViewModel.eventPublisher)
        activityIndicator.isHidden = true
        emailTextField.addTarget(self, action: #selector(ViewController.textFieldDidChange(_:)), for: .editingChanged)
        addChild(ownIdButton)
        view.addSubview(ownIdButton.view)
        ownIdButton.didMove(toParent: self)
        
        NSLayoutConstraint.activate([
            ownIdButton.view.topAnchor.constraint(equalTo: passwordTextField.topAnchor),
            ownIdButton.view.trailingAnchor.constraint(equalTo: passwordTextField.leadingAnchor, constant: 10),
            ownIdButton.view.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    func makeOwnIDButton() -> UIHostingController<OwnID.FlowsSDK.RegisterView> {
        let emailBinding = Binding<String>(
            get: { self.emailTextField.text ?? "" },
            set: { newText in
                self.emailTextField.text = newText
            }
        )
        let headerView = OwnID.GigyaSDK.createRegisterView(viewModel: ownIDViewModel, email: emailBinding)
        let headerVC = UIHostingController(rootView: headerView)
        headerVC.view.translatesAutoresizingMaskIntoConstraints = false
        return headerVC
    }
    
    @objc func textFieldDidChange(_ textField: UITextField) {
    }
    
    @IBAction func registerTapped(_ sender: UIButton) {
        ownIDViewModel.register(with: emailTextField.text ?? "")
    }
    
    func subscribe(to eventsPublisher: OwnID.RegistrationPublisher) {
           eventsPublisher
               .sink { [unowned self] event in
                   switch event {
                   case .success(let event):
                       switch event {
                       case .readyToRegister:
                           activityIndicator.isHidden = true
                           activityIndicator.stopAnimating()
                           
                       case .userRegisteredAndLoggedIn:
                           print("userRegisteredAndLoggedIn")
                         
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

