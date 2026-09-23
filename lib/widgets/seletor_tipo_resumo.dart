import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../main.dart';

/// Um único destaque acompanha a seleção, inclusive quando o usuário muda
/// de direção antes de a animação terminar.
class SeletorTipoResumo extends StatelessWidget {
  static const opcoes = ['Todos', 'Moradias', 'Eventos'];
  static const _icones = [
    Icons.apps_rounded,
    Icons.home_rounded,
    Icons.celebration_rounded,
  ];

  final String selecionado;
  final ValueChanged<String> onChanged;

  const SeletorTipoResumo({
    super.key,
    required this.selecionado,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final escuro = Theme.of(context).brightness == Brightness.dark;
    final indice = opcoes.indexOf(selecionado).clamp(0, opcoes.length - 1);
    final duracao = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    final estilo = DefaultTextStyle.of(
      context,
    ).style.copyWith(fontSize: 13, fontWeight: FontWeight.w600, height: 1.4);
    final direcao = Directionality.of(context);
    final escala = MediaQuery.textScalerOf(context);
    var larguraTexto = 0.0;
    for (final opcao in opcoes) {
      final medidor = TextPainter(
        text: TextSpan(text: opcao, style: estilo),
        textDirection: direcao,
        textScaler: escala,
      )..layout();
      larguraTexto = math.max(larguraTexto, medidor.width);
      medidor.dispose();
    }
    // Normalmente ocupa toda a largura. Com fonte ampliada, mantém os
    // rótulos completos e permite rolar, como os filtros anteriores.
    final larguraMinima = (larguraTexto + 16 + 6 + 16) * opcoes.length + 4;

    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final largura = math.max(constraints.maxWidth, larguraMinima);
          final altura = math.max(48.0, escala.scale(13) * 1.4 + 20);
          final larguraOpcao = (largura - 4) / opcoes.length;
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              width: largura,
              height: altura,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: escuro
                    ? Colors.black.withAlpha(35)
                    : corPrimaria.withAlpha(10),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Stack(
                children: [
                  AnimatedPositionedDirectional(
                    key: const ValueKey('destaque-tipo-resumo'),
                    duration: duracao,
                    curve: Curves.easeOutCubic,
                    start: indice * larguraOpcao,
                    top: 0,
                    bottom: 0,
                    width: larguraOpcao,
                    child: IgnorePointer(
                      child: AnimatedContainer(
                        duration: duracao,
                        curve: Curves.easeOutCubic,
                        decoration: BoxDecoration(
                          gradient: indice == 2
                              ? gradienteEvento
                              : gradientePrincipal,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.white.withAlpha(32)),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Row(
                      children: [
                        for (var i = 0; i < opcoes.length; i++)
                          Expanded(
                            child: Semantics(
                              selected: i == indice,
                              child: TextButton(
                                onPressed: () {
                                  if (i != indice) onChanged(opcoes[i]);
                                },
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  foregroundColor: i == indice
                                      ? Colors.white
                                      : escuro
                                      ? Colors.white70
                                      : Colors.black54,
                                  textStyle: estilo,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(_icones[i], size: 16),
                                    const SizedBox(width: 6),
                                    Text(opcoes[i]),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
