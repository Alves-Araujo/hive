import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../main.dart';

// Papel de parede das telas de conversa.
//
// A aba de Chat era a unica do app com fundo chapado: entrar numa conversa
// dava a leitura de tela em branco enquanto o resto do app tem mapa, cards e
// gradiente. WhatsApp e Telegram resolvem isso com um padrao atras dos
// baloes, e e o que falta aqui.
//
// Sao TRES camadas, do fundo pra frente:
//   1. gradiente de base, pra tela nao ser uma cor chapada;
//   2. malha de favo -- a marca e uma colmeia (Hive), entao o padrao nao e
//      um xadrez qualquer, e a forma do proprio app;
//   3. desenhos do assunto (casa, chave, pin, onibus, livro) espalhados
//      esparsamente por cima, que e o que da a cara de "papel de parede de
//      mensageiro" em vez de textura generica.
//
// Tudo em alpha muito baixo de proposito: papel de parede que disputa
// atencao com o balao vira ruido e deixa a conversa mais dificil de ler, que
// e exatamente o contrario do que ele esta aqui pra fazer.
class PapelDeParedeChat extends StatelessWidget {
  final Widget child;

  // multiplicador sobre o alpha das duas camadas de padrao. A caixa de
  // entrada usa menos que a conversa: la o conteudo sao cards claros de
  // ponta a ponta, e o padrao aparecendo entre eles pesava
  final double intensidade;

  // so a malha de favo, sem os desenhos -- listas com muito conteudo por
  // item ficam mais limpas so com a textura
  final bool comDesenhos;

  const PapelDeParedeChat({
    super.key,
    required this.child,
    this.intensidade = 1,
    this.comDesenhos = true,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        // RepaintBoundary porque o padrao nunca muda: sem ele, cada mensagem
        // nova (ou cada segundo do cronometro de gravacao) repintaria a
        // malha inteira junto com a lista
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _PapelDeParedePainter(
                isDark: isDark,
                intensidade: intensidade,
                comDesenhos: comDesenhos,
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _PapelDeParedePainter extends CustomPainter {
  final bool isDark;
  final double intensidade;
  final bool comDesenhos;

  _PapelDeParedePainter({
    required this.isDark,
    required this.intensidade,
    required this.comDesenhos,
  });

  // o assunto do app, nao clipart aleatorio: e isso que faz o fundo parecer
  // desenhado pra este app e nao um papel de parede baixado pronto
  static const List<IconData> _desenhos = [
    Icons.home_outlined,
    Icons.vpn_key_outlined,
    Icons.apartment_rounded,
    Icons.place_outlined,
    Icons.bed_outlined,
    Icons.menu_book_outlined,
    Icons.local_cafe_outlined,
    Icons.wifi_rounded,
    Icons.directions_bus_outlined,
    Icons.chat_bubble_outline_rounded,
    Icons.school_outlined,
    Icons.lightbulb_outline_rounded,
  ];

  static const double _ladoFavo = 34;
  static const double _celulaDesenho = 116;

  @override
  void paint(Canvas canvas, Size size) {
    _pintarBase(canvas, size);
    _pintarFavo(canvas, size);
    if (comDesenhos) _pintarDesenhos(canvas, size);
  }

  // um fio do azul da marca descendo -- e o mesmo movimento do CabecalhoTela,
  // pra conversa e cabecalho parecerem a mesma tela
  void _pintarBase(Canvas canvas, Size size) {
    final Color base = isDark ? corFundoEscuro : corFundoClaro;
    final gradiente = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        base,
        Color.alphaBlend(corPrimaria.withAlpha(isDark ? 20 : 12), base),
      ],
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = gradiente.createShader(Offset.zero & size),
    );
  }

  // hexagonos de ponta pra cima, encaixados: o passo horizontal e a largura
  // cheia e o vertical so 3/4 da altura, com as linhas impares deslocadas
  // meia largura -- e isso que fecha o favo sem sobrepor traco
  void _pintarFavo(Canvas canvas, Size size) {
    final traco = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = (isDark ? Colors.white : corPrimaria)
          .withAlpha(_alpha(isDark ? 12 : 16));

    final double largura = math.sqrt(3) * _ladoFavo;
    final double passoVertical = 1.5 * _ladoFavo;

    final int linhas = (size.height / passoVertical).ceil() + 2;
    final int colunas = (size.width / largura).ceil() + 2;

    for (int linha = -1; linha < linhas; linha++) {
      final double y = linha * passoVertical;
      final double recuo = linha.isOdd ? largura / 2 : 0;
      for (int coluna = -1; coluna < colunas; coluna++) {
        canvas.drawPath(
          _hexagono(Offset(coluna * largura + recuo, y), _ladoFavo),
          traco,
        );
      }
    }
  }

  Path _hexagono(Offset centro, double lado) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      // -90 graus como ponto de partida deixa um vertice no topo
      final double angulo = (math.pi / 180) * (60 * i - 90);
      final ponto = Offset(
        centro.dx + lado * math.cos(angulo),
        centro.dy + lado * math.sin(angulo),
      );
      i == 0 ? path.moveTo(ponto.dx, ponto.dy) : path.lineTo(ponto.dx, ponto.dy);
    }
    return path..close();
  }

  // Um desenho a cada duas celulas, mais ou menos, com tamanho e giro
  // sorteados. O sorteio e derivado da posicao da celula (nao de um Random),
  // entao o padrao e SEMPRE o mesmo: com Random, cada repintura embaralharia
  // os desenhos e o fundo pareceria piscar ao girar a tela
  void _pintarDesenhos(Canvas canvas, Size size) {
    final Color cor = (isDark ? Colors.white : corPrimaria)
        .withAlpha(_alpha(isDark ? 16 : 22));

    final int linhas = (size.height / _celulaDesenho).ceil() + 1;
    final int colunas = (size.width / _celulaDesenho).ceil() + 1;

    for (int linha = 0; linha < linhas; linha++) {
      for (int coluna = 0; coluna < colunas; coluna++) {
        final int ruido = _ruido(coluna, linha);
        // deixa ~1/3 das celulas vazias pra o padrao respirar
        if (ruido % 3 == 0) continue;

        final double tamanho = 22 + (ruido % 3) * 5;
        final double giro = -0.32 + ((ruido >> 3) % 7) * 0.105;
        final Offset centro = Offset(
          (coluna + 0.5) * _celulaDesenho + ((ruido >> 6) % 30) - 15,
          (linha + 0.5) * _celulaDesenho + ((ruido >> 11) % 30) - 15,
        );

        canvas.save();
        canvas.translate(centro.dx, centro.dy);
        canvas.rotate(giro);
        _pintarIcone(canvas, _desenhos[ruido % _desenhos.length], tamanho, cor);
        canvas.restore();
      }
    }
  }

  // os icones do Material sao uma fonte: da pra desenhar qualquer um no
  // canvas pintando o caractere dele. Sai muito mais barato (e mais bonito)
  // que redesenhar casa, chave e onibus a mao em Path
  void _pintarIcone(Canvas canvas, IconData icone, double tamanho, Color cor) {
    final pintor = TextPainter(
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
    pintor.paint(canvas, Offset(-pintor.width / 2, -pintor.height / 2));
  }

  int _alpha(int base) => (base * intensidade).round().clamp(0, 255);

  // hash espalhado das coordenadas da celula -- dois primos grandes e um
  // deslocamento bastam pra celulas vizinhas caírem em desenhos diferentes
  int _ruido(int x, int y) {
    int h = (x * 73856093) ^ (y * 19349663);
    h = h ^ (h >> 13);
    return h.abs();
  }

  @override
  bool shouldRepaint(_PapelDeParedePainter anterior) =>
      anterior.isDark != isDark ||
      anterior.intensidade != intensidade ||
      anterior.comDesenhos != comDesenhos;
}
