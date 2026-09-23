import 'package:flutter/widgets.dart';

// Os pontos da interface que o guia interativo sabe acender.
//
// Cada tela pendura a chave do seu alvo no widget de verdade (key:
// chaveAlvo(AlvoTutorial.busca)), e o guia descobre onde ele esta na tela na
// hora de desenhar o furo. Assim o guia aponta pro botao REAL: se ele mudar
// de canto, o furo muda junto, sem ninguem lembrar de atualizar coordenada.
enum AlvoTutorial {
  // sem alvo: o cartao fica no centro da tela, sem furo. Serve pro que nao
  // mora num botao ("cada pin e um anuncio", "voce ja pode conversar")
  nenhum,
  avatar,
  busca,
  filtros,
  configuracoes,
  minhaLocalizacao,
  anunciar,
  abaMapa,
  abaResumo,
  abaChat,
  abaImoveis,
  filtroResumo,
}

final Map<AlvoTutorial, GlobalKey> _chaves = {};

GlobalKey chaveAlvo(AlvoTutorial alvo) =>
    _chaves.putIfAbsent(alvo, () => GlobalKey(debugLabel: 'alvo_${alvo.name}'));

// Onde o alvo esta AGORA, em coordenadas da tela.
//
// Volta nulo quando o alvo nao existe neste momento -- o botao "Anunciar" so
// aparece pra quem pode anunciar, a aba "Imóveis" nao existe pra estudante, e
// nada disso pode derrubar o guia: sem retangulo, o passo vira um cartao
// central (ver GuiaInterativo)
Rect? rectDoAlvo(AlvoTutorial alvo) {
  if (alvo == AlvoTutorial.nenhum) return null;

  final contexto = _chaves[alvo]?.currentContext;
  if (contexto == null) return null;

  final objeto = contexto.findRenderObject();
  if (objeto is! RenderBox || !objeto.hasSize || !objeto.attached) return null;
  if (objeto.size.isEmpty) return null;

  return objeto.localToGlobal(Offset.zero) & objeto.size;
}
