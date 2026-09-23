import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../main.dart';
import '../models/passo_guia.dart';
import '../utils/alvos_tutorial.dart';
import '../utils/observador_rotas.dart';
import 'pressionavel.dart';

// Guia por cima do app de verdade: escurece a tela, abre um furo no botao do
// passo e explica ao lado dele.
//
// O furo nao e enfeite -- o toque PASSA por ele. A pessoa toca no botao real,
// ve o que acontece (a aba troca, a folha abre) e o guia segue dali. Era isso
// que faltava na versao em slides: ela contava o app em vez de mostrar.
//
// Nao existe caminho sem saida: todo passo tem "Próximo", e "Sair do guia"
// aparece o tempo todo. Quem tocar fora do furo nao muda de tela por acidente
// (as barreiras seguram o toque), que e o que mantem o guia e a tela falando
// da mesma coisa.
class GuiaInterativo extends StatefulWidget {
  final List<PassoGuia> passos;

  // troca a aba da barra de baixo. Usado quando o passo fala de outra aba e a
  // pessoa prefere o "Próximo" em vez de tocar na aba acesa
  final ValueChanged<int> onTrocarAba;

  final VoidCallback onConcluir;

  const GuiaInterativo({
    super.key,
    required this.passos,
    required this.onTrocarAba,
    required this.onConcluir,
  });

  @override
  State<GuiaInterativo> createState() => _GuiaInterativoState();
}

class _GuiaInterativoState extends State<GuiaInterativo>
    with SingleTickerProviderStateMixin {
  int _indice = 0;

  // trava contra avancar duas vezes com o mesmo toque: o furo deixa o evento
  // passar pro botao de baixo, e um toque rapido pode render mais de um
  // onPointerUp antes do proximo frame
  bool _avancando = false;

  late final AnimationController _pulso = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  PassoGuia get _passo => widget.passos[_indice];
  bool get _ultimo => _indice >= widget.passos.length - 1;

  @override
  void initState() {
    super.initState();
    // o retangulo do alvo so existe depois que a tela se desenhou uma vez
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _pulso.stop();
      _pulso.value = 0;
    } else if (!_pulso.isAnimating) {
      _pulso.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulso.dispose();
    super.dispose();
  }

  void _avancar({bool porToque = false}) {
    if (_avancando) return;
    _avancando = true;

    final passo = _passo;
    // pelo "Próximo" o guia troca de aba sozinho; pelo toque quem trocou foi a
    // propria pessoa, no botao de verdade
    if (!porToque && passo.abaParaAbrir != null) {
      widget.onTrocarAba(passo.abaParaAbrir!);
    }

    if (_ultimo) {
      widget.onConcluir();
      return;
    }

    setState(() => _indice++);
    // o alvo do passo novo pode estar noutra aba, que acabou de entrar: mede
    // depois que o frame terminar, senao o furo sai no lugar velho
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _avancando = false;
      setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: mudancasDeRota,
      builder: (context, _, _) {
        // some enquanto uma folha ou outra tela esta por cima (filtros,
        // perfil, formulario de anuncio) e volta sozinho quando ela fecha
        final bool naFrente = ModalRoute.of(context)?.isCurrent ?? true;
        if (!naFrente) return const SizedBox.shrink();
        return _camada(context);
      },
    );
  }

  Widget _camada(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Size tela = MediaQuery.sizeOf(context);

    final Rect? alvo = rectDoAlvo(_passo.alvo);
    // o furo e um pouco maior que o botao: colado na borda ele parece um
    // recorte torto em vez de um destaque
    final Rect? furo = alvo == null
        ? null
        : Rect.fromLTRB(
            math.max(0, alvo.left - 8),
            math.max(0, alvo.top - 8),
            math.min(tela.width, alvo.right + 8),
            math.min(tela.height, alvo.bottom + 8),
          );

    // alvo redondo (avatar, botao de localizacao) pede furo redondo; o resto
    // fica com canto arredondado
    final double raio = furo == null
        ? 0
        : ((furo.width - furo.height).abs() < 12
              ? math.max(furo.width, furo.height) / 2
              : AppRadius.lg);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _pulso,
                builder: (_, _) => CustomPaint(
                  painter: _PinturaDoFuro(
                    furo: furo,
                    raio: raio,
                    pulso: _pulso.value,
                    isDark: isDark,
                  ),
                ),
              ),
            ),
          ),
          ..._barreiras(furo, tela),
          if (furo != null && !_passo.abreOutraTela)
            // translucido: o toque chega no botao de baixo E chega aqui. E o
            // que faz "toque em Resumo" trocar de aba de verdade e o guia
            // seguir junto
            Positioned.fromRect(
              rect: furo,
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerUp: (_) => _avancar(porToque: true),
              ),
            ),
          _cartao(context, isDark, furo, tela),
        ],
      ),
    );
  }

  // quatro retangulos em volta do furo. Seguram o toque fora dele pra ninguem
  // sair navegando no meio do guia -- e deixam o furo livre, sem nada por cima
  List<Widget> _barreiras(Rect? furo, Size tela) {
    Widget bloqueio() => GestureDetector(
      behavior: HitTestBehavior.opaque,
      // tocar no escuro nao avanca: seria fácil pular um passo sem querer
      onTap: () {},
    );

    if (furo == null) {
      return [Positioned.fill(child: bloqueio())];
    }

    return [
      Positioned(left: 0, right: 0, top: 0, height: furo.top, child: bloqueio()),
      Positioned(
        left: 0,
        right: 0,
        top: furo.bottom,
        height: math.max(0, tela.height - furo.bottom),
        child: bloqueio(),
      ),
      Positioned(
        left: 0,
        width: furo.left,
        top: furo.top,
        height: furo.height,
        child: bloqueio(),
      ),
      Positioned(
        left: furo.right,
        width: math.max(0, tela.width - furo.right),
        top: furo.top,
        height: furo.height,
        child: bloqueio(),
      ),
    ];
  }

  Widget _cartao(BuildContext context, bool isDark, Rect? furo, Size tela) {
    final EdgeInsets recuo = MediaQuery.paddingOf(context);
    const double margem = AppSpacing.lg;
    const double respiro = AppSpacing.md + 2;

    final double limiteTopo = recuo.top + AppSpacing.sm;
    final double limiteBase = recuo.bottom + AppSpacing.sm;

    Widget posicionar(Widget cartao) {
      if (furo == null) {
        return Positioned(
          left: margem,
          right: margem,
          top: limiteTopo,
          bottom: limiteBase,
          child: Center(child: cartao),
        );
      }

      final double espacoAbaixo = tela.height - furo.bottom - limiteBase - respiro;
      final double espacoAcima = furo.top - limiteTopo - respiro;
      // fica do lado em que cabe mais: alvo no topo (busca, avatar) joga o
      // cartao pra baixo, alvo na barra de baixo joga pra cima
      final bool abaixo = espacoAbaixo >= espacoAcima;

      return Positioned(
        left: margem,
        right: margem,
        top: abaixo ? furo.bottom + respiro : limiteTopo,
        bottom: abaixo ? limiteBase : tela.height - furo.top + respiro,
        child: Align(
          alignment: abaixo ? Alignment.topCenter : Alignment.bottomCenter,
          child: cartao,
        ),
      );
    }

    return posicionar(
      Container(
        decoration: BoxDecoration(
          color: isDark ? corCardEscuro : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: AppShadows.nivel3(isDark),
        ),
        // o texto rola quando nao cabe (fonte grande, aparelho baixo) em vez
        // de estourar o cartao
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_indice + 1} de ${widget.passos.length}',
                style: AppTextStyles.label.copyWith(
                  color: isDark ? Colors.white38 : Colors.grey,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _passo.titulo,
                style: AppTextStyles.heading3.copyWith(
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _passo.texto,
                style: AppTextStyles.body.copyWith(
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Pressionavel(
                    onTap: widget.onConcluir,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.sm,
                      ),
                      child: Text(
                        'Sair do guia',
                        style: AppTextStyles.captionBold.copyWith(
                          color: isDark ? Colors.white54 : Colors.grey.shade600,
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Pressionavel(
                    onTap: _avancar,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                        vertical: AppSpacing.md,
                      ),
                      decoration: BoxDecoration(
                        gradient: gradientePrincipal,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        boxShadow: AppShadows.marca(forca: 0.6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _ultimo ? 'Entendi' : 'Próximo',
                            style: AppTextStyles.captionBold.copyWith(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs + 2),
                          Icon(
                            _ultimo
                                ? Icons.check_rounded
                                : Icons.arrow_forward_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinturaDoFuro extends CustomPainter {
  final Rect? furo;
  final double raio;
  final double pulso;
  final bool isDark;

  _PinturaDoFuro({
    required this.furo,
    required this.raio,
    required this.pulso,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint escuro = Paint()
      ..color = Colors.black.withAlpha(isDark ? 190 : 160);

    if (furo == null) {
      canvas.drawRect(Offset.zero & size, escuro);
      return;
    }

    final RRect recorte = RRect.fromRectAndRadius(
      furo!,
      Radius.circular(raio),
    );

    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(recorte),
      ),
      escuro,
    );

    // anel que respira em volta do furo: sem ele o buraco no escuro parece
    // falha de desenho, e nao "toque aqui"
    canvas.drawRRect(
      recorte.inflate(2 + pulso * 5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = corDestaque.withAlpha((170 - pulso * 110).round()),
    );
  }

  @override
  bool shouldRepaint(_PinturaDoFuro anterior) =>
      anterior.furo != furo ||
      anterior.raio != raio ||
      anterior.pulso != pulso ||
      anterior.isDark != isDark;
}
