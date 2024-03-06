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
        
        let emailPublisher = NotificationCenter.default
            .publisher(for: UITextField.textDidChangeNotification, object: emailTextField)
            .map({ ($0.object as? UITextField)?.text ?? "" })
        
        let ownIDViewModel = OwnID.GigyaSDK.registrationViewModel(instance: Gigya.sharedInstance(), loginIdPublisher: emailPublisher.eraseToAnyPublisher())
        self.ownIDViewModel = ownIDViewModel
        subscribe(to: ownIDViewModel.integrationEventPublisher)
        activityIndicator.isHidden = true
        emailTextField.addTarget(self, action: #selector(ViewController.textFieldDidChange(_:)), for: .editingChanged)
        addChild(ownIdButton)
        view.addSubview(ownIdButton.view)
        ownIdButton.didMove(toParent: self)
        
        NSLayoutConstraint.activate([
            ownIdButton.view.topAnchor.constraint(equalTo: passwordTextField.topAnchor),
            ownIdButton.view.trailingAnchor.constraint(equalTo: passwordTextField.leadingAnchor, constant: -10),
            ownIdButton.view.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    
    func makeOwnIDButton() -> UIHostingController<OwnID.FlowsSDK.RegisterView> {
        let headerView = OwnID.GigyaSDK.createRegisterView(viewModel: ownIDViewModel)
        let headerVC = UIHostingController(rootView: headerView)
        headerVC.view.translatesAutoresizingMaskIntoConstraints = false
        return headerVC
    }
    
    @objc func textFieldDidChange(_ textField: UITextField) {
    }
    
    @IBAction func registerTapped(_ sender: UIButton) {
        ownIDViewModel.register()
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

