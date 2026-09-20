import 'dart:convert';
import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../models/imovel.dart';
import '../utils/moderacao.dart';
import '../utils/texto.dart';

enum TipoSugestao { cidade, faculdade, moradia, endereco }

// forma da geometria devolvida pro mapa desenhar o destaque certo --
// ponto vira marker, linha vira Polyline (rua), area vira Polygon (bairro)
enum TipoGeometria { ponto, linha, area }

class SugestaoBusca {
  final String texto;
  final TipoSugestao tipo;
  final LatLng destino;
  final TipoGeometria tipoGeometria;
  final List<LatLng> pontosGeometria; // so preenchido quando tipoGeometria != ponto

  // linha de apoio na lista (cidade/estado, rua...) -- o display_name do
  // Nominatim vem inteiro numa string so e fica ilegivel numa linha unica
  final String detalhe;

  // area cujo contorno ainda nao foi buscado. Buscar o contorno leva
  // segundos (Overpass), e fazer isso PARA CADA sugestao antes de mostrar a
  // lista era o motivo de as sugestoes demorarem tanto a aparecer -- agora
  // so acontece quando a pessoa escolhe o resultado
  final bool contornoPendente;

  const SugestaoBusca({
    required this.texto,
    required this.tipo,
    required this.destino,
    this.tipoGeometria = TipoGeometria.ponto,
    this.pontosGeometria = const [],
    this.detalhe = '',
    this.contornoPendente = false,
  });

  SugestaoBusca comGeometria(TipoGeometria tipo, List<LatLng> pontos) =>
      SugestaoBusca(
        texto: texto,
        tipo: this.tipo,
        destino: destino,
        tipoGeometria: tipo,
        pontosGeometria: pontos,
        detalhe: detalhe,
      );
}

// pedido de "mostra esse bairro no mapa", feito da tela de detalhes do
// imovel e consumido pelo mapa -- mesmo padrao do rotaPendenteGlobal, que
// ja existia pra rota. A tela de detalhes nao desenha nada: ela so diz qual
// bairro quer ver e volta pro mapa, que trata de achar o contorno
class BairroPendente {
  final String nome;

  // ponto de referencia (a posicao do imovel) -- e o que distingue o "Centro"
  // certo entre os milhares de bairros com esse nome no Brasil
  final LatLng perto;

  const BairroPendente({required this.nome, required this.perto});
}

final ValueNotifier<BairroPendente?> bairroPendenteGlobal = ValueNotifier(null);

class _LocalConhecido {
  final String nome;
  final TipoSugestao tipo;
  final LatLng posicao;
  const _LocalConhecido(this.nome, this.tipo, this.posicao);
}

// cidades e faculdades da regiao do Inatel (Santa Rita do Sapucaí, MG) --
// lista estatica, sem custo de leitura nenhuma
final List<String> locaisConhecidosParaCidade = _locaisConhecidos
    .where((l) => l.tipo == TipoSugestao.cidade)
    .map((l) => l.nome)
    .toList();

// mesma lista, mas com a coordenada junto -- usada no seletor de destino da rota
final List<SugestaoBusca> locaisConhecidosGeral = _locaisConhecidos
    .map((l) => SugestaoBusca(texto: l.nome, tipo: l.tipo, destino: l.posicao))
    .toList();

// so essas 3 (+ visao geral, tratada a parte na tela) aparecem no seletor
// rapido de "cidades parceiras" -- bem mais restrito que a lista geral usada
// na busca/autocomplete, que continua com todas as cidades da regiao
const _nomesCidadesParceiras = {'Santa Rita do Sapucaí, MG', 'Pouso Alegre, MG', 'Itajubá, MG'};
final List<SugestaoBusca> cidadesParceiras = _locaisConhecidos
    .where((l) => _nomesCidadesParceiras.contains(l.nome))
    .map((l) => SugestaoBusca(texto: l.nome, tipo: l.tipo, destino: l.posicao))
    .toList();

const List<_LocalConhecido> _locaisConhecidos = [
  // nome completo com a sigla junto, pra ficar claro pra quem digita "INATEL"
  // ou "UNIFEI" que achou a instituicao certa (nao um bairro homonimo).
  // Coordenadas conferidas na propria base do OpenStreetMap (nao a estimativa
  // antiga) -- o Nominatim so tinha "Inatel"/"FAI" cadastrados como bairro/
  // area no lugar do predio, e essa era a causa do pino cair fora do campus
  _LocalConhecido('Inatel - Instituto Nacional de Telecomunicações', TipoSugestao.faculdade, LatLng(-22.2573047, -45.6958702)),
  _LocalConhecido('UNIFEI - Universidade Federal de Itajubá', TipoSugestao.faculdade, LatLng(-22.4132556, -45.4488284)),
  _LocalConhecido('FAI - Faculdade de Administração e Informática', TipoSugestao.faculdade, LatLng(-22.2602959, -45.7028555)),
  _LocalConhecido('UNIVÁS - Universidade do Vale do Sapucaí', TipoSugestao.faculdade, LatLng(-22.2197083, -45.9160719)),
  _LocalConhecido('Santa Rita do Sapucaí, MG', TipoSugestao.cidade, LatLng(-22.2528, -45.6976)),
  _LocalConhecido('Cássia, MG', TipoSugestao.cidade, LatLng(-20.5967, -46.9219)),
  _LocalConhecido('Itajubá, MG', TipoSugestao.cidade, LatLng(-22.4256, -45.4528)),
  _LocalConhecido('Pouso Alegre, MG', TipoSugestao.cidade, LatLng(-22.2299, -45.9364)),
  _LocalConhecido('Poços de Caldas, MG', TipoSugestao.cidade, LatLng(-21.7877, -46.5613)),
  _LocalConhecido('São Lourenço, MG', TipoSugestao.cidade, LatLng(-22.1170, -45.0547)),
];

// combina cidades/faculdades (lista fixa) com moradias (ja carregadas em
// memoria pelo mapa) -- nenhuma leitura nova no firestore por busca
class BuscaService {
  BuscaService._();
  static final BuscaService instance = BuscaService._();

  // quebra o que foi digitado em palavras soltas.
  //
  // E o que torna a busca "mais livre": antes o texto inteiro tinha que
  // aparecer na mesma ordem, entao "sapucai santa rita" nao achava "Santa
  // Rita do Sapucaí", e "republica centro" nao achava "República Estudantil
  // Central" no bairro Centro. Agora basta cada palavra aparecer em algum
  // lugar, em qualquer ordem, sem acento e sem ligar pra maiuscula
  List<String> _palavras(String query) => normalizarNome(query)
      .split(' ')
      .where((p) => p.isNotEmpty)
      .toList();

  // relevancia: quanto MENOR, mais em cima na lista. Null = nao casa.
  //
  // Casar no inicio do nome vale mais do que casar no comeco de uma palavra
  // do meio, que por sua vez vale mais do que casar dentro de uma palavra --
  // e o que faz "cen" mostrar "Centro" antes de "Vila Adélia, perto do
  // centro". Sem isso a ordem era so a de insercao no laço
  int? _pontuar(String alvo, List<String> palavras) {
    final texto = normalizarNome(alvo);
    var pontos = 0;
    for (final palavra in palavras) {
      final posicao = texto.indexOf(palavra);
      if (posicao < 0) return null;
      if (posicao == 0) {
        pontos += 0;
      } else if (texto[posicao - 1] == ' ') {
        pontos += 3;
      } else {
        pontos += 8;
      }
    }
    // desempate: entre dois que casam igual, o nome mais curto e o mais
    // especifico ("Centro" antes de "Centro Comercial de Santa Rita")
    return pontos + (texto.length ~/ 25);
  }

  List<SugestaoBusca> buscarSugestoes(String query, List<Imovel> imoveis) {
    final palavras = _palavras(query);
    if (palavras.isEmpty) return [];

    final ranqueadas = <({int pontos, SugestaoBusca sugestao})>[];

    for (final local in _locaisConhecidos) {
      final pontos = _pontuar(local.nome, palavras);
      if (pontos == null) continue;
      ranqueadas.add((
        // instituicao e cidade da lista fixa sao o resultado mais provavel
        // quando a pessoa digita o nome delas -- entram na frente
        pontos: pontos - 2,
        sugestao: SugestaoBusca(
            texto: local.nome, tipo: local.tipo, destino: local.posicao),
      ));
    }

    for (final imovel in imoveis) {
      // combina titulo, endereco, tipo (Casa/Apartamento/Pensão/...), bairro e
      // cidade -- antes so titulo+endereco batiam, entao buscar "pensao" nao
      // achava uma Pensão cujo titulo/endereco nao continha essa palavra
      final pontos = _pontuar(
        '${imovel.titulo} ${imovel.endereco} ${imovel.tipoImovel} ${imovel.bairro} ${imovel.cidade}',
        palavras,
      );
      if (pontos == null) continue;
      ranqueadas.add((
        pontos: pontos,
        sugestao: SugestaoBusca(
          texto: imovel.titulo,
          tipo: TipoSugestao.moradia,
          destino: imovel.posicao,
          detalhe: [imovel.bairro, imovel.cidade]
              .where((p) => p.isNotEmpty)
              .join(' · '),
        ),
      ));
    }

    ranqueadas.sort((a, b) => a.pontos.compareTo(b.pontos));
    return ranqueadas.map((r) => r.sugestao).take(8).toList();
  }

  // autocomplete de verdade (ruas, bairros, cidades -- nao so a listinha fixa
  // acima), via Nominatim (OpenStreetMap) -- gratuito, sem chave, sem
  // depender do Google Cloud (que na pratica so aceita Directions/Places com
  // billing habilitado e sem restricao de API, o que ficou instavel pra
  // gente). Limitado ao Brasil pra nao trazer resultado de fora.
  // polygon_geojson pede a geometria de verdade (contorno da rua/bairro), nao
  // so o ponto central -- e o que permite desenhar o destaque certo no mapa
  Future<List<SugestaoBusca>> buscarLocaisOnline(String query,
      {LatLng? perto}) async {
    if (query.trim().length < 3) return [];

    // caixa de ~100 km em volta do ponto de referencia (onde a pessoa esta,
    // ou o Inatel). Sem isso "Centro" devolvia o centro de Alagoas e o de
    // Nova Friburgo antes do centro da cidade em que a pessoa esta -- o
    // Nominatim nao tem como adivinhar a regiao sozinho.
    // bounded=0: e preferencia, nao cerca. Buscar uma cidade de outro estado
    // continua funcionando, so vem depois do que esta perto
    final referencia = perto ?? const LatLng(-22.2573047, -45.6958702);
    const double raioGraus = 0.9;

    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': query,
      'format': 'json',
      'addressdetails': '1',
      'countrycodes': 'br',
      'limit': '10',
      'polygon_geojson': '1',
      'polygon_threshold': '0.002', // simplifica o contorno, senao vem pesado demais
      'viewbox': '${referencia.longitude - raioGraus},'
          '${referencia.latitude + raioGraus},'
          '${referencia.longitude + raioGraus},'
          '${referencia.latitude - raioGraus}',
      'bounded': '0',
    });

    try {
      final resposta = await http
          .get(uri, headers: {'User-Agent': 'moradia-app-inatel/1.0'})
          // 6 s era tempo demais pra uma lista que precisa acompanhar quem
          // esta digitando: passou disso, a sugestao ja nao serve mais
          .timeout(const Duration(seconds: 3));
      if (resposta.statusCode != 200) return [];

      final lista = json.decode(resposta.body) as List<dynamic>;
      final vistos = <String>{};
      final sugestoes = <SugestaoBusca>[];

      const tiposDeCidade = {'city', 'town', 'village', 'municipality', 'suburb'};

      for (final item in lista) {
        // display_name ja vem formatado pelo Nominatim (rua, bairro, cidade,
        // estado...) -- usar direto em vez de remontar a mao a partir de
        // "address" cobre ruas/bairros que antes ficavam de fora
        final texto = item['display_name'] as String?;
        if (texto == null || texto.isEmpty || !vistos.add(texto)) continue;

        final lat = double.tryParse(item['lat']?.toString() ?? '');
        final lng = double.tryParse(item['lon']?.toString() ?? '');
        if (lat == null || lng == null) continue;

        final classe = item['class'] as String? ?? '';
        final tipoOsm = item['type'] as String? ?? '';
        final ehCidade = classe == 'place' && tiposDeCidade.contains(tipoOsm);

        // o estilo do destaque (linha/area/ponto) e decidido pela CATEGORIA
        // do lugar (class/type do OSM), nao pela forma da geometria que
        // por acaso veio na resposta -- uma faculdade pode ter o terreno do
        // campus mapeado como poligono no OSM, mas continua sendo um PONTO
        // de interesse (pin), nao uma "area" tipo bairro
        var tipoGeometria = _classificarDestaque(classe, tipoOsm);
        List<LatLng> pontosGeometria = tipoGeometria == TipoGeometria.ponto
            ? const <LatLng>[]
            : _extrairPontos(item['geojson'] as Map<String, dynamic>?, tipoGeometria);

        // bairro sem contorno no proprio Nominatim: o contorno real (o
        // formato de verdade das ruas, nao um circulo aproximado) existe no
        // Overpass, mas buscar la e LENTO -- e antes isso acontecia AQUI,
        // para cada area da lista, antes de mostrar qualquer sugestao. Era a
        // causa da demora. Agora so marca que falta, e o contorno e buscado
        // quando a pessoa escolhe o resultado (ver garantirContorno)
        final bool faltaContorno =
            tipoGeometria == TipoGeometria.area && pontosGeometria.length < 3;

        // display_name vem inteiro numa string so ("Centro, Santa Rita do
        // Sapucaí, Minas Gerais, Brasil"): o comeco e o nome do lugar, o
        // resto e onde ele fica. Separado, a lista fica legivel
        final partes = texto.split(',');
        final nome = (item['name'] as String?)?.trim().isNotEmpty == true
            ? (item['name'] as String).trim()
            : partes.first.trim();
        final detalhe = partes.length > 1
            ? partes.sublist(1).map((p) => p.trim()).take(3).join(', ')
            : '';

        sugestoes.add(SugestaoBusca(
          texto: capitalizarNome(nome),
          detalhe: detalhe,
          tipo: ehCidade ? TipoSugestao.cidade : TipoSugestao.endereco,
          destino: LatLng(lat, lng),
          tipoGeometria: tipoGeometria,
          pontosGeometria: pontosGeometria,
          contornoPendente: faltaContorno,
        ));
      }

      // o viewbox e so uma dica pro Nominatim, que as vezes devolve o lugar
      // distante primeiro mesmo assim. Ordenar por distancia aqui garante
      // que o bairro da cidade da pessoa venha antes do homonimo do outro
      // estado -- e o comportamento que se espera de uma busca no mapa
      sugestoes.sort((a, b) => _distanciaAprox(a.destino, referencia)
          .compareTo(_distanciaAprox(b.destino, referencia)));
      return sugestoes;
    } catch (e) {
      debugPrint('Erro ao buscar locais online: $e');
      return [];
    }
  }

  // so pra ORDENAR: compara distancias em graus ao quadrado, sem raiz e sem
  // trigonometria. Nao vira metro nenhum -- e a ordem que importa aqui
  double _distanciaAprox(LatLng a, LatLng b) {
    final dx = a.longitude - b.longitude;
    final dy = a.latitude - b.latitude;
    return dx * dx + dy * dy;
  }

  // completa a sugestao escolhida com o contorno que faltava.
  //
  // Roda no momento da escolha, nao na montagem da lista: uma busca lenta
  // aqui atrasa UM resultado que a pessoa ja pediu, em vez de segurar a lista
  // inteira enquanto ela ainda esta digitando
  Future<SugestaoBusca> garantirContorno(SugestaoBusca sugestao) async {
    if (!sugestao.contornoPendente) return sugestao;
    final pontos = await buscarContornoDeArea(sugestao.texto, sugestao.destino);
    return sugestao.comGeometria(
      pontos.length >= 3 ? TipoGeometria.area : TipoGeometria.ponto,
      pontos,
    );
  }

  // busca o contorno real (way ou relation do tipo boundary/place) de um
  // bairro/regiao via Overpass API -- gratuito tambem, mesma infra do
  // OpenStreetMap. So chamado quando o Nominatim nao trouxe poligono nenhum
  Future<List<LatLng>> buscarContornoDeArea(String nome, LatLng perto) async {
    final nomeEscapado = nome.replaceAll('\\', r'\\').replaceAll('"', r'\"');
    final query = '[out:json][timeout:15];'
        '('
        'way["name"="$nomeEscapado"]["place"](around:4000,${perto.latitude},${perto.longitude});'
        'way["name"="$nomeEscapado"]["boundary"](around:4000,${perto.latitude},${perto.longitude});'
        'relation["name"="$nomeEscapado"]["boundary"](around:4000,${perto.latitude},${perto.longitude});'
        ');out geom;';

    try {
      final resposta = await http
          .post(Uri.https('overpass-api.de', '/api/interpreter'), body: {'data': query})
          .timeout(const Duration(seconds: 8));
      if (resposta.statusCode != 200) return const [];

      final dados = json.decode(resposta.body) as Map<String, dynamic>;
      final elementos = dados['elements'] as List<dynamic>? ?? [];

      List<LatLng> melhorAnel = const [];
      for (final el in elementos) {
        final geometriaDireta = el['geometry'] as List<dynamic>?;
        if (geometriaDireta != null) {
          final anel = _pontosOverpass(geometriaDireta);
          if (anel.length > melhorAnel.length) melhorAnel = anel;
          continue;
        }
        // relation (multipoligono) -- junta o(s) membro(s) externo(s) com mais pontos
        final membros = el['members'] as List<dynamic>?;
        if (membros == null) continue;
        for (final membro in membros) {
          if (membro['role'] != 'outer') continue;
          final geomMembro = membro['geometry'] as List<dynamic>?;
          if (geomMembro == null) continue;
          final anel = _pontosOverpass(geomMembro);
          if (anel.length > melhorAnel.length) melhorAnel = anel;
        }
      }
      return melhorAnel;
    } catch (e) {
      debugPrint('Erro ao buscar contorno do bairro: $e');
      return const [];
    }
  }

  List<LatLng> _pontosOverpass(List<dynamic> geometria) {
    return geometria
        .whereType<Map<String, dynamic>>()
        .map((p) => LatLng((p['lat'] as num).toDouble(), (p['lon'] as num).toDouble()))
        .toList();
  }

  // rua/via sempre linha; bairro, distrito ou fronteira administrativa
  // sempre area; qualquer outra coisa (faculdade, loja, hospital, predio,
  // orgao publico...) e sempre ponto -- e assim que o Google Maps tambem se
  // comporta, independente de qual geometria o OSM tem cadastrada pro lugar
  TipoGeometria _classificarDestaque(String classe, String tipoOsm) {
    if (classe == 'highway') return TipoGeometria.linha;
    if (classe == 'boundary') return TipoGeometria.area;
    const tiposDeAreaEmPlace = {'suburb', 'neighbourhood', 'quarter', 'city_block', 'city', 'town', 'village', 'municipality'};
    if (classe == 'place' && tiposDeAreaEmPlace.contains(tipoOsm)) return TipoGeometria.area;
    return TipoGeometria.ponto;
  }

  // decodifica o geojson que o Nominatim devolve, quando existe -- pode nao
  // ter contorno de verdade (so um node no OSM), nesse caso volta vazio e
  // quem desenha o mapa cai num fallback (ex: um circulo aproximado)
  List<LatLng> _extrairPontos(Map<String, dynamic>? geojson, TipoGeometria esperado) {
    if (geojson == null) return const [];

    List<LatLng> anel(List<dynamic> pontos) => pontos
        .map((p) => LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()))
        .toList();

    final tipo = geojson['type'] as String?;
    final coordenadas = geojson['coordinates'];
    if (coordenadas == null) return const [];

    try {
      switch (tipo) {
        case 'LineString':
          return anel(coordenadas as List<dynamic>);
        case 'MultiLineString':
          return (coordenadas as List<dynamic>).expand((trecho) => anel(trecho as List<dynamic>)).toList();
        case 'Polygon':
          return anel((coordenadas as List<dynamic>).first as List<dynamic>);
        case 'MultiPolygon':
          final poligonos = (coordenadas as List<dynamic>)
              .map((p) => anel((p as List<dynamic>).first as List<dynamic>))
              .toList();
          poligonos.sort((a, b) => b.length.compareTo(a.length));
          return poligonos.first;
        default:
          return const [];
      }
    } catch (_) {
      return const [];
    }
  }

}
