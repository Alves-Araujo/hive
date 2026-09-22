import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

import '../main.dart';
import '../utils/pins_mapa.dart';

// os tipos de estabelecimento do dia a dia que aparecem perto das moradias.
//
// `tiposGoogle` sao tipos da tabela A do Places API (New). `raio` e o limite
// do que ainda conta como "perto" -- hospital a 1,5 km ainda e informacao
// util, mercado a 1,5 km nao.
//
// `nomeContem`: o tipo do Google sozinho nao e confiavel. Em Santa Rita ele
// dava "Chalezinho, Pousada Romantica" como hotel, a loja de produtos
// naturais Bioessencia como farmacia e uma clinica de fisioterapia como
// hospital. Entao, nessas categorias, o nome tambem tem que dizer o que o
// lugar e (comparado sem acento e sem caixa). Vazio = so o tipo basta.
//
// `naFichaDoAnuncio`: hotel fica so no mapa. Saber que a moradia esta a 120 m
// de um hotel nao ajuda em NADA quem vai morar ali -- na ficha do anuncio
// isso era ruido no meio de mercado, farmacia e hospital, que pesam de
// verdade na escolha. No mapa o pin continua, pra quem vem visitar
enum CategoriaLugar {
  mercado('Mercado', 'do mercado', Icons.shopping_cart_rounded, TipoPin.mercado,
      ['supermarket', 'grocery_store', 'convenience_store'], [], 800, true),
  farmacia('Farmácia', 'da farmácia', Icons.local_pharmacy_rounded, TipoPin.farmacia,
      // 1 km e nao 800 m: exigindo farmacia de verdade COM foto, a mais perto
      // da republica do Centro ficou a 945 m -- com 800 nenhuma aparecia
      ['pharmacy', 'drugstore'], ['farma', 'drog'], 1000, true),
  posto('Posto de combustível', 'do posto', Icons.local_gas_station_rounded, TipoPin.posto,
      ['gas_station'], [], 1000, true),
  hotel('Hotel', 'do hotel', Icons.hotel_rounded, TipoPin.hotel,
      ['hotel'], ['hotel'], 1500, false),
  hospital('Hospital', 'do hospital', Icons.local_hospital_rounded, TipoPin.hospital,
      ['hospital', 'general_hospital'], ['hospital'], 1500, true);

  const CategoriaLugar(this.rotulo, this.sufixo, this.icone, this.pin, this.tiposGoogle,
      this.nomeContem, this.raio, this.naFichaDoAnuncio);

  final String rotulo; // "Farmácia" -- titulo do painel
  final String sufixo; // "da farmácia" -- etiqueta "320 m da farmácia"
  final IconData icone;
  final TipoPin pin;
  final List<String> tiposGoogle;
  final List<String> nomeContem;
  final int raio;
  final bool naFichaDoAnuncio;

  bool aceitaNome(String nome) {
    if (nomeContem.isEmpty) return true;
    final n = _semAcento(nome.toLowerCase());
    return nomeContem.any(n.contains);
  }
}

String _semAcento(String s) => s
    .replaceAll(RegExp('[áàâã]'), 'a')
    .replaceAll(RegExp('[éê]'), 'e')
    .replaceAll('í', 'i')
    .replaceAll(RegExp('[óôõ]'), 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ç', 'c');

// foto de um estabelecimento. O Google exige mostrar o autor junto da foto
class FotoLugar {
  final String nome; // recurso "places/.../photos/..." da API
  final String autor;

  const FotoLugar(this.nome, this.autor);

  // a URL de /media responde com redirecionamento pra imagem em si, entao
  // serve direto no Image.network. Cada carga e cobrada, por isso so e
  // montada quando o painel abre, e no maximo 2 por lugar
  String url({int largura = 800}) =>
      'https://places.googleapis.com/v1/$nome/media?maxWidthPx=$largura&key=$googleMapsApiKey';
}

class Lugar {
  final String id; // place id do Google -- tambem serve pra deduplicar
  final String nome;
  final String endereco;
  final LatLng posicao;
  final CategoriaLugar categoria;
  final List<FotoLugar> fotos;
  final String? linkGoogleMaps;

  const Lugar({
    required this.id,
    required this.nome,
    required this.endereco,
    required this.posicao,
    required this.categoria,
    required this.fotos,
    this.linkGoogleMaps,
  });
}

// o estabelecimento mais perto de uma categoria, medido a partir de uma moradia
class LugarProximo {
  final Lugar lugar;
  final double metros;
  const LugarProximo(this.lugar, this.metros);
}

// estabelecimentos perto de uma moradia, via Google Places API (New).
//
// Uma chamada por categoria, com o Google ordenando por distancia: uma
// chamada unica com todos os tipos juntos traria os 20
// mais perto de qualquer tipo, e no centro da cidade isso seria 20 farmacias
// e mercados -- o posto e o hospital nunca entrariam.
//
// Cache so em memoria, de proposito: os termos do Google nao permitem
// guardar nome, endereco e foto no aparelho. Na mesma sessao, abrir o
// mesmo anuncio (ou o mapa de novo) nao repete a busca
class LugaresService {
  LugaresService._();
  static final LugaresService instance = LugaresService._();

  final Map<String, Future<List<LugarProximo>>> _cache = {};
  Future<List<Lugar>>? _cacheFixos;

  // lugares que ficam no mapa SEMPRE, mesmo sem nenhum anuncio por perto.
  //
  // A busca normal guarda so o estabelecimento mais proximo de cada
  // categoria por moradia, entao um mercado bom mas longe dos anuncios de
  // hoje nunca ganharia pin. Esta lista e a excecao, pra quando alguem
  // conhece a cidade e sabe que um lugar tem que estar la.
  //
  // So o place id entra aqui: nome, endereco e foto continuam vindo da API a
  // cada sessao, porque os termos do Google nao deixam guardar isso no
  // aparelho (mesmo motivo do cache so em memoria)
  static const String _idAlvorada = 'ChIJTZTKRVCiy5QRTkIdLa7PDN8';
  static const String _idMaristelaBairro = 'ChIJs5SKOlOiy5QRMW7tclY_Sd0';
  static const String _idMaristelaInatel = 'ChIJcbDcH5mjy5QR7WpUlv780Ww';
  static const String _idUnissul = 'ChIJaQy3zv2iy5QRGVQXUvu_vt0';

  static const Map<String, CategoriaLugar> _idsFixos = {
    // Supermercados Alvorada -- R. Comendador Custodio Ribeiro, Centro
    _idAlvorada: CategoriaLugar.mercado,
    // Supermercado Maristela -- Av. Frederico de Paula Cunha, bairro Maristela
    _idMaristelaBairro: CategoriaLugar.mercado,
    // a outra loja do Maristela -- Av. Joao de Camargo, a avenida do Inatel
    _idMaristelaInatel: CategoriaLugar.mercado,
    // Supermercado Avenida Unissul -- Av. Sinha Moreira, Centro
    _idUnissul: CategoriaLugar.mercado,
  };

  // categorias em que SO estes lugares valem. Lista branca, e nao o contrario
  // (proibir um por um), porque em mercado os falsos positivos sao a regra:
  //
  // o filtro por nome (nomeContem) resolve farmacia e hospital, onde o nome
  // sempre entrega -- "farma", "drog", "hospital". Nome de supermercado e
  // qualquer coisa, entao la nao da pra exigir palavra nenhuma e passa tudo
  // que o Google marcou como grocery_store: adega, banca de jornal, loja de
  // tamaras. Em Santa Rita a curadoria e curta: os mercados abaixo.
  //
  // Categoria que nao esta neste mapa continua aceitando o que a busca achar
  static const Map<CategoriaLugar, Set<String>> _idsPermitidos = {
    CategoriaLugar.mercado: {
      _idAlvorada,
      _idMaristelaBairro,
      _idMaristelaInatel,
      _idUnissul,
    },
  };

  // busca os fixos uma vez por sessao. Falha nao fica em cache
  Future<List<Lugar>> fixos() {
    return _cacheFixos ??= Future.wait(_idsFixos.entries.map(_detalhesDe))
        .then((lista) => [for (final l in lista) ?l]).then((lugares) {
      if (lugares.isEmpty) _cacheFixos = null;
      return lugares;
    });
  }

  Future<Lugar?> _detalhesDe(MapEntry<String, CategoriaLugar> fixo) async {
    try {
      final resposta = await http.get(
        Uri.https('places.googleapis.com', '/v1/places/${fixo.key}',
            {'languageCode': 'pt-BR', 'regionCode': 'BR'}),
        headers: {
          'X-Goog-Api-Key': googleMapsApiKey,
          'X-Goog-FieldMask':
              'id,displayName,formattedAddress,location,photos,googleMapsUri',
        },
      ).timeout(const Duration(seconds: 10));

      if (resposta.statusCode != 200) {
        debugPrint('Places (fixo ${fixo.key}) respondeu ${resposta.statusCode}');
        return null;
      }
      return _lugarDe(json.decode(resposta.body) as Map<String, dynamic>, fixo.value);
    } catch (e) {
      debugPrint('Erro ao buscar lugar fixo ${fixo.key}: $e');
      return null;
    }
  }

  Future<List<LugarProximo>> proximosDe(LatLng posicao) {
    // chave pela coordenada arredondada (~10 m): o mesmo predio anunciado
    // duas vezes aproveita a busca
    final chave = '${posicao.latitude.toStringAsFixed(4)},${posicao.longitude.toStringAsFixed(4)}';
    return _cache[chave] ??= _buscar(posicao).then((lugares) {
      // falha (null) nao fica em cache: a proxima abertura tenta de novo
      if (lugares == null) _cache.remove(chave);
      return lugares ?? const [];
    });
  }

  // null = a API falhou em todas as categorias
  Future<List<LugarProximo>?> _buscar(LatLng p) async {
    final resultados = await Future.wait(
      CategoriaLugar.values.map((c) => _maisPerto(c, p)),
    );
    if (resultados.every((r) => r == null)) return null;
    return [for (final r in resultados) ?r?.$1];
  }

  // devolve (lugar ou null se nao ha nenhum perto,) ou null se a chamada falhou
  Future<(LugarProximo?,)?> _maisPerto(CategoriaLugar categoria, LatLng p) async {
    try {
      final resposta = await http
          .post(
            Uri.https('places.googleapis.com', '/v1/places:searchNearby'),
            headers: {
              'Content-Type': 'application/json',
              'X-Goog-Api-Key': googleMapsApiKey,
              // so os campos usados: o preco da chamada depende do campo mais
              // caro pedido
              'X-Goog-FieldMask': 'places.id,places.displayName,places.formattedAddress,'
                  'places.location,places.photos,places.googleMapsUri',
            },
            body: json.encode({
              // tipo PRINCIPAL, nao qualquer tipo: com includedTypes um posto
              // com loja de conveniencia entrava como mercado
              'includedPrimaryTypes': categoria.tiposGoogle,
              // os 10 mais perto, e nao so 1: o mais perto pode nao ter foto
              // ou nao passar no filtro de nome. O preco da chamada e o mesmo
              'maxResultCount': 10,
              'rankPreference': 'DISTANCE',
              'languageCode': 'pt-BR',
              'regionCode': 'BR',
              'locationRestriction': {
                'circle': {
                  'center': {'latitude': p.latitude, 'longitude': p.longitude},
                  'radius': categoria.raio.toDouble(),
                },
              },
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (resposta.statusCode != 200) {
        // 403 aqui quase sempre e a API desligada no Google Cloud ou a chave
        // restrita sem o "Places API (New)" na lista
        debugPrint('Places (${categoria.name}) respondeu ${resposta.statusCode}: '
            '${resposta.body.substring(0, resposta.body.length.clamp(0, 200))}');
        return null;
      }

      final dados = json.decode(resposta.body) as Map<String, dynamic>;
      final candidatos = (dados['places'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map((m) => _lugarDe(m, categoria))
          .whereType<Lugar>();

      // ja vem do mais perto pro mais longe: fica o primeiro que e o que diz
      // ser e tem foto. Sem foto sai de proposito -- lugar sem nenhuma foto
      // no Google costuma ser cadastro abandonado ou errado
      final permitidos = _idsPermitidos[categoria];
      final lugar = candidatos
          .where((l) =>
              (permitidos == null || permitidos.contains(l.id)) &&
              l.fotos.isNotEmpty &&
              categoria.aceitaNome(l.nome))
          .firstOrNull;
      if (lugar == null) return (null,);
      final metros = Geolocator.distanceBetween(
          p.latitude, p.longitude, lugar.posicao.latitude, lugar.posicao.longitude);
      return (LugarProximo(lugar, metros),);
    } catch (e) {
      debugPrint('Erro ao buscar ${categoria.name} perto: $e');
      return null;
    }
  }

  Lugar? _lugarDe(Map<String, dynamic> m, CategoriaLugar categoria) {
    final local = m['location'] as Map<String, dynamic>?;
    final id = m['id'] as String?;
    if (local == null || id == null) return null;

    final fotos = <FotoLugar>[];
    for (final f in (m['photos'] as List<dynamic>? ?? []).whereType<Map<String, dynamic>>()) {
      final nome = f['name'] as String?;
      if (nome == null) continue;
      final autores = (f['authorAttributions'] as List<dynamic>? ?? [])
          .whereType<Map<String, dynamic>>()
          .map((a) => a['displayName'] as String? ?? '')
          .where((a) => a.isNotEmpty);
      fotos.add(FotoLugar(nome, autores.isEmpty ? 'Google' : autores.first));
      if (fotos.length == 2) break;
    }

    return Lugar(
      id: id,
      nome: (m['displayName'] as Map<String, dynamic>?)?['text'] as String? ?? categoria.rotulo,
      endereco: m['formattedAddress'] as String? ?? '',
      posicao: LatLng((local['latitude'] as num).toDouble(), (local['longitude'] as num).toDouble()),
      categoria: categoria,
      fotos: fotos,
      linkGoogleMaps: m['googleMapsUri'] as String?,
    );
  }
}
