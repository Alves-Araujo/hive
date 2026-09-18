import 'dart:ui';
import 'package:flutter/material.dart';

import '../main.dart';

// superficie estilo "liquid glass" (o vidro do iOS).
//
// Quatro coisas separam vidro de verdade de um branco translucido, e todas
// estao aqui:
//
// 1. TRANSPARENCIA ALTA -- preenchimento fraco; e o blur que sustenta a
//    legibilidade, nao a opacidade.
// 2. BORDA QUE REFRATA -- quina de cima pega luz forte, o meio escurece, o pe
//    volta a brilhar (luz contornando a peca). Feita com gradiente por baixo
//    + padding, porque o Border do Flutter nao aceita gradiente.
// 3. BRILHO ESPECULAR -- faixa clara na diagonal com corte seco, o reflexo de
//    uma superficie curva.
// 4. ESPESSURA -- hairline INTERNA invertida em relacao a borda externa. O par
//    claro-fora/escuro-dentro e o que o olho le como peca com corpo.
//
// DESEMPENHO -- leia antes de mexer: o BackdropFilter le e desfoca o fundo a
// cada frame, e o GoogleMap do Android e platform view, o que torna isso ainda
// mais caro. Medido neste projeto: 8 superficies desfocando sem parar levaram
// o arraste do mapa a 25% de frames com jank (p90 de 36ms contra o orcamento
// de 16,7ms a 60fps).
//
// Duas defesas, e as duas precisam ficar de pe:
//   a) `mapaEmMovimentoGlobal` solta o blur durante o arraste e devolve na
//      parada. Se isso sair, o mapa volta a travar na hora.
//   b) `comBlur: false` nas pecas pequenas (botao redondo, FAB, chip). Peca
//      pequena le como vidro so com rim + especular; nao vale uma camada de
//      blur inteira por 44px de tela.
// Rim, especular e espessura sao pintura pura -- nao cobram por frame e podem
// ficar sempre ligados.
class GlassCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final double blur;

  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final List<BoxShadow>? sombra;

  // corpo do preenchimento. Baixo de proposito
  final int opacidade;

  // "grossura" do vidro na borda refratada
  final double espessura;

  // false = sem BackdropFilter nenhum. Use nas pecas pequenas
  final bool comBlur;

  // superficie fora do mapa nao precisa soltar o blur no arraste
  final bool soltarBlurEmMovimento;

  const GlassCard({
    super.key,
    required this.child,
    this.radius = AppRadius.lg,
    this.blur = 28,
    this.padding,
    this.margin,
    this.sombra,
    this.opacidade = 96,
    this.espessura = 1.4,
    this.comBlur = true,
    this.soltarBlurEmMovimento = true,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final BorderRadius raio = BorderRadius.circular(radius);
    final BorderRadius raioInterno = BorderRadius.circular(radius - espessura);

    final Widget pintura = _pintura(isDark, raioInterno);

    return Container(
      margin: margin,
      // esse gradiente NAO e o fundo: aparece somente na faixa de `espessura`
      // que sobra em volta do filho, virando a borda refratada
      decoration: BoxDecoration(
        borderRadius: raio,
        gradient: _rim(isDark),
        boxShadow: sombra ?? AppShadows.nivel2(isDark),
      ),
      padding: EdgeInsets.all(espessura),
      child: ClipRRect(
        borderRadius: raioInterno,
        child: !comBlur
            ? pintura
            : soltarBlurEmMovimento
                ? ValueListenableBuilder<bool>(
                    valueListenable: mapaEmMovimentoGlobal,
                    builder: (_, emMovimento, filho) =>
                        emMovimento ? filho! : _comBlur(filho!),
                    child: pintura,
                  )
                : _comBlur(pintura),
      ),
    );
  }

  Widget _comBlur(Widget filho) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: filho,
      );

  // luz contornando a peca. Borda uniforme mata o efeito e le como retangulo
  LinearGradient _rim(bool isDark) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0, 0.32, 0.66, 1],
        colors: isDark
            ? [
                Colors.white.withAlpha(110),
                Colors.white.withAlpha(34),
                Colors.white.withAlpha(18),
                Colors.white.withAlpha(66),
              ]
            : [
                Colors.white.withAlpha(252),
                Colors.white.withAlpha(128),
                Colors.white.withAlpha(82),
                Colors.white.withAlpha(200),
              ],
      );

  Widget _pintura(bool isDark, BorderRadius raio) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: raio,
        // um fio do azul da marca no pe -- o app e azul, entao o vidro tinge
        // de azul, nao de branco morto
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.58, 1],
          colors: isDark
              ? [
                  Colors.white.withAlpha((opacidade * 0.26).round()),
                  Colors.black.withAlpha(52),
                  Color.alphaBlend(corPrimaria.withAlpha(40), Colors.black.withAlpha(58)),
                ]
              : [
                  Colors.white.withAlpha(opacidade),
                  Colors.white.withAlpha((opacidade * 0.84).round()),
                  Color.alphaBlend(
                    corPrimaria.withAlpha(34),
                    Colors.white.withAlpha((opacidade * 0.90).round()),
                  ),
                ],
        ),
      ),
      child: Stack(
        children: [
          // reflexo especular -- IgnorePointer porque e decoracao e nao pode
          // roubar o toque do conteudo
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: raio,
                  gradient: LinearGradient(
                    begin: const Alignment(-1, -1.5),
                    end: const Alignment(0.75, 1),
                    // corte seco: no iOS o reflexo tem limite, nao esfuma pela
                    // peca toda -- esfumado le como degrade, nao como brilho
                    stops: const [0, 0.13, 0.28, 1],
                    colors: [
                      Colors.white.withAlpha(isDark ? 62 : 148),
                      Colors.white.withAlpha(isDark ? 24 : 62),
                      Colors.white.withAlpha(0),
                      Colors.white.withAlpha(0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // espessura: invertida em relacao ao rim de fora
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: raio,
                  border: Border(
                    top: BorderSide(
                      color: isDark ? Colors.black.withAlpha(70) : corPrimaria.withAlpha(26),
                      width: 1,
                    ),
                    bottom: BorderSide(
                      color: Colors.white.withAlpha(isDark ? 34 : 165),
                      width: 1,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ],
      ),
    );
  }
}
