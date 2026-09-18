import 'package:flutter/material.dart';

import '../main.dart';

// encolhe levemente enquanto o dedo esta pressionando, e volta ao soltar.
// O GestureDetector puro nao da retorno nenhum: o toque acontece e a tela
// so muda depois, o que faz a interface parecer sem resposta.
//
// Usa AppMotion.rapida de proposito -- retorno ao toque precisa ser quase
// instantaneo. E nunca AppMotion.entrada (overshoot) aqui: elastico em algo
// que o dedo esta segurando passa sensacao de imprecisao.
class Pressionavel extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;

  // quanto encolhe -- 0.96 e o suficiente pra sentir sem parecer que afundou
  final double escala;

  const Pressionavel({
    super.key,
    required this.child,
    this.onTap,
    this.escala = 0.96,
  });

  @override
  State<Pressionavel> createState() => _PressionavelState();
}

class _PressionavelState extends State<Pressionavel> {
  bool _pressionado = false;

  void _mudar(bool valor) {
    if (widget.onTap == null || _pressionado == valor) return;
    setState(() => _pressionado = valor);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _mudar(true),
      onTapUp: (_) => _mudar(false),
      onTapCancel: () => _mudar(false),
      child: AnimatedScale(
        scale: _pressionado ? widget.escala : 1,
        duration: AppMotion.rapida,
        curve: AppMotion.suave,
        child: widget.child,
      ),
    );
  }
}
