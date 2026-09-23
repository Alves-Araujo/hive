import 'package:cloud_firestore/cloud_firestore.dart';
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

  // manda o e-mail com o link de redefinicao de senha.
  //
  // Com a protecao contra enumeracao de e-mail ligada (padrao dos projetos
  // novos no Firebase), um e-mail SEM conta nao levanta 'user-not-found' --
  // a chamada simplesmente passa. Por isso quem chama responde a mesma coisa
  // nos dois casos, em vez de confirmar pra qualquer um se um e-mail tem
  // cadastro aqui
  Future<void> enviarEmailDeRedefinicaoDeSenha(String email) {
    return _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> sair() async {
    await _auth.signOut();
    if (_googleSignInPronto) await GoogleSignIn.instance.signOut();
  }

  Future<void> enviarEmailDeVerificacao() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  // true se o login foi feito com e-mail/senha -- decide se a reautenticacao
  // (pedida pelo firebase antes de excluir a conta) pede senha ou reabre o
  // seletor do Google
  bool get precisaSenhaPraReautenticar =>
      _auth.currentUser?.providerData.any((p) => p.providerId == 'password') ?? false;

  // repete a prova de identidade exigida pelo firebase pra operacao sensivel
  // (excluir conta) quando o login já não é recente. Sem isso, currentUser!.delete()
  // falha com 'requires-recent-login' pra quem nao entrou agora ha pouco
  Future<void> reautenticar({String? senha}) async {
    final usuario = _auth.currentUser;
    if (usuario == null) return;

    if (precisaSenhaPraReautenticar) {
      if (senha == null || senha.isEmpty || usuario.email == null) {
        throw ArgumentError('Senha necessária para reautenticar');
      }
      final credential = EmailAuthProvider.credential(email: usuario.email!, password: senha);
      await usuario.reauthenticateWithCredential(credential);
      return;
    }

    await _garantirGoogleSignInInicializado();
    final contaGoogle = await GoogleSignIn.instance.authenticate();
    final auth = contaGoogle.authentication;
    final credential = GoogleAuthProvider.credential(idToken: auth.idToken);
    await usuario.reauthenticateWithCredential(credential);
  }

  // apaga o que o app tem permissao de apagar (anuncios, avisos pessoais,
  // perfil publico e privado) e por ultimo a conta no firebase auth --
  // precisa ser por ultimo porque sem usuario logado nenhuma das regras acima
  // deixa mais escrever.
  //
  // Nao ha Cloud Functions no projeto (ver notificacao_service.dart), entao
  // nao existe faxina automatica de servidor: avaliacoes recebidas e
  // conversas continuam existindo, do mesmo jeito que um anuncio removido
  // nao apaga as mensagens trocadas nele
  Future<void> excluirConta() async {
    final usuario = _auth.currentUser;
    if (usuario == null) return;
    final uid = usuario.uid;
    final db = FirebaseFirestore.instance;

    final imoveis = await db.collection('imoveis').where('donoUid', isEqualTo: uid).get();
    final notificacoes = await db.collection('usuarios').doc(uid).collection('notificacoes').get();

    final lote = db.batch();
    for (final doc in imoveis.docs) {
      lote.delete(doc.reference);
    }
    for (final doc in notificacoes.docs) {
      lote.delete(doc.reference);
    }
    lote.delete(db.collection('perfisPublicos').doc(uid));
    lote.delete(db.collection('usuarios').doc(uid));
    await lote.commit();

    await usuario.delete();
    if (_googleSignInPronto) await GoogleSignIn.instance.signOut();
  }
}
