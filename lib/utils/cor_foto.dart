import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

// cache por URL -- PaletteGenerator baixa e decodifica a imagem inteira, e
// sem isso o anel do avatar refaria esse trabalho toda vez que a tela
// reconstruisse (o que acontece bastante no mapa)
final Map<String, Future<Color?>> _cache = {};

// cor que combina com a foto de perfil, pra usar no anel do avatar. Prefere
// uma cor vibrante (mais viva que a media crua da imagem); cai pra
// dominante e depois muted se a foto nao tiver nada vibrante
Future<Color?> corDaFoto(String url) {
  if (url.isEmpty) return Future.value(null);
  return _cache.putIfAbsent(url, () => _carregar(url));
}

Future<Color?> _carregar(String url) async {
  try {
    final paleta = await PaletteGenerator.fromImageProvider(
      NetworkImage(url),
      size: const Size(60, 60),
      maximumColorCount: 12,
      // fotos grandes (ex.: direto de drone/camera) podem passar dos 15s
      // padrao numa rede mais lenta -- 30s da folga sem travar a UI, que so
      // fica no verde padrao enquanto isso
      timeout: const Duration(seconds: 30),
    );
    return paleta.vibrantColor?.color ?? paleta.dominantColor?.color ?? paleta.mutedColor?.color;
  } catch (_) {
    // nao guarda falha (timeout, rede) no cache -- assim a proxima vez que
    // o anel pedir essa foto ele tenta de novo, em vez de ficar preso no
    // verde padrao pelo resto da sessao por causa de uma rede ruim uma vez
    _cache.remove(url);
    return null;
  }
}
