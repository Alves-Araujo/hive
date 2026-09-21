import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';
import '../models/usuario.dart';
import '../services/auth_service.dart';
import '../services/usuario_service.dart';
import 'login_screen.dart';
import 'verificar_email_screen.dart';

// se ainda nao existe perfil salvo (primeiro login, normalmente via google),
// cria um minimo na hora -- tipo de conta e o resto ficam pra tela de
// "concluir perfil", entao nao precisa mais de uma tela separada pra isso
Future<Usuario> _perfilOuCriar(User user) async {
  // O e-mail pode ter sido confirmado com o app fechado (link aberto no
  // navegador) -- ai o usuario ja volta "confirmado", mas o token guardado no
  // aparelho ainda diz o contrario, e o Firestore nega o que as regras
  // reservam pra quem confirmou. Ler a claim e local e barato; so vai na
  // rede quando ela esta mesmo desatualizada
  final token = await user.getIdTokenResult();
  if (token.claims?['email_verified'] != true) {
    await user.getIdToken(true);
  }

  final existente = await UsuarioService.instance.buscarPorUid(user.uid);
  if (existente != null) return existente;

  final nome = user.displayName ?? '';
  final email = user.email ?? '';
  await UsuarioService.instance.criarPerfil(uid: user.uid, nome: nome, email: email);
  return Usuario(uid: user.uid, nome: nome, email: email);
}

// atualiza o "ultimo acesso" sem travar a navegacao (indicador de atividade)
void _registrarAcesso(String uid) {
  UsuarioService.instance.atualizarUltimoAcesso(uid);
}

// decide qual tela mostrar de acordo com o estado de login. e por causa dela
// que o app agora lembra a sessao -- antes sempre abria direto na tela de
// login, mesmo com o firebase ja mantendo o usuario logado
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.mudancasDeEstado,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _TelaCarregando();
        }

        final user = snapshot.data;
        if (user == null) return const TelaLogin();

        // contas google ja chegam com emailVerified = true automaticamente
        if (!user.emailVerified) return const VerificarEmailScreen();

        return FutureBuilder<Usuario>(
          future: _perfilOuCriar(user),
          builder: (context, perfilSnap) {
            if (perfilSnap.connectionState == ConnectionState.waiting || !perfilSnap.hasData) {
              return const _TelaCarregando();
            }
            _registrarAcesso(user.uid);
            return TelaPrincipal(perfil: perfilSnap.data!);
          },
        );
      },
    );
  }
}

class _TelaCarregando extends StatelessWidget {
  const _TelaCarregando();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: corPrimaria)),
    );
  }
}
