import 'package:flutter/material.dart';

/// Mantem as telas montadas e faz a passagem nos dois sentidos.
/// Somente a camada Flutter acima recebe fade; o mapa nunca e animado.
class AbasPersistentes extends StatefulWidget {
  final int indice;
  final List<Widget> telas;

  const AbasPersistentes({
    super.key,
    required this.indice,
    required this.telas,
  });

  @override
  State<AbasPersistentes> createState() => _AbasPersistentesState();
}

class _AbasPersistentesState extends State<AbasPersistentes>
    with SingleTickerProviderStateMixin {
  int? _anterior;
  late final AnimationController _transicao = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: 1,
  )..addStatusListener(_aoTerminar);
  late final CurvedAnimation _entrada = CurvedAnimation(
    parent: _transicao,
    curve: Curves.easeInOut,
  );
  late final Animation<double> _saida = ReverseAnimation(_entrada);

  void _aoTerminar(AnimationStatus status) {
    if (status == AnimationStatus.completed && _anterior != null && mounted) {
      setState(() => _anterior = null);
    }
  }

  @override
  void didUpdateWidget(AbasPersistentes oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.indice == widget.indice) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _anterior = null;
      _transicao.value = 1;
      return;
    }

    // Voltar antes de acabar reverte do ponto atual, sem reiniciar o brilho.
    // A curva simetrica mantem a opacidade continua nessa inversao.
    final inicio = widget.indice == _anterior && _transicao.isAnimating
        ? 1 - _transicao.value
        : 0.0;
    _anterior = oldWidget.indice;
    _transicao.forward(from: inicio);
  }

  @override
  void dispose() {
    _transicao.removeStatusListener(_aoTerminar);
    _entrada.dispose();
    _transicao.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A ordem e fixa para nao remontar telas. A pagina de cima aparece ou
    // desaparece sobre a de baixo. Na volta ao mapa, Resumo/Chat se apagam
    // sobre ele; na ida, aparecem sobre ele. Sem opacity na platform view.
    final camadaSuperior = _anterior == null
        ? null
        : (widget.indice > _anterior! ? widget.indice : _anterior!);

    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < widget.telas.length; i++)
          Offstage(
            offstage: i != widget.indice && i != _anterior,
            child: IgnorePointer(
              ignoring: i != widget.indice,
              child: ExcludeSemantics(
                excluding: i != widget.indice,
                child: TickerMode(
                  enabled: i == widget.indice,
                  child: i == 0
                      ? widget.telas[i]
                      : FadeTransition(
                          opacity: i == camadaSuperior
                              ? (i == widget.indice ? _entrada : _saida)
                              : const AlwaysStoppedAnimation(1),
                          child: RepaintBoundary(
                            child: ColoredBox(
                              // Cobre a pagina inteira, inclusive o espaco
                              // vazio de listas, sem corte na volta ao mapa.
                              color: Theme.of(context).scaffoldBackgroundColor,
                              child: widget.telas[i],
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
