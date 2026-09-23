import 'package:flutter/material.dart';

/// Reutiliza o layout de cada símbolo durante uma pintura do papel de parede.
/// O cache é local à pintura: não retém fontes nem cores de um tema anterior.
class PintorIconesPadrao {
  PintorIconesPadrao({required this.cor, required this.tamanho});

  final Color cor;
  final double tamanho;
  final Map<IconData, TextPainter> _pintores = {};

  void pintar(Canvas canvas, IconData icone) {
    final pintor = _pintores.putIfAbsent(icone, () {
      return TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icone.codePoint),
          style: TextStyle(
            fontSize: tamanho,
            fontFamily: icone.fontFamily,
            package: icone.fontPackage,
            color: cor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
    pintor.paint(canvas, Offset(-pintor.width / 2, -pintor.height / 2));
  }

  void dispose() {
    for (final pintor in _pintores.values) {
      pintor.dispose();
    }
    _pintores.clear();
  }
}
