import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../main.dart';
import '../widgets/campo_formulario.dart';
import '../services/auth_service.dart';
import '../services/usuario_service.dart';
import '../utils/moderacao.dart';
import '../widgets/animated_gradient_button.dart';

class TelaCadastro extends StatefulWidget {
  const TelaCadastro({super.key});

  @override
  State<TelaCadastro> createState() => _TelaCadastroState();
}

class _TelaCadastroState extends State<TelaCadastro>
    with SingleTickerProviderStateMixin {
  final TextEditingController _nomeController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _senhaController = TextEditingController();
  final TextEditingController _confirmaSenhaController = TextEditingController();

  bool _senhaVisivel = false;
  bool _confirmaSenhaVisivel = false;
  bool _carregando = false;
  bool _carregandoGoogle = false;

  late AnimationController _animController;
  late List<Animation<double>> _fadeAnims;
  late List<Animation<Offset>> _slideAnims;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _fadeAnims = List.generate(7, (i) {
      final start = (i * 0.1).clamp(0.0, 1.0);
      final end = (start + 0.4).clamp(0.0, 1.0);
      return Tween<double>(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _animController, curve: Interval(start, end, curve: Curves.easeOut)),
      );
    });

    _slideAnims = List.generate(7, (i) {
      final start = (i * 0.1).clamp(0.0, 1.0);
      final end = (start + 0.4).clamp(0.0, 1.0);
      return Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(
        CurvedAnimation(parent: _animController, curve: Interval(start, end, curve: Curves.easeOutCubic)),
      );
    });

    _animController.forward();

    // atualiza a barra de forca da senha quando digita
    _senhaController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _emailController.dispose();
    _senhaController.dispose();
    _confirmaSenhaController.dispose();
    _animController.dispose();
    super.dispose();
  }

  double get _forcaSenha {
    final senha = _senhaController.text;
    if (senha.isEmpty) return 0;
    double forca = 0;
    if (senha.length >= 6) forca += 0.25;
    if (senha.length >= 10) forca += 0.15;
    if (RegExp(r'[A-Z]').hasMatch(senha)) forca += 0.2;
    if (RegExp(r'[0-9]').hasMatch(senha)) forca += 0.2;
    if (RegExp(r'[!@#\$%\^\&\*\(\)_\+\-=]').hasMatch(senha)) forca += 0.2;
    return forca.clamp(0.0, 1.0);
  }

  Color get _corForcaSenha {
    if (_forcaSenha < 0.3) return corErro;
    if (_forcaSenha < 0.6) return corAtencao;
    return corSucesso;
  }

  String get _textoForcaSenha {
    if (_senhaController.text.isEmpty) return '';
    if (_forcaSenha < 0.3) return 'Fraca';
    if (_forcaSenha < 0.6) return 'Média';
    if (_forcaSenha < 0.85) return 'Forte';
    return 'Muito forte';
  }

  // cria a conta no firebase e salva os dados extras no firestore
  Future<void> _cadastrar() async {
    final nome = _nomeController.text.trim();
    final email = _emailController.text.trim();
    final senha = _senhaController.text;
    final confirmaSenha = _confirmaSenhaController.text;

    if (nome.isEmpty) {
      _mostrarErro('Informe seu nome completo.');
      return;
    }
    if (!temNomeESobrenome(nome)) {
      _mostrarErro('Informe nome e sobrenome.');
      return;
    }
    if (contemPalavraImpropria(nome)) {
      _mostrarErro('Esse nome contém palavras não permitidas.');
      return;
    }
    if (email.isEmpty || !email.contains('@')) {
      _mostrarErro('Informe um e-mail válido.');
      return;
    }
    if (senha.length < 6) {
      _mostrarErro('A senha deve ter pelo menos 6 caracteres.');
      return;
    }
    if (senha != confirmaSenha) {
      _mostrarErro('As senhas não coincidem.');
      return;
    }

    setState(() => _carregando = true);

    try {
      if (await UsuarioService.instance.nomeJaExiste(nome)) {
        _mostrarErro('Já existe uma conta cadastrada com esse nome.');
        return;
      }

      // cria a conta no authentication
      final credencial = await AuthService.instance.cadastrarComEmailSenha(email, senha);

      // salva o resto dos dados no firestore usando o uid -- tipo de conta e
      // documentos ficam pra tela de "concluir perfil"
      if (credencial.user != null) {
        await UsuarioService.instance.criarPerfil(
          uid: credencial.user!.uid,
          nome: nome,
          email: email,
        );
        await AuthService.instance.enviarEmailDeVerificacao();
      }

      if (!mounted) return;

      // fecha essa tela -- a AuthGate, que fica por baixo, ja assume sozinha
      // e mostra a tela de "confirme seu e-mail"
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on FirebaseAuthException catch (e) {
      // erros comuns do firebase na hora de cadastrar
      String msgErro = 'Erro ao criar conta.';
      if (e.code == 'weak-password') {
        msgErro = 'A senha fornecida é muito fraca.';
      } else if (e.code == 'email-already-in-use') {
        msgErro = 'Já existe uma conta cadastrada com este e-mail.';
      } else if (e.code == 'invalid-email') {
        msgErro = 'O formato do e-mail é inválido.';
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

  // cadastro/login via google -- conta ja vem com e-mail verificado, entao a
  // AuthGate pula direto pra tela de escolher tipo de conta (perfil novo) ou principal
  Future<void> _continuarComGoogle() async {
    setState(() => _carregandoGoogle = true);
    try {
      await AuthService.instance.entrarComGoogle();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on GoogleSignInException catch (e) {
      _mostrarErro('Erro ao entrar com Google: ${e.description ?? e.code}');
    } catch (e) {
      _mostrarErro('Ocorreu um erro inesperado.');
    } finally {
      if (mounted) setState(() => _carregandoGoogle = false);
    }
  }

  void _mostrarErro(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: corErro,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _animarElemento(int index, Widget child) {
    return FadeTransition(
      opacity: _fadeAnims[index],
      child: SlideTransition(position: _slideAnims[index], child: child),
    );
  }

  InputDecoration _inputDeco(String label, IconData icon, bool isDark) {
    return decoracaoCampo(isDark: isDark, rotulo: label, icone: icon);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [corFundoEscuro, const Color(0xFF12101F), const Color(0xFF0D0B18)]
                : [corFundoClaro, const Color(0xFFF0EDFF), const Color(0xFFE8E4FF)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // botao de voltar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(6),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: isDark ? Colors.white : Colors.black87,
                          size: 18,
                        ),
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // formulario
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 28.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 8),

                      _animarElemento(0, Column(
                        children: [
                          Text(
                            'Criar Conta',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.heading1.copyWith(
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Preencha seus dados para começar.',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.caption.copyWith(
                              color: isDark ? Colors.white54 : Colors.grey.shade600,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      )),
                      const SizedBox(height: 24),

                      // foto de perfil
                      _animarElemento(1, Center(
                        child: Stack(
                          children: [
                            Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white.withAlpha(10) : Colors.grey.withAlpha(30),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.person_outline, size: 40, color: isDark ? Colors.white38 : Colors.grey),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Abrindo câmera/galeria...')),
                                  );
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: corPrimaria,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isDark ? const Color(0xFF12101F) : const Color(0xFFF0EDFF),
                                      width: 3,
                                    ),
                                  ),
                                  child: const Icon(Icons.camera_alt_rounded, size: 18, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )),
                      const SizedBox(height: 32),

                      // campo nome
                      _animarElemento(2, TextField(
                        controller: _nomeController,
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                        decoration: _inputDeco('Nome completo', Icons.person_outline, isDark),
                      )),
                      const SizedBox(height: 16),

                      // campo email
                      _animarElemento(3, TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                        decoration: _inputDeco('Email', Icons.email_outlined, isDark),
                      )),
                      const SizedBox(height: 20),

                      // campo senha
                      _animarElemento(4, Column(
                        children: [
                          TextField(
                            controller: _senhaController,
                            obscureText: !_senhaVisivel,
                            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                            decoration: _inputDeco('Senha', Icons.lock_outline, isDark).copyWith(
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _senhaVisivel ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  color: isDark ? Colors.white38 : Colors.grey,
                                ),
                                onPressed: () => setState(() => _senhaVisivel = !_senhaVisivel),
                              ),
                            ),
                          ),
                          // barra de forca da senha
                          if (_senhaController.text.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: _forcaSenha,
                                      minHeight: 4,
                                      backgroundColor: isDark ? Colors.white.withAlpha(12) : Colors.grey.withAlpha(30),
                                      valueColor: AlwaysStoppedAnimation(_corForcaSenha),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  _textoForcaSenha,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _corForcaSenha,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      )),
                      const SizedBox(height: 16),

                      // confirmar senha
                      _animarElemento(5, TextField(
                        controller: _confirmaSenhaController,
                        obscureText: !_confirmaSenhaVisivel,
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                        decoration: _inputDeco('Confirmar senha', Icons.lock_outline, isDark).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _confirmaSenhaVisivel ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: isDark ? Colors.white38 : Colors.grey,
                            ),
                            onPressed: () => setState(() => _confirmaSenhaVisivel = !_confirmaSenhaVisivel),
                          ),
                        ),
                      )),
                      const SizedBox(height: 32),

                      // botao cadastrar
                      _animarElemento(6, AnimatedGradientButton(
                        label: 'Cadastrar',
                        isLoading: _carregando,
                        onTap: _cadastrar,
                      )),
                      const SizedBox(height: 16),
                      _animarElemento(6, Row(
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
                      _animarElemento(6, SizedBox(
                        height: 56,
                        child: OutlinedButton.icon(
                          onPressed: _carregandoGoogle ? null : _continuarComGoogle,
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
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            backgroundColor: isDark ? Colors.white.withAlpha(5) : Colors.white.withAlpha(120),
                          ),
                        ),
                      )),
                      const SizedBox(height: 32),
                    ],
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