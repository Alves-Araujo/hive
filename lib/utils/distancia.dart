import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../main.dart';

// distancia em linha reta ate o Inatel, em metros.
//
// E linha reta de proposito, nao distancia de caminhada: esta e uma etiqueta
// de referencia rapida no card, nao uma rota. Calcular trajeto real custaria
// uma chamada a Directions API por anuncio na lista, o que seria caro e lento
// pra uma informacao que serve so pra dar noçao de proximidade. Quem quer o
// trajeto de verdade usa o "Calcular Rota".
double metrosAteInatel(LatLng posicao) => Geolocator.distanceBetween(
      posicao.latitude,
      posicao.longitude,
      posicaoInatel.latitude,
      posicaoInatel.longitude,
    );

// formata pra leitura humana: metros ate 1 km, depois quilometros com uma
// casa. Arredonda metros de 10 em 10 -- precisao de 1 metro daria falsa
// impressao de exatidao numa medida em linha reta
String formatarDistancia(double metros) {
  if (metros < 1000) {
    final int arredondado = (metros / 10).round() * 10;
    return '$arredondado m';
  }
  final double km = metros / 1000;
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
}

// tempo restante pro painel de navegacao, curto o bastante pra ser lido de
// relance. Nunca devolve "0 min": enquanto a navegacao nao terminou, falta
// pelo menos um minuto pra quem esta olhando
String formatarDuracaoCurta(int segundos) {
  final int minutos = (segundos / 60).round();
  if (minutos < 60) return '${minutos < 1 ? 1 : minutos} min';
  final int horas = minutos ~/ 60;
  final int resto = minutos % 60;
  return resto == 0 ? '$horas h' : '$horas h $resto min';
}

// texto da etiqueta de proximidade da faculdade
String rotuloDistanciaFaculdade(LatLng posicao) =>
    '${formatarDistancia(metrosAteInatel(posicao))} da faculdade';
