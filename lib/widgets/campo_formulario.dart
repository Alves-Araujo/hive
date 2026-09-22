import 'package:flutter/material.dart';

import '../main.dart';

// decoracao padrao dos campos de formulario do app.
//
// Existe porque login, cadastro, concluir perfil e novo anuncio tinham cada
// um a SUA copia dessa decoracao, escrita na mao. Quatro copias que ja tinham
// divergido em raio, cor de preenchimento e espessura de borda -- e que
// obrigariam a repetir qualquer ajuste quatro vezes.
//
// Segue o mesmo vocabulario do resto: superficie do app (nao branco puro),
// raio dos tokens, azul da marca no foco.
InputDecoration decoracaoCampo({
  required bool isDark,
  String? rotulo,
  String? dica,
  IconData? icone,
  Widget? sufixo,

  // texto fixo colado antes do que a pessoa digita ("R$ " nos campos de
  // dinheiro). So aparece com o campo em foco ou ja preenchido, que e o
  // comportamento do proprio InputDecorator
  String? prefixoTexto,

  // campo de uma linha usa pilula; campo de varias linhas fica estranho em
  // pilula, entao aceita raio menor
  double raio = AppRadius.md + 6,
}) {
  OutlineInputBorder borda(Color cor, double espessura) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(raio),
        borderSide: BorderSide(color: cor, width: espessura),
      );

  return InputDecoration(
    labelText: rotulo,
    hintText: dica,
    labelStyle: TextStyle(
      color: isDark ? Colors.white38 : Colors.grey.shade600,
      fontWeight: FontWeight.w500,
    ),
    hintStyle: TextStyle(
      color: isDark ? Colors.white30 : Colors.black38,
      fontWeight: FontWeight.w400,
    ),
    prefixIcon: icone == null
        ? null
        : Icon(icone, color: isDark ? Colors.white54 : corPrimaria.withAlpha(170), size: 21),
    suffixIcon: sufixo,
    prefixText: prefixoTexto,
    prefixStyle: TextStyle(
      color: isDark ? Colors.white70 : Colors.black87,
      fontWeight: FontWeight.w600,
    ),
    border: borda(Colors.transparent, 0),
    enabledBorder: borda(
      isDark ? Colors.white.withAlpha(20) : corPrimaria.withAlpha(24),
      1,
    ),
    focusedBorder: borda(corPrimaria, 1.6),
    errorBorder: borda(corErro.withAlpha(140), 1),
    focusedErrorBorder: borda(corErro, 1.6),
    filled: true,
    // superficie do app, nao branco puro -- mesma razao das barras do mapa
    fillColor: isDark ? Colors.white.withAlpha(12) : superficieClara,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.xl,
      vertical: AppSpacing.lg + 2,
    ),
  );
}
