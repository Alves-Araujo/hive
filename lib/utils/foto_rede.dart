import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

// Foto vinda da internet, com cache em disco e decodificada no tamanho em que
// vai aparecer. Serve pras fotos de anuncio, de imobiliaria, do chat e dos
// lugares -- o avatar tem o seu proprio atalho em utils/cor_foto.dart, que faz
// a mesma coisa e ainda e a chave do cache de cor do anel.
//
// O QUE ISSO CONSERTA
//
// Image.network guarda a imagem SO em memoria, no ImageCache do Flutter, e
// decodifica o arquivo no tamanho original. Foto tirada no celular sai com
// algo como 4000x3000, e imagem decodificada ocupa largura x altura x 4 bytes:
// 48 MB cada uma, independente de aparecer num card de 180px ou num quadrado
// de 56px. O ImageCache tem teto de 100 MB, entao DUAS fotos enchiam o cache
// inteiro; da terceira em diante cada foto nova expulsava as anteriores.
//
// Era isso que fazia:
//   - as fotos sumirem da lista depois de um tempo rolando a tela
//   - abrir um anuncio (que carrega a foto em tela cheia) e, ao voltar,
//     encontrar a lista inteira sem foto -- a foto grande tinha acabado de
//     expulsar todas as pequenas
//   - a mesma foto ser baixada de novo a cada vez, o que numa rede de celular
//     e o que faz a imagem demorar pra aparecer
//
// Decodificando no tamanho de exibicao, a mesma foto do card de 180px passa a
// ocupar menos de 1 MB em vez de 48 MB, e cabem centenas delas no cache. O
// cache em disco do CachedNetworkImage completa o conserto: o arquivo baixado
// fica gravado no aparelho, entao voltar pra uma tela ja vista nao gasta rede
// nenhuma.
//
// COMO USAR
//
// Passe a largura em que a foto aparece na tela (em pixels logicos) e a
// densidade do aparelho. Em BoxFit.cover use a largura da caixa; a altura sai
// junto porque a proporcao da foto e mantida.
ImageProvider fotoDaRede(String url, double larguraLogica, double densidade) {
  // piso pequeno so pra nao pedir decodificacao de 0px se a caixa ainda nao
  // foi medida no primeiro frame
  final largura = (larguraLogica * densidade).round().clamp(64, 4096);
  return ResizeImage(
    CachedNetworkImageProvider(url),
    width: largura,
    policy: ResizeImagePolicy.fit,
    // sem isso uma foto menor que a caixa seria AMPLIADA na decodificacao,
    // gastando memoria pra piorar a imagem
    allowUpscaling: false,
  );
}

// atalho pra quem ja esta num build e quer a largura da tela como referencia
// (card que ocupa a linha toda, capa em tela cheia)
ImageProvider fotoDaRedeLargura(BuildContext context, String url) {
  return fotoDaRede(
    url,
    MediaQuery.sizeOf(context).width,
    MediaQuery.devicePixelRatioOf(context),
  );
}
