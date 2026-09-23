import 'package:flutter/material.dart';

import '../main.dart';
import '../utils/pintor_icones_padrao.dart';
import '../models/imovel.dart';

// Papel de parede miudo da aba Resumo, irmao do PapelDeParedeMiudo em
// papel_parede_chat.dart -- mesma textura de simbolos repetidos atras da
// lista, so que aqui o simbolo muda com o chip selecionado: "Todos" mistura
// moradia e evento, "Moradias" e "Eventos" mostram so a familia do proprio
// filtro. Reforca visualmente em qual aba a pessoa esta sem precisar reler o
// chip la em cima.
class PapelDeParedeResumo extends StatelessWidget {
  final TipoListing? tipo; // null = Todos
  final Widget child;

  const PapelDeParedeResumo({
    super.key,
    required this.tipo,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        Positioned.fill(
          // mesmo motivo do papel de parede do chat: sem o ClipRect o
          // CustomPaint pinta uma celula alem da borda e a malha vaza por
          // cima do cabecalho com os chips
          child: ClipRect(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _PadraoResumoPainter(isDark: isDark, tipo: tipo),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _PadraoResumoPainter extends CustomPainter {
  final bool isDark;
  final TipoListing? tipo;

  _PadraoResumoPainter({required this.isDark, required this.tipo});

  // mesma familia usada no papel de parede do chat, pra "Moradias" falar a
  // mesma lingua visual em qualquer aba do app
  static const List<IconData> _simbolosMoradia = [
    Icons.home_outlined,
    Icons.vpn_key_outlined,
    Icons.apartment_rounded,
    Icons.place_outlined,
    Icons.hexagon_outlined,
  ];

  static const List<IconData> _simbolosEvento = [
    Icons.celebration_outlined,
    Icons.confirmation_number_outlined,
    Icons.event_outlined,
    Icons.local_activity_outlined,
    Icons.hexagon_outlined,
  ];

  List<IconData> get _simbolos => switch (tipo) {
    TipoListing.moradia => _simbolosMoradia,
    TipoListing.evento => _simbolosEvento,
    // Todos: as duas familias juntas, hexagono da marca uma vez so
    null => [..._simbolosMoradia.take(4), ..._simbolosEvento],
  };

  Color get _corDestaque =>
      tipo == TipoListing.evento ? corEvento : corPrimaria;

  static const double _celula = 46;
  static const double _tamanhoSimbolo = 17;

  @override
  void paint(Canvas canvas, Size size) {
    _pintarBase(canvas, size);

    final Color cor = (isDark ? Colors.white : _corDestaque).withAlpha(
      isDark ? 12 : 17,
    );
    final List<IconData> simbolos = _simbolos;

    final int linhas = (size.height / _celula).ceil() + 1;
    final int colunas = (size.width / _celula).ceil() + 1;

    final pintor = PintorIconesPadrao(cor: cor, tamanho: _tamanhoSimbolo);
    try {
      for (int linha = -1; linha < linhas; linha++) {
        for (int coluna = -1; coluna < colunas; coluna++) {
          final int ruido = _ruido(coluna, linha);

          final double recuo = linha.isOdd ? _celula / 2 : 0;
          final Offset centro = Offset(
            coluna * _celula + recuo + _celula / 2,
            linha * _celula + _celula / 2,
          );

          canvas.save();
          canvas.translate(centro.dx, centro.dy);
          canvas.rotate(-0.16 + (ruido % 5) * 0.08);
          pintor.pintar(canvas, simbolos[ruido % simbolos.length]);
          canvas.restore();
        }
      }
    } finally {
      pintor.dispose();
    }
  }

  void _pintarBase(Canvas canvas, Size size) {
    final Color base = isDark ? corFundoEscuro : corFundoClaro;
    final gradiente = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        base,
        Color.alphaBlend(_corDestaque.withAlpha(isDark ? 20 : 12), base),
      ],
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = gradiente.createShader(Offset.zero & size),
    );
  }

  int _ruido(int x, int y) {
    int h = (x * 73856093) ^ (y * 19349663);
    h = h ^ (h >> 13);
    return h.abs();
  }

  @override
  bool shouldRepaint(_PadraoResumoPainter anterior) =>
      anterior.isDark != isDark || anterior.tipo != tipo;
}
