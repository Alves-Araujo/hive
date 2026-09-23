import 'dart:math';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../main.dart';
import '../widgets/campo_formulario.dart';
import '../services/auth_service.dart';
import '../widgets/animated_gradient_button.dart';
import 'cadastro_screen.dart';

class TelaLogin extends StatefulWidget {
  const TelaLogin({super.key});

  @override
  State<TelaLogin> createState() => _TelaLoginState();
}

class _TelaLoginState extends State<TelaLogin> with TickerProviderStateMixin {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _senhaController = TextEditingController();
  bool _senhaVisivel = false;
  bool _carregando = false;
  bool _carregandoGoogle = false;

  // animacoes de entrada
  late AnimationController _staggerController;
  late AnimationController _bgController;
  late List<Animation<double>> _fadeAnims;
  late List<Animation<Offset>> _slideAnims;

  @override
  void initState() {
    super.initState();

    // animacao de fundo (orbes)
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    // animacoes staggered pra 6 elementos
    _staggerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _fadeAnims = List.generate(6, (i) {
      final start = (i * 0.12).clamp(0.0, 1.0);
      final end = (start + 0.4).clamp(0.0, 1.0);
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(
          parent: _staggerController,
          curve: Interval(start, end, curve: Curves.easeOut),
        ),
      );
    });

    _slideAnims = List.generate(6, (i) {
      final start = (i * 0.12).clamp(0.0, 1.0);
      final end = (start + 0.4).clamp(0.0, 1.0);
      return Tween<Offset>(
        begin: const Offset(0, 0.15),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: _staggerController,
          curve: Interval(start, end, curve: Curves.easeOutCubic),
        ),
      );
    });

    _staggerController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();
    _staggerController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  // login de verdade no firebase e busca o tipo do usuario
  Future<void> _entrar() async {
    final email = _emailController.text.trim();
    final senha = _senhaController.text;

    if (email.isEmpty || !email.contains('@')) {
      _mostrarErro('Informe um e-mail válido.');
      return;
    }
    if (senha.length < 6) {
      _mostrarErro('A senha deve ter pelo menos 6 caracteres.');
      return;
    }

    setState(() => _carregando = true);

    try {
      // autentica no firebase -- a AuthGate percebe sozinha e troca de tela
      await AuthService.instance.entrarComEmailSenha(email, senha);
    } on FirebaseAuthException catch (e) {
      String msgErro = 'Erro ao fazer login.';
      if (e.code == 'user-not-found' || e.code == 'invalid-email') {
        msgErro = 'Nenhum usuário encontrado para esse e-mail.';
      } else if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        msgErro = 'E-mail ou senha incorretos.';
      } else if (e.code == 'user-disabled') {
        msgErro = 'Essa conta foi desativada.';
      }
      _mostrarErro(msgErro);
    } catch (e) {
      _mostrarErro('Ocorreu um erro inesperado.');
    } finally {
      if (mounted) {
        setState(() => _carregando = false);
      }
    }
  }

  // login com google -- a AuthGate cuida do resto (perfil novo cai na tela de escolher tipo de conta)
  Future<void> _entrarComGoogle() async {
    setState(() => _carregandoGoogle = true);
    try {
      await AuthService.instance.entrarComGoogle();
    } on GoogleSignInException catch (e) {
      _mostrarErro('Erro ao entrar com Google: ${e.description ?? e.code}');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'account-exists-with-different-credential') {
        _mostrarErro('Esse e-mail já tem conta com senha. Entre com e-mail e senha.');
      } else {
        _mostrarErro('Erro ao entrar com Google: ${e.message ?? e.code}');
      }
    } catch (e) {
      debugPrint('erro no login com google: $e');
      _mostrarErro('Ocorreu um erro inesperado.');
    } finally {
      if (mounted) setState(() => _carregandoGoogle = false);
    }
  }

  // abre a folha de redefinicao de senha. Ja leva o que a pessoa digitou no
  // campo de e-mail -- quem chegou aqui errando a senha quase sempre ja tem
  // o e-mail certo preenchido
  Future<void> _abrirRecuperarSenha() async {
    final emailEnviado = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? corCardEscuro
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _FolhaRecuperarSenha(emailInicial: _emailController.text.trim()),
    );

    if (emailEnviado == null || !mounted) return;

    // a confirmacao aparece depois da folha fechar, senao o snackbar ficaria
    // escondido atras dela
    _mostrarAviso(
      'Se existir uma conta com $emailEnviado, o link de redefinição chega em instantes.',
      cor: corSucesso,
      icone: Icons.mark_email_read_outlined,
      duracao: const Duration(seconds: 6),
    );
  }

  void _mostrarErro(String msg) {
    _mostrarAviso(msg, cor: corErro, icone: Icons.error_outline);
  }

  void _mostrarAviso(
    String msg, {
    required Color cor,
    required IconData icone,
    Duration duracao = const Duration(seconds: 4),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icone, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: cor,
        behavior: SnackBarBehavior.floating,
        duration: duracao,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _animarElemento(int index, Widget child) {
    return FadeTransition(
      opacity: _fadeAnims[index],
      child: SlideTransition(
        position: _slideAnims[index],
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [corFundoEscuro, const Color(0xFF13202C), const Color(0xFF0A1420)]
                    : [corFundoClaro, const Color(0xFFEAF1F9), const Color(0xFFDDE8F4)],
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _bgController,
            builder: (context, _) {
              return CustomPaint(
                size: size,
                painter: _OrbPainter(
                  progress: _bgController.value,
                  isDark: isDark,
                ),
              );
            },
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28.0),
              child: SizedBox(
                height: size.height - MediaQuery.of(context).padding.top - MediaQuery.of(context).padding.bottom,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(flex: 1),
                    // o texto "Hive" da logo e azul-marinho e some no fundo escuro,
                    // entao o modo escuro usa a variante com o texto claro
                    _animarElemento(0, Center(
                      child: Image.asset(
                        isDark ? 'assets/images/logo_escuro.png' : 'assets/images/logo_claro.png',
                        width: 190,
                        fit: BoxFit.contain,
                      ),
                    )),
                    const SizedBox(height: 28),
                    _animarElemento(1, Column(
                      children: [
                        Text(
                          'O seu novo lar, focado nas suas prioridades.',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.caption.copyWith(
                            color: isDark ? Colors.white54 : Colors.grey.shade600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    )),
                    const SizedBox(height: 40),
                    _animarElemento(2, _buildTextField(
                      controller: _emailController,
                      label: 'Email',
                      icon: Icons.email_outlined,
                      isDark: isDark,
                      keyboardType: TextInputType.emailAddress,
                    )),
                    const SizedBox(height: 16),
                    _animarElemento(3, _buildTextField(
                      controller: _senhaController,
                      label: 'Senha',
                      icon: Icons.lock_outline,
                      isDark: isDark,
                      obscureText: !_senhaVisivel,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _senhaVisivel ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: isDark ? Colors.white38 : Colors.grey,
                        ),
                        onPressed: () => setState(() => _senhaVisivel = !_senhaVisivel),
                      ),
                    )),
                    _animarElemento(3, Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _abrirRecuperarSenha,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                        ),
                        child: Text(
                          'Esqueceu a senha?',
                          style: TextStyle(
                            color: isDark ? corDestaque.withAlpha(220) : corPrimaria.withAlpha(200),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )),
                    const SizedBox(height: 8),
                    _animarElemento(4, AnimatedGradientButton(
                      label: 'Entrar',
                      isLoading: _carregando,
                      onTap: _entrar,
                    )),
                    const SizedBox(height: 24),
                    _animarElemento(5, Row(
                      children: [
                        Expanded(child: Divider(color: isDark ? Colors.white.withAlpha(20) : Colors.grey.shade300)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            'ou',
                            style: TextStyle(
                              color: isDark ? Colors.white30 : Colors.grey.shade400,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Expanded(child: Divider(color: isDark ? Colors.white.withAlpha(20) : Colors.grey.shade300)),
                      ],
                    )),
                    const SizedBox(height: 16),
                    _animarElemento(5, SizedBox(
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: _carregandoGoogle ? null : _entrarComGoogle,
                        icon: _carregandoGoogle
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.g_mobiledata_rounded, size: 28),
                        label: const Text(
                          'Continuar com Google',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? Colors.white70 : Colors.black87,
                          side: BorderSide(
                            color: isDark ? Colors.white.withAlpha(25) : Colors.grey.withAlpha(80),
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99.0)),
                          backgroundColor: isDark ? Colors.white.withAlpha(5) : Colors.white.withAlpha(120),
                        ),
                      ),
                    )),
                    const SizedBox(height: 16),
                    _animarElemento(5, SizedBox(
                      height: 56,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            PageRouteBuilder(
                              pageBuilder: (context, anim1, anim2) => const TelaCadastro(),
                              transitionsBuilder: (context, anim1, anim2, child) {
                                return SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(1, 0),
                                    end: Offset.zero,
                                  ).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic)),
                                  child: child,
                                );
                              },
                              transitionDuration: const Duration(milliseconds: 350),
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: isDark ? Colors.white.withAlpha(25) : corPrimaria.withAlpha(60),
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99.0)),
                          backgroundColor: isDark ? Colors.white.withAlpha(5) : Colors.white.withAlpha(120),
                        ),
                        child: Text(
                          'Criar Conta',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white70 : corPrimaria,
                          ),
                        ),
                      ),
                    )),
                    const Spacer(flex: 3),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isDark,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      style: TextStyle(
        color: isDark ? Colors.white : Colors.black87,
        fontSize: 15,
      ),
      decoration: decoracaoCampo(
        isDark: isDark,
        rotulo: label,
        icone: icon,
        sufixo: suffixIcon,
      ),
    );
  }
}

// folha de "esqueceu a senha": pede o e-mail e dispara o link de redefinicao
// do proprio Firebase.
//
// E uma folha, e nao uma tela empilhada, porque a pessoa esta no meio de uma
// tentativa de login -- ela volta pro mesmo formulario, com o que ja tinha
// digitado, assim que o link sai.
class _FolhaRecuperarSenha extends StatefulWidget {
  final String emailInicial;

  const _FolhaRecuperarSenha({required this.emailInicial});

  @override
  State<_FolhaRecuperarSenha> createState() => _FolhaRecuperarSenhaState();
}

class _FolhaRecuperarSenhaState extends State<_FolhaRecuperarSenha> {
  late final TextEditingController _emailController;
  bool _enviando = false;

  // o erro fica NO campo, nao num snackbar: snackbar sobre folha aberta
  // aparece atras do teclado e some antes da pessoa corrigir
  String? _erro;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.emailInicial);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final email = _emailController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _erro = 'Informe um e-mail válido.');
      return;
    }

    setState(() {
      _enviando = true;
      _erro = null;
    });

    try {
      await AuthService.instance.enviarEmailDeRedefinicaoDeSenha(email);
      if (!mounted) return;
      // quem abriu a folha mostra a confirmacao, ja com a folha fechada
      Navigator.pop(context, email);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      String msg = 'Não foi possível enviar o link agora.';
      if (e.code == 'invalid-email') {
        msg = 'Esse e-mail não parece válido.';
      } else if (e.code == 'user-not-found') {
        // so chega aqui com a protecao contra enumeracao desligada no projeto
        msg = 'Nenhuma conta cadastrada com esse e-mail.';
      } else if (e.code == 'too-many-requests') {
        msg = 'Muitas tentativas seguidas. Aguarde alguns minutos.';
      } else if (e.code == 'network-request-failed') {
        msg = 'Sem conexão. Verifique a internet e tente de novo.';
      }
      setState(() {
        _erro = msg;
        _enviando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Ocorreu um erro inesperado.';
        _enviando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      // sobe junto com o teclado, senao o campo fica embaixo dele
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xxl,
            AppSpacing.md,
            AppSpacing.xxl,
            AppSpacing.xxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withAlpha(30) : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: gradientePrincipal,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: AppShadows.marca(forca: 0.7),
                ),
                child: const Icon(
                  Icons.lock_reset_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Recuperar senha',
                style: AppTextStyles.heading2.copyWith(
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Enviamos um link pro seu e-mail pra você criar uma senha nova.',
                style: AppTextStyles.caption.copyWith(
                  color: isDark ? Colors.white54 : Colors.grey.shade600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                autofocus: widget.emailInicial.isEmpty,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _enviando ? null : _enviar(),
                onChanged: (_) {
                  if (_erro != null) setState(() => _erro = null);
                },
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 15,
                ),
                decoration: decoracaoCampo(
                  isDark: isDark,
                  rotulo: 'Email',
                  icone: Icons.email_outlined,
                ).copyWith(errorText: _erro),
              ),
              const SizedBox(height: AppSpacing.xl),
              AnimatedGradientButton(
                label: 'Enviar link',
                isLoading: _enviando,
                onTap: _enviando ? null : _enviar,
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: TextButton(
                  onPressed: _enviando ? null : () => Navigator.pop(context),
                  child: Text(
                    'Voltar pro login',
                    style: AppTextStyles.captionBold.copyWith(
                      color: isDark ? Colors.white54 : Colors.grey.shade600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final double progress;
  final bool isDark;

  _OrbPainter({required this.progress, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    final orb1X = size.width * 0.8 + sin(progress * 2 * pi) * 30;
    final orb1Y = size.height * 0.15 + cos(progress * 2 * pi) * 20;
    paint.shader = RadialGradient(
      colors: [
        corPrimaria.withAlpha(isDark ? 30 : 20),
        corPrimaria.withAlpha(0),
      ],
    ).createShader(Rect.fromCircle(center: Offset(orb1X, orb1Y), radius: 160));
    canvas.drawCircle(Offset(orb1X, orb1Y), 160, paint);

    final orb2X = size.width * 0.2 + cos(progress * 2 * pi + 1) * 25;
    final orb2Y = size.height * 0.75 + sin(progress * 2 * pi + 1) * 30;
    paint.shader = RadialGradient(
      colors: [
        corPrimaria2.withAlpha(isDark ? 25 : 15),
        corPrimaria2.withAlpha(0),
      ],
    ).createShader(Rect.fromCircle(center: Offset(orb2X, orb2Y), radius: 130));
    canvas.drawCircle(Offset(orb2X, orb2Y), 130, paint);

    final orb3X = size.width * 0.5 + sin(progress * 2 * pi + 2) * 20;
    final orb3Y = size.height * 0.45 + cos(progress * 2 * pi + 2) * 15;
    paint.shader = RadialGradient(
      colors: [
        corDestaque.withAlpha(isDark ? 18 : 12),
        corDestaque.withAlpha(0),
      ],
    ).createShader(Rect.fromCircle(center: Offset(orb3X, orb3Y), radius: 90));
    canvas.drawCircle(Offset(orb3X, orb3Y), 90, paint);
  }

  @override
  bool shouldRepaint(covariant _OrbPainter oldDelegate) =>
      oldDelegate.progress != progress;
}