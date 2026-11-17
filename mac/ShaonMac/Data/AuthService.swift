import SwiftUI
import Observation
import FirebaseCore
import FirebaseAuth
import GoogleSignIn

@MainActor @Observable
final class AuthService {
    enum State { case loading, signedOut, signedIn(uid: String, name: String, email: String) }
    var state: State = .loading
    var error: String?
    @ObservationIgnored private var handle: AuthStateDidChangeListenerHandle?

    init() {
        // Unit tests host the app; they must not open Firebase (its local DB is locked by a running copy).
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { state = .signedOut; return }
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        Auth.auth().languageCode = "he"
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, u in
            self?.state = u.map { .signedIn(uid: $0.uid, name: $0.displayName ?? "", email: $0.email ?? "") } ?? .signedOut
        }
    }

    func signIn() async {
        error = nil
        guard let clientID = FirebaseApp.app()?.options.clientID, let window = NSApp.keyWindow ?? NSApp.windows.first else {
            error = "לא ניתן להתחיל התחברות"; return
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: window)
            guard let idToken = result.user.idToken?.tokenString else { error = "ההתחברות נכשלה"; return }
            let cred = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
            try await Auth.auth().signIn(with: cred)
        } catch {
            if (error as NSError).code != GIDSignInError.canceled.rawValue {
                self.error = "ההתחברות נכשלה: \((error as NSError).localizedDescription)"
            }
        }
    }
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        try? Auth.auth().signOut()
        WidgetSync.clear()
    }
}
