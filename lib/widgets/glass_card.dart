import 'package:flutter/material.dart';

import '../main.dart';

// superficie de vidro do app.
//
// POR QUE NAO TEM BackdropFilter AQUI -- leia antes de adicionar um.
//
// No Android o GoogleMap e platform view, e o BackdropFilter precisa ler o
// fundo JA COMPOSTO a cada frame. Isso forca uma sincronizacao com a
// superficie do mapa que nao existe quando o fundo e conteudo Flutter comum.
// Medido neste projeto, arrastando o mapa num Galaxy A9 2018:
//
//   filtros ativos | frames com jank | p90
//   ---------------+-----------------+------
//                0 |             ~5% |  7-9ms
//                1 |          14-18% | 19-21ms
//                2 |             29% |   32ms
//
//   (orcamento a 60fps = 16,7ms)
//
// O custo escala com o NUMERO de filtros, nao com o sigma: baixar de 28 pra
// 14 quase nao mudou nada, porque o preco esta na leitura do fundo e nao no
// desfoque. Mesmo UM filtro estoura o orcamento.
//
// Tentamos tambem soltar o blur so durante o arraste. Resolveu o desempenho
// (~5%) mas criou um salto visivel -- sem blur a peca parece mais
// transparente, com blur parece leitosa -- e dava pra ver a barra "piscando"
// a cada movimento do mapa. Foi rejeitado justamente por isso: qualquer
// diferenca de estado e percebida.
//
// Entao o vidro aqui e feito 100% de pintura, que custa zero por frame:
//
// 1. OPACIDADE MEDIA -- sem desfoque, e ela que garante legibilidade e faz o
//    mapa atras virar uma insinuacao em vez de linhas nitidas competindo com
//    o texto. Por isso e mais alta do que seria com blur.
// 2. BORDA QUE REFRATA -- quina de cima pega luz forte, o meio escurece, o pe
//    volta a brilhar. Gradiente por baixo + padding, porque o Border do
//    Flutter nao aceita gradiente.
// 3. BRILHO ESPECULAR -- faixa clara na diagonal, com corte seco. No iOS o
//    reflexo tem limite definido; esfumado le como degrade, nao como brilho.
// 4. ESPESSURA -- hairline INTERNA invertida em relacao a externa. O par
//    claro-fora/escuro-dentro e o que o olho le como peca com corpo.
//
// Sem o desfoque, 2/3/4 passam a carregar o efeito sozinhas -- e por isso
// estao mais fortes aqui do que estariam acompanhadas de blur.
class GlassCard extends StatelessWidget {
  final Widget child;
  final double radius;

  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final List<BoxShadow>? sombra;

  // corpo do preenchimento (0-255). Sem blur, abaixo de ~150 o mapa atras
  // comeca a competir com o texto -- por isso fica alto
  final int opacidade;

  // "grossura" do vidro na borda refratada
  final double espessura;

  // cor base do preenchimento. null = branco (claro) / corCardEscuro (escuro).
  // O card de rota usa um azul escuro pra combinar com a paleta do mapa
  final Color? corBase;

  const GlassCard({
    super.key,
    required this.child,
    this.radius = AppRadius.lg,
    this.padding,
    this.margin,
    this.sombra,
    this.opacidade = 212,
    this.espessura = 1.4,
    this.corBase,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final BorderRadius raio = BorderRadius.circular(radius);
    final BorderRadius raioInterno = BorderRadius.circular(radius - espessura);

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
        child: _interior(isDark, raioInterno),
      ),
    );
  }

  LinearGradient _rim(bool isDark) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        stops: const [0, 0.30, 0.64, 1],
        colors: isDark
            ? [
                Colors.white.withAlpha(132),
                Colors.white.withAlpha(42),
                Colors.white.withAlpha(22),
                Colors.white.withAlpha(78),
              ]
            : [
                // era branco puro aqui e 224 no pe, o que desenhava um
                // contorno branco visivel em volta da peca. Agora e so uma
                // insinuacao de quina iluminada
                Colors.white.withAlpha(118),
                Colors.white.withAlpha(64),
                Colors.white.withAlpha(44),
                Colors.white.withAlpha(86),
              ],
      );

  Widget _interior(bool isDark, BorderRadius raio) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: raio,
        // tres paradas: vidro real nao escurece de forma linear, e a do meio
        // mais fraca cria a faixa de luz que atravessa a peca
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.56, 1],
          colors: isDark
              ? [
                  Color.alphaBlend(Colors.white.withAlpha(30), corCardEscuro.withAlpha(opacidade)),
                  corCardEscuro.withAlpha((opacidade * 0.94).round()),
                  Color.alphaBlend(corPrimaria.withAlpha(30), corCardEscuro.withAlpha(opacidade)),
                ]
              : [
                  (corBase ?? Colors.white).withAlpha(opacidade),
                  (corBase ?? Colors.white).withAlpha((opacidade * 0.92).round()),
                  Color.alphaBlend(
                    corPrimaria.withAlpha(20),
                    (corBase ?? Colors.white).withAlpha((opacidade * 0.96).round()),
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
                    stops: const [0, 0.12, 0.27, 1],
                    colors: [
                      Colors.white.withAlpha(isDark ? 74 : 176),
                      Colors.white.withAlpha(isDark ? 30 : 74),
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
                      color: isDark ? Colors.black.withAlpha(80) : corPrimaria.withAlpha(30),
                      width: 1,
                    ),
                    bottom: BorderSide(
                      color: Colors.white.withAlpha(isDark ? 40 : 96),
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
