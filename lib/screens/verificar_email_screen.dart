import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';
import '../services/auth_service.dart';
import '../widgets/animated_gradient_button.dart';
import 'auth_gate.dart';

// pedida logo apos o cadastro por senha -- o firebase manda um link de
// confirmacao por e-mail (nao um codigo numerico, o auth nativo nao tem isso)
class VerificarEmailScreen extends StatefulWidget {
  const VerificarEmailScreen({super.key});

  @override
  State<VerificarEmailScreen> createState() => _VerificarEmailScreenState();
}

class _VerificarEmailScreenState extends State<VerificarEmailScreen> {
  bool _verificando = false;
  bool _reenviando = false;
  int _cooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _iniciarCooldown() {
    setState(() => _cooldown = 30);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_cooldown <= 1) {
        timer.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  Future<void> _reenviarEmail() async {
    setState(() => _reenviando = true);
    try {
      await AuthService.instance.enviarEmailDeVerificacao();
      _iniciarCooldown();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('E-mail reenviado!'), backgroundColor: corSucesso),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao reenviar: $e'), backgroundColor: corErro),
        );
      }
    } finally {
      if (mounted) setState(() => _reenviando = false);
    }
  }

  Future<void> _jaConfirmei() async {
    setState(() => _verificando = true);
    await FirebaseAuth.instance.currentUser?.reload();
    final user = FirebaseAuth.instance.currentUser;

    if (!mounted) return;
    setState(() => _verificando = false);

    if (user != null && user.emailVerified) {
      // reload() atualiza o usuario AQUI no app, mas o token que o Firestore
      // manda nas requisicoes continua dizendo "e-mail nao confirmado" ate
      // ser renovado -- o que sozinho leva ate uma hora. As regras que exigem
      // e-mail confirmado negavam tudo nesse meio tempo, e a primeira coisa
      // que a pessoa faz depois de confirmar (salvar o perfil) falhava
      await user.getIdToken(true);
      if (!mounted) return;

      // reload() nao dispara authStateChanges sozinho, entao reconstruimos a
      // auth gate na mao pra ela reavaliar o estado ja atualizado
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const AuthGate()),
        (route) => false,
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ainda não encontramos a confirmação. Clique no link do e-mail e tente de novo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final email = FirebaseAuth.instance.currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: isDark ? corFundoEscuro : corFundoClaro,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(Icons.mark_email_unread_rounded, size: 72, color: corPrimaria.withAlpha(180)),
              const SizedBox(height: 24),
              Text(
                'Confirme seu e-mail',
                textAlign: TextAlign.center,
                style: AppTextStyles.heading1.copyWith(
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Mandamos um link de confirmação pra $email. Clique nele e depois volte aqui.',
                textAlign: TextAlign.center,
                style: AppTextStyles.caption.copyWith(
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 32),
              AnimatedGradientButton(
                label: 'Já confirmei',
                isLoading: _verificando,
                onTap: _jaConfirmei,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: (_reenviando || _cooldown > 0) ? null : _reenviarEmail,
                child: Text(
                  _cooldown > 0 ? 'Reenviar em ${_cooldown}s' : 'Reenviar e-mail',
                  style: TextStyle(color: corPrimaria.withAlpha(200), fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                onPressed: () => AuthService.instance.sair(),
                child: Text(
                  'Sair',
                  style: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
                ),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
