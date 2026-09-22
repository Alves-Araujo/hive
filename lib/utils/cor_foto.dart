import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';

// cores ja calculadas, por URL. Ficam salvas no aparelho: a cor de uma URL
// nunca muda (trocar a foto gera URL nova), entao depois da primeira vez o
// anel ja abre com a cor certa, sem esperar download nem PaletteGenerator
const String _prefixoPrefs = 'cor_foto:';
final Map<String, Color> _salvas = {};
SharedPreferences? _prefs;

// cache dos calculos em andamento/prontos na sessao -- sem isso o anel
// refaria o trabalho toda vez que a tela reconstruisse (acontece bastante
// no mapa)
final Map<String, Future<Color?>> _cache = {};

// foto de perfil com cache em disco (Image.network so guarda em memoria, e
// baixava a foto inteira de novo a cada abertura do app). Decodifica no
// tamanho em que vai aparecer -- a foto original pode ter a resolucao cheia
// da camera, e decodificar isso pra um circulo de 44px e o que mais pesava
ImageProvider fotoAvatar(String url, double tamanho, double densidade) {
  final largura = (tamanho * densidade).round();
  return ResizeImage(CachedNetworkImageProvider(url), width: largura, height: largura, policy: ResizeImagePolicy.fit);
}

// carrega as cores salvas; chamado no main antes do runApp pra que a
// primeira tela ja encontre a cor sincronamente
Future<void> iniciarCorFoto() async {
  try {
    _prefs = await SharedPreferences.getInstance();
    for (final chave in _prefs!.getKeys()) {
      if (!chave.startsWith(_prefixoPrefs)) continue;
      final valor = _prefs!.getInt(chave);
      if (valor != null) _salvas[chave.substring(_prefixoPrefs.length)] = Color(valor);
    }
  } catch (_) {
    // sem prefs o anel so calcula a cor de novo a cada abertura
  }
}

// cor ja conhecida, sem esperar nada -- serve de initialData do FutureBuilder
// pra nao piscar o verde padrao antes da cor certa
Color? corDaFotoSalva(String url) => _salvas[url];

// cor que combina com a foto de perfil, pra usar no anel do avatar. Prefere
// uma cor vibrante (mais viva que a media crua da imagem); cai pra
// dominante e depois muted se a foto nao tiver nada vibrante
Future<Color?> corDaFoto(String url) {
  if (url.isEmpty) return Future.value(null);
  final salva = _salvas[url];
  return _cache.putIfAbsent(url, () => salva != null ? Future.value(salva) : _carregar(url));
}

Future<Color?> _carregar(String url) async {
  try {
    final paleta = await PaletteGenerator.fromImageProvider(
      // mesmo provider (com cache em disco) do avatar, entao o download e
      // compartilhado; o ResizeImage decodifica a foto ja pequena em vez de
      // decodificar a resolucao cheia da camera so pra tirar uma cor
      ResizeImage(CachedNetworkImageProvider(url), width: 64, policy: ResizeImagePolicy.fit),
      maximumColorCount: 12,
      timeout: const Duration(seconds: 30),
    );
    final cor = paleta.vibrantColor?.color ?? paleta.dominantColor?.color ?? paleta.mutedColor?.color;
    if (cor != null) {
      _salvas[url] = cor;
      _prefs?.setInt('$_prefixoPrefs$url', cor.toARGB32());
    }
    return cor;
  } catch (_) {
    // nao guarda falha (timeout, rede) no cache -- assim a proxima vez que
    // o anel pedir essa foto ele tenta de novo, em vez de ficar preso no
    // verde padrao pelo resto da sessao por causa de uma rede ruim uma vez
    _cache.remove(url);
    return null;
  }
}
