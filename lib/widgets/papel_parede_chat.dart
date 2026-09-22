import 'package:flutter/material.dart';

import '../main.dart';

// Papel de parede das telas de conversa.
//
// A aba de Chat era a unica do app com fundo chapado: entrar numa conversa
// dava a leitura de tela em branco enquanto o resto do app tem mapa, cards e
// gradiente. WhatsApp e Telegram resolvem isso com um padrao atras dos
// baloes, e e o que falta aqui.
//
// Sao DUAS pecas, com trabalhos diferentes:
//
//   PapelDeParedeConversa -- a arte pronta (assets/papel_parede), uma versao
//   por tema. Fundo de tela cheia que nao rola com as mensagens, igual
//   mensageiro: como e imagem, o desenho e exatamente o aprovado, com os
//   blobs, as ondas e os hexagonos da marca no lugar certo.
//
//   PapelDeParedeMiudo -- padrao gerado, para a caixa de entrada. Ali o
//   fundo aparece so nas frestas entre os cards, entao vale mais uma textura
//   fina e uniforme que uma arte com composicao: arte grande picotada por
//   cards parece erro de recorte.
//
// Nos dois casos o alpha e baixo de proposito. Papel de parede que disputa
// atencao com o balao vira ruido e deixa a conversa mais dificil de ler, que
// e o contrario do que ele esta aqui pra fazer.

class PapelDeParedeConversa extends StatelessWidget {
  final Widget child;

  const PapelDeParedeConversa({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      // a cor embaixo cobre o instante antes de a imagem decodificar, e as
      // bordas caso a proporcao da tela nao bata com a da arte
      decoration: BoxDecoration(
        color: isDark ? corFundoEscuro : corFundoClaro,
        image: DecorationImage(
          image: AssetImage(
            isDark
                ? 'assets/papel_parede/conversa_escuro.jpg'
                : 'assets/papel_parede/conversa_claro.jpg',
          ),
          // cover, nao fill: a arte tem proporcao de tela de celular, entao
          // em telas mais largas ela sobra nas laterais em vez de esticar --
          // esticar deformaria os hexagonos da marca, que sao a assinatura
          // do desenho
          fit: BoxFit.cover,
        ),
      ),
      child: child,
    );
  }
}

class PapelDeParedeMiudo extends StatelessWidget {
  final Widget child;

  const PapelDeParedeMiudo({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Stack(
      children: [
        Positioned.fill(
          // ClipRect obrigatorio: um CustomPaint NAO limita o pincel a
          // propria caixa, e o padrao comeca uma celula antes da borda pra
          // nao abrir faixa vazia no topo. Sem o clipe, essas celulas de
          // fora eram pintadas por cima do cabecalho da aba -- a malha
          // aparecia atravessando o titulo e o campo de busca
          child: ClipRect(
            // o padrao nunca muda: sem isso, cada mensagem nova repintaria a
            // textura inteira junto com a lista
            child: RepaintBoundary(
              child: CustomPaint(painter: _PadraoMiudoPainter(isDark: isDark)),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _PadraoMiudoPainter extends CustomPainter {
  final bool isDark;

  _PadraoMiudoPainter({required this.isDark});

  // os mesmos simbolos da arte da conversa, pra as duas telas falarem a
  // mesma lingua: casa, chave, predio, pin, balao e o hexagono da marca
  static const List<IconData> _simbolos = [
    Icons.home_outlined,
    Icons.vpn_key_outlined,
    Icons.apartment_rounded,
    Icons.place_outlined,
    Icons.chat_bubble_outline_rounded,
    Icons.hexagon_outlined,
  ];

  // A celula manda na densidade, e e ela que separa "papel de parede de
  // mensageiro" de "desenhos soltos numa tela vazia".
  //
  // A primeira versao usava 116 px com simbolos de 22 a 32 px: dava uns
  // poucos desenhos grandes, muito espacados, e o fundo parecia inacabado.
  // WhatsApp e Telegram fazem o oposto -- simbolo pequeno, repetido,
  // proximo, ate virar textura em vez de ilustracao
  static const double _celula = 46;
  static const double _tamanhoSimbolo = 17;

  @override
  void paint(Canvas canvas, Size size) {
    _pintarBase(canvas, size);

    final Color cor =
        (isDark ? Colors.white : corPrimaria).withAlpha(isDark ? 12 : 17);

    final int linhas = (size.height / _celula).ceil() + 1;
    final int colunas = (size.width / _celula).ceil() + 1;

    for (int linha = -1; linha < linhas; linha++) {
      for (int coluna = -1; coluna < colunas; coluna++) {
        final int ruido = _ruido(coluna, linha);

        // linhas impares entram meia celula deslocadas: em grade reta o olho
        // acha as colunas na hora e o fundo vira papel quadriculado
        final double recuo = linha.isOdd ? _celula / 2 : 0;
        final Offset centro = Offset(
          coluna * _celula + recuo + _celula / 2,
          linha * _celula + _celula / 2,
        );

        canvas.save();
        canvas.translate(centro.dx, centro.dy);
        // giro pequeno (ate ~9 graus) e so pra tirar o ar de carimbo; giro
        // grande, como o da primeira versao, e o que fazia o padrao parecer
        // bagunçado em vez de trabalhado
        canvas.rotate(-0.16 + (ruido % 5) * 0.08);
        _pintarIcone(canvas, _simbolos[ruido % _simbolos.length], cor);
        canvas.restore();
      }
    }
  }

  // um fio do azul da marca descendo -- o mesmo movimento do CabecalhoTela,
  // pra aba e cabecalho parecerem a mesma tela
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

  // os icones do Material sao uma fonte: da pra desenhar qualquer um no
  // canvas pintando o caractere dele. Sai muito mais barato (e mais bonito)
  // que redesenhar casa, chave e predio a mao em Path
  void _pintarIcone(Canvas canvas, IconData icone, Color cor) {
    final pintor = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icone.codePoint),
        style: TextStyle(
          fontSize: _tamanhoSimbolo,
          fontFamily: icone.fontFamily,
          package: icone.fontPackage,
          color: cor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    pintor.paint(canvas, Offset(-pintor.width / 2, -pintor.height / 2));
  }

  // hash espalhado das coordenadas da celula. Derivado da POSICAO, e nao de
  // um Random: com Random, cada repintura embaralharia os simbolos e o fundo
  // pareceria piscar ao girar a tela
  int _ruido(int x, int y) {
    int h = (x * 73856093) ^ (y * 19349663);
    h = h ^ (h >> 13);
    return h.abs();
  }

  @override
  bool shouldRepaint(_PadraoMiudoPainter anterior) => anterior.isDark != isDark;
}
