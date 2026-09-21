import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

// centraliza tudo que mexe com login/cadastro/sessao, pra nao ficar duplicado pelas telas
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _googleSignInPronto = false;

  User? get usuarioAtual => _auth.currentUser;
  Stream<User?> get mudancasDeEstado => _auth.authStateChanges();

  Future<void> _garantirGoogleSignInInicializado() async {
    if (_googleSignInPronto) return;
    await GoogleSignIn.instance.initialize(
      // "Web client ID" gerado pelo Firebase Console quando voce habilita o provedor Google
      // (Authentication > Sign-in method > Google > Web SDK configuration)
      serverClientId: '890336956924-lnokgj8k18f9abqk1g9sms5jujbkg6lu.apps.googleusercontent.com',
    );
    _googleSignInPronto = true;
  }

  Future<UserCredential> entrarComEmailSenha(String email, String senha) {
    return _auth.signInWithEmailAndPassword(email: email, password: senha);
  }

  Future<UserCredential> cadastrarComEmailSenha(String email, String senha) {
    return _auth.createUserWithEmailAndPassword(email: email, password: senha);
  }

  // retorna null se o usuario cancelou o seletor de conta do google
  Future<UserCredential?> entrarComGoogle() async {
    await _garantirGoogleSignInInicializado();
    try {
      final contaGoogle = await GoogleSignIn.instance.authenticate();
      final auth = contaGoogle.authentication;
      final credential = GoogleAuthProvider.credential(idToken: auth.idToken);
      return await _auth.signInWithCredential(credential);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      rethrow;
    }
  }

  Future<void> sair() async {
    await _auth.signOut();
    if (_googleSignInPronto) await GoogleSignIn.instance.signOut();
  }

  Future<void> enviarEmailDeVerificacao() async {
    await _auth.currentUser?.sendEmailVerification();
  }
}
