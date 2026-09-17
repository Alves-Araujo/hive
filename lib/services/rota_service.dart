import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint;
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng, LatLngBounds;

// pedido de rota feito na tela de detalhes, consumido pelo mapa principal --
// mesmo padrao do temaGlobal (ValueNotifier global) ja usado no app. A tela
// de detalhes seta o valor e volta pro mapa; o mapa escuta, calcula a rota
// de verdade e limpa o valor
class RotaPendente {
  final LatLng origem;
  final LatLng destino;
  final String nomeDestino;
  final TravelMode modo;

  RotaPendente({
    required this.origem,
    required this.destino,
    required this.nomeDestino,
    this.modo = TravelMode.driving,
  });
}

final ValueNotifier<RotaPendente?> rotaPendenteGlobal = ValueNotifier(null);

// uma das alternativas de trajeto que o Google devolveu -- guarda tambem a
// duracao em segundos (nao so o texto) pra dar pra comparar as opcoes entre
// si e montar o "+7 min" do seletor de alternativas
class RotaOpcao {
  final List<LatLng> pontos;
  final String distanciaTexto;
  final String duracaoTexto;
  final int duracaoSegundos;

  RotaOpcao({
    required this.pontos,
    required this.distanciaTexto,
    required this.duracaoTexto,
    required this.duracaoSegundos,
  });
}

// rota ja calculada, pronta pra desenhar -- guarda tambem origem/destino
// (os markers), o nome digitado/escolhido pro destino (pro card de
// distancia/duracao mostrar) e o modo usado (pra saber qual icone destacar
// no seletor de transporte e poder recalcular no mesmo par origem/destino
// quando o usuario troca de carro pra a pe, por exemplo)
class RotaAtiva {
  // todas as alternativas devolvidas pra esse par origem/destino, na ordem
  // que o Google mandou (a primeira e a que ele considera principal)
  final List<RotaOpcao> opcoes;
  final int indiceSelecionado;
  final LatLng origem;
  final LatLng destino;
  final String nomeDestino;
  final TravelMode modo;

  RotaAtiva({
    required this.opcoes,
    required this.origem,
    required this.destino,
    required this.nomeDestino,
    required this.modo,
    this.indiceSelecionado = 0,
  });

  RotaOpcao get selecionada => opcoes[indiceSelecionado];

  // troca so qual alternativa esta ativa, reaproveitando a MESMA lista de
  // opcoes -- o mapa usa essa identidade (identical) pra saber que nao e uma
  // rota nova e por isso nao deve reenquadrar a camera
  RotaAtiva selecionar(int indice) => RotaAtiva(
        opcoes: opcoes,
        origem: origem,
        destino: destino,
        nomeDestino: nomeDestino,
        modo: modo,
        indiceSelecionado: indice,
      );
}

// resultado da rota mais recente e se uma busca ta em andamento -- ficam
// globais (mesmo padrao do temaGlobal) de proposito: o CentroDoMapa e
// recriado do zero toda vez que o usuario troca de aba (a TelaPrincipal usa
// uma key baseada no indice na IndexedStack), entao guardar isso preso a
// State dele faria o resultado se perder se o calculo terminasse com o
// mapa fora da tela
final ValueNotifier<bool> rotaCarregandoGlobal = ValueNotifier(false);
final ValueNotifier<RotaAtiva?> rotaAtivaGlobal = ValueNotifier(null);

// mensagem de erro da ultima tentativa de rota -- o mapa escuta isso pra
// mostrar um SnackBar (antes uma falha aqui sumia sem avisar ninguem)
final ValueNotifier<String?> rotaErroGlobal = ValueNotifier(null);

// dispara o calculo de uma rota pendente e publica o resultado -- funcao
// solta, sem dono, pra nao ser interrompida se a tela que a chamou for
// desmontada no meio do caminho
Future<void> processarPedidoDeRota(RotaPendente pendente, String apiKey) async {
  rotaCarregandoGlobal.value = true;
  try {
    final opcoes = await RotaService(apiKey).buscarRotas(
      origem: pendente.origem,
      destino: pendente.destino,
      modo: pendente.modo,
    );
    rotaAtivaGlobal.value = RotaAtiva(
      opcoes: opcoes,
      origem: pendente.origem,
      destino: pendente.destino,
      nomeDestino: pendente.nomeDestino,
      modo: pendente.modo,
    );
  } catch (e) {
    debugPrint('Erro ao calcular rota: $e');
    rotaErroGlobal.value = e.toString();
  } finally {
    rotaCarregandoGlobal.value = false;
  }
}

// wrapper fino sobre o flutter_polyline_points pra buscar a rota entre 2 pontos
class RotaService {
  RotaService(this._apiKey);
  final String _apiKey;

  // os textos vem por "leg" -- sem waypoints existe so uma, mas um ".first"
  // seco estouraria se a API devolvesse a lista vazia
  static String _primeiroTexto(List<String>? textos) =>
      (textos == null || textos.isEmpty) ? '' : textos.first;

  // devolve TODAS as alternativas de trajeto pro par origem/destino (a
  // primeira e a principal na visao do Google). Usa o NetworkUtil em vez do
  // PolylinePoints.getRouteBetweenCoordinates porque esse ultimo colapsa a
  // resposta num unico resultado e joga as alternativas fora -- o NetworkUtil
  // monta um PolylineResult por item de "routes", que e exatamente o que
  // precisamos pro seletor de alternativas
  Future<List<RotaOpcao>> buscarRotas({
    required LatLng origem,
    required LatLng destino,
    TravelMode modo = TravelMode.driving,
  }) async {
    // PolylineRequest usa a Directions API "classica" de proposito -- foi ela
    // que habilitamos no google cloud, nao a Routes API nova (que o pacote
    // tambem suporta, mas exigiria habilitar outra api). Por isso "moto"
    // (TravelMode.twoWheeler) nao existe na API classica do Google -- usamos
    // o modo de carro como aproximacao nesse caso (ver mapeamento no mapa)
    //
    // alternatives:true e o que faz o Google mandar mais de um trajeto. Vale
    // lembrar que ele so funciona sem waypoints intermediarios -- se um dia
    // adicionarmos paradas, as alternativas somem (limitacao da propria API)
    // ignore: deprecated_member_use
    final request = PolylineRequest(
      origin: PointLatLng(origem.latitude, origem.longitude),
      destination: PointLatLng(destino.latitude, destino.longitude),
      mode: modo,
      alternatives: true,
    );

    // ignore: deprecated_member_use
    final resultados = await NetworkUtil().getRouteBetweenCoordinates(
      request: request,
      googleApiKey: _apiKey,
    );

    final opcoes = resultados
        .where((r) => r.points.isNotEmpty)
        .map((r) => RotaOpcao(
              pontos: r.points.map((p) => LatLng(p.latitude, p.longitude)).toList(),
              distanciaTexto: _primeiroTexto(r.distanceTexts),
              duracaoTexto: _primeiroTexto(r.durationTexts),
              duracaoSegundos: r.totalDurationValue ?? 0,
            ))
        .toList();

    // o NetworkUtil engole o motivo da falha (devolve lista vazia em qualquer
    // erro), e perder esse diagnostico atrapalha demais pra achar problema de
    // chave/restricao/limite -- entao refaz a chamada pela via que ainda
    // expoe status + errorMessage so pra montar a mensagem de erro
    if (opcoes.isEmpty) {
      final diagnostico = await PolylinePoints(apiKey: _apiKey).getRouteBetweenCoordinates(
        request: request,
      );
      throw Exception(
        '${diagnostico.status ?? 'Sem rota'}: ${diagnostico.errorMessage ?? 'nenhum trajeto encontrado'}',
      );
    }

    return opcoes;
  }

  // menor retangulo que engloba todos os pontos da rota, pra enquadrar a
  // camera do mapa mostrando o trajeto inteiro
  static LatLngBounds calcularBounds(List<LatLng> pontos) {
    double? minLat, maxLat, minLng, maxLng;
    for (final p in pontos) {
      minLat = (minLat == null || p.latitude < minLat) ? p.latitude : minLat;
      maxLat = (maxLat == null || p.latitude > maxLat) ? p.latitude : maxLat;
      minLng = (minLng == null || p.longitude < minLng) ? p.longitude : minLng;
      maxLng = (maxLng == null || p.longitude > maxLng) ? p.longitude : maxLng;
    }
    return LatLngBounds(
      southwest: LatLng(minLat!, minLng!),
      northeast: LatLng(maxLat!, maxLng!),
    );
  }
}
