import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../main.dart';
import '../models/imovel.dart';

// pins do mapa desenhados em Canvas, nao carregados de PNG.
//
// Por que desenhar em vez de usar imagem: o marker sai na densidade real do
// aparelho (nada de borrado em tela de alta densidade), segue a paleta do app
// sem manter arquivo separado em sincronia, e muda de cor/icone trocando um
// parametro. Um PNG teria que existir em 3 resolucoes e ser reexportado a
// cada ajuste de cor.
//
// O desenho fica em cache por tipo: sao poucos pins diferentes e recriar o
// bitmap a cada rebuild da lista de marcadores seria desperdicio.
//
// Cada tipo de anuncio tem cor E icone proprios: de longe a cor separa, de
// perto o icone confirma. Hotel, mercado e farmacia ainda nao tem cadastro,
// mas o pin ja existe -- quando o tipo for criado basta gravar o nome em
// tipoImovel que tipoPinDoImovel() resolve sozinho.
enum TipoPin {
  casa,
  apartamento,
  kitnet,
  republica,
  pensao,
  hotel,
  mercado,
  farmacia,
  evento,
  faculdade,
  imobiliaria,
}

// escolhe o pin pelo campo "Tipo" do anuncio. Compara sem acento e sem
// caixa porque o valor vem do banco e anuncio antigo pode ter sido gravado
// com grafia diferente.
//
// Anuncio anterior ao campo tipoImovel nao tem o tipo gravado nele: o tipo
// ia como tag ("República", "Kitnet"...). Sem olhar as tags, todos esses
// saiam com o pin de casa. Sem tipo em nenhum dos dois, cai na casa, que era
// o pin unico de moradia antes
TipoPin tipoPinDoImovel(Imovel imovel) {
  if (imovel.tipo == TipoListing.evento) return TipoPin.evento;
  final porCampo = _tipoPinPorNome(imovel.tipoImovel);
  if (porCampo != null) return porCampo;
  for (final tag in imovel.tags) {
    final porTag = _tipoPinPorNome(tag);
    if (porTag != null) return porTag;
  }
  return TipoPin.casa;
}

TipoPin? _tipoPinPorNome(String nome) =>
    switch (_semAcento(nome.trim().toLowerCase())) {
      'casa' => TipoPin.casa,
      'apartamento' => TipoPin.apartamento,
      'kitnet' => TipoPin.kitnet,
      'republica' => TipoPin.republica,
      'pensao' => TipoPin.pensao,
      'hotel' => TipoPin.hotel,
      'mercado' || 'supermercado' => TipoPin.mercado,
      'farmacia' || 'drogaria' => TipoPin.farmacia,
      _ => null,
    };

String _semAcento(String s) => s
    .replaceAll(RegExp('[áàâã]'), 'a')
    .replaceAll(RegExp('[éê]'), 'e')
    .replaceAll('í', 'i')
    .replaceAll(RegExp('[óôõ]'), 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ç', 'c');

class PinsMapa {
  static final Map<String, BitmapDescriptor> _cache = {};

  static Future<BitmapDescriptor> obter(TipoPin tipo, double densidade, {bool isOrigem = false, bool isDestino = false}) async {
    final chave = '${tipo.name}_${densidade.toStringAsFixed(1)}_o$isOrigem\_d$isDestino';
    final emCache = _cache[chave];
    if (emCache != null) return emCache;

    final gerado = await _desenhar(tipo, densidade, isOrigem: isOrigem, isDestino: isDestino);
    _cache[chave] = gerado;
    return gerado;
  }

  static (List<Color>, IconData, double) _estilo(TipoPin tipo) => switch (tipo) {
        // casa: azul da marca, o caso mais comum no mapa e o padrao pra
        // anuncio sem tipo
        TipoPin.casa => (
            const [Color(0xFF1C5A8F), Color(0xFF12294A)],
            Icons.home_rounded,
            1.0,
          ),
        // apartamento: indigo, vizinho do azul da casa -- os dois sao
        // moradia "comum", so muda o predio no lugar da casa
        TipoPin.apartamento => (
            const [Color(0xFF34458F), Color(0xFF171F4A)],
            Icons.apartment_rounded,
            1.0,
          ),
        // kitnet: cinza-azulado, mesma familia fria das moradias
        TipoPin.kitnet => (
            const [Color(0xFF4A5F6B), Color(0xFF1D282E)],
            Icons.door_back_door_rounded,
            1.0,
          ),
        // republica: vinho. Ja foi laranja, mas chamava atencao demais perto
        // dos tons escuros do resto do mapa -- toda a paleta fica fechada e
        // quem diferencia e a matiz, nao o brilho
        TipoPin.republica => (
            const [Color(0xFF8A2D4B), Color(0xFF3B0F1F)],
            Icons.groups_rounded,
            1.0,
          ),
        // pensao: marrom, quarto com refeicao -- a cama diz "quarto", nao casa
        TipoPin.pensao => (
            const [Color(0xFF6E4E3C), Color(0xFF2E1E15)],
            Icons.bed_rounded,
            1.0,
          ),
        // hotel: dourado, estadia curta
        TipoPin.hotel => (
            const [Color(0xFF8F7418), Color(0xFF3D3000)],
            Icons.hotel_rounded,
            1.0,
          ),
        // mercado: verde-oliva. Nao usa o verde puro porque esse e o pin de
        // origem da rota
        TipoPin.mercado => (
            const [Color(0xFF52752B), Color(0xFF223512)],
            Icons.shopping_cart_rounded,
            1.0,
          ),
        // farmacia: vermelho fechado, puxando a cor das redes de farmacia. Bem
        // mais escuro que o vermelho vivo do pin de destino
        TipoPin.farmacia => (
            const [Color(0xFF9E3030), Color(0xFF450F0F)],
            Icons.local_pharmacy_rounded,
            1.0,
          ),
        // evento: roxo escuro. Distingue de moradia sem berrar como o
        // ambar/vermelho anterior, que puxava atencao demais pro que e
        // excecao na tela, e segura melhor o icone branco por cima
        TipoPin.evento => (
            const [Color(0xFF6D3FA8), Color(0xFF2F1A52)],
            Icons.celebration_rounded,
            1.0,
          ),
        // faculdade: azul vivo, a cor do Inatel. Toda a busca orbita a
        // faculdade, entao ela e o ponto de destaque: os anuncios ficam todos
        // em tons fechados justamente pra ela saltar. Casa e apartamento
        // tambem sao azuis, entao o que separa aqui e o brilho -- este azul
        // (o corPrimaria2 do app) e bem mais claro que o deles. Um pouco
        // maior pelo mesmo motivo
        TipoPin.faculdade => (
            const [Color(0xFF007BFF), Color(0xFF00509E)],
            Icons.school_rounded,
            1.15,
          ),
        // imobiliaria: verde-azulado escuro, a cor que era da faculdade. Nao
        // e anuncio (nao entra nos filtros de preco/tag) -- e uma empresa, e
        // precisa de uma cor propria pra nao ser lida como moradia. O icone
        // de corretor (casa com chave) nao repete o predio, que e o pin de
        // apartamento
        TipoPin.imobiliaria => (
            const [Color(0xFF0E7C7B), Color(0xFF07403F)],
            Icons.real_estate_agent_rounded,
            1.05,
          ),
      };

  static Future<BitmapDescriptor> _desenhar(TipoPin tipo, double densidade,
      {bool isOrigem = false, bool isDestino = false}) async {
    final imagem = await desenharImagem(tipo, densidade,
        isOrigem: isOrigem, isDestino: isDestino);
    final bytes = await imagem.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.bytes(
      bytes!.buffer.asUint8List(),
      imagePixelRatio: densidade,
    );
  }

  // o desenho cru, antes de virar marcador. Separado pra dar pra conferir o
  // pin sem precisar de um mapa na tela -- ver test/pins_mapa_test.dart
  static Future<ui.Image> desenharImagem(TipoPin tipo, double densidade,
      {bool isOrigem = false, bool isDestino = false}) async {
    var (cores, icone, escala) = _estilo(tipo);

    if (isOrigem) {
      cores = const [Color(0xFF2E7D32), Color(0xFF1B5E20)];
    } else if (isDestino) {
      cores = const [Color(0xFFD32F2F), Color(0xFFB71C1C)];
    }

    // medidas em pixels logicos, multiplicadas pela densidade no fim
    const double raio = 15.5;
    const double alturaCauda = 14;
    const double borda = 2.1;
    const double margem = 4; // espaco pra sombra nao ser cortada

    final double r = raio * escala;
    final double cauda = alturaCauda * escala;
    final double larguraL = (r + borda + margem) * 2;
    // a altura tem que contar o DIAMETRO (2r) e nao o raio: a ponta fica
    // `cauda` ABAIXO da borda inferior do circulo, nao abaixo do centro --
    // com r > cauda a ponta caia dentro do proprio circulo e o pin saia
    // redondo, sem bico
    final double alturaL = margem * 2 + borda * 2 + 2 * r + cauda;

    final double d = densidade;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(d);

    final Offset centro = Offset(larguraL / 2, margem + borda + r);
    final Offset ponta = Offset(larguraL / 2, centro.dy + r + cauda);

    // FORMATO DE GOTA POR TANGENTES -- nao por curvas chutadas.
    //
    // Tentei antes com bezier e pontos de controle arbitrarios: sempre dava
    // uma bola com um bico estranho grudado, porque a cauda encontrava o
    // circulo num angulo qualquer, criando quina ou inchaco.
    //
    // A construcao correta e geometrica: das duas retas tangentes ao circulo
    // que passam pela ponta. Tangente encosta no circulo sem quina por
    // definicao, entao a transicao fica lisa sozinha, sem ajuste fino.
    //
    // Com distancia centro-ponta D e raio r, o ponto de tangencia fica a
    // acos(r/D) do eixo que liga o centro a ponta.
    final double distCentroPonta = r + cauda;
    final double beta = math.acos(r / distCentroPonta);

    final Path gota = Path();
    final Rect circ = Rect.fromCircle(center: centro, radius: r);
    // arco do tangente esquerdo, por cima, ate o tangente direito
    gota.arcTo(circ, math.pi / 2 + beta, 2 * math.pi - 2 * beta, true);
    // retas ate a ponta e de volta -- o close() fecha no tangente esquerdo
    gota.lineTo(ponta.dx, ponta.dy);
    gota.close();

    // sombra: da o descolamento do mapa, senao o pin parece adesivo
    canvas.drawShadow(gota, Colors.black.withAlpha(140), 3.0, false);

    // anel branco por fora -- separa o pin de qualquer cor de mapa por baixo
    canvas.drawPath(
      gota,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = borda * 2
        ..color = Colors.white,
    );

    canvas.drawPath(
      gota,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(centro.dx, centro.dy - r),
          Offset(centro.dx, ponta.dy),
          cores,
        ),
    );

    // icone via fonte de icones, centralizado no circulo
    final tp = TextPainter(textDirection: TextDirection.ltr);
    tp.text = TextSpan(
      text: String.fromCharCode(icone.codePoint),
      style: TextStyle(
        fontSize: r * 1.05,
        fontFamily: icone.fontFamily,
        package: icone.fontPackage,
        color: Colors.white,
      ),
    );
    tp.layout();
    tp.paint(canvas, Offset(centro.dx - tp.width / 2, centro.dy - tp.height / 2));

    return recorder.endRecording().toImage(
          (larguraL * d).round(),
          (alturaL * d).round(),
        );
  }
}

// seta de navegacao: substitui o ponto azul durante o modo Ir.
//
// Desenhada de frente pra CIMA (norte do bitmap). Quem gira e a propriedade
// `rotation` do Marker, em graus de bussola -- entao o desenho nao precisa
// saber nada sobre rumo.
Future<BitmapDescriptor> setaNavegacao(double densidade) async {
  const double lado = 46; // caixa quadrada, pra rotacao nao deslocar o centro
  final double d = densidade;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(d);

  final Offset c = const Offset(lado / 2, lado / 2);

  // disco de fundo: destaca a seta de qualquer cor de mapa e da area de
  // toque visual maior
  canvas.drawCircle(c, 17, Paint()..color = Colors.white);
  canvas.drawCircle(c, 17, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..color = Colors.black.withAlpha(30));

  // seta: triangulo com a base recuada (chanfro), o que da a leitura de
  // "ponta" em vez de triangulo solido
  final Path seta = Path()
    ..moveTo(c.dx, c.dy - 11.5)
    ..lineTo(c.dx + 8.5, c.dy + 10)
    ..lineTo(c.dx, c.dy + 5.2)
    ..lineTo(c.dx - 8.5, c.dy + 10)
    ..close();

  canvas.drawPath(
    seta,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(c.dx, c.dy - 11.5),
        Offset(c.dx, c.dy + 10),
        const [Color(0xFF2E7BC4), Color(0xFF12294A)],
      ),
  );

  final imagem = await recorder.endRecording().toImage(
        (lado * d).round(),
        (lado * d).round(),
      );
  final bytes = await imagem.toByteData(format: ui.ImageByteFormat.png);
  return BitmapDescriptor.bytes(bytes!.buffer.asUint8List(), imagePixelRatio: d);
}

// marker fixo do Inatel -- ponto de referencia permanente do mapa, nao
// depende de anuncio nem de filtro. Toda a busca do app orbita a faculdade,
// entao ela sempre visivel ajuda a se localizar
Future<Marker> markerInatel(double densidade) async {
  return Marker(
    markerId: const MarkerId('inatel_fixo'),
    position: posicaoInatel,
    icon: await PinsMapa.obter(TipoPin.faculdade, densidade),
    zIndexInt: 2, // acima dos anuncios
    infoWindow: const InfoWindow(
      title: 'Inatel',
      snippet: 'Instituto Nacional de Telecomunicações',
    ),
  );
}
