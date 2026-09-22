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
  return _cache.putIfAbsent(url, () async {
    try {
      final paleta = await PaletteGenerator.fromImageProvider(
        NetworkImage(url),
        size: const Size(60, 60),
        maximumColorCount: 12,
      );
      return paleta.vibrantColor?.color ?? paleta.dominantColor?.color ?? paleta.mutedColor?.color;
    } catch (_) {
      return null;
    }
  });
}
