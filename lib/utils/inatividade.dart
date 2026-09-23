// Anuncio abandonado sai do mapa sozinho.
//
// O problema: moradia anunciada, gente mandando mensagem e ninguem do outro
// lado respondendo. O anuncio segue no mapa ocupando o lugar de quem
// responde, e quem procura moradia gasta o tempo dele mandando mensagem pro
// vazio -- o que o app existe pra evitar.
//
// A conta mora num campo so do proprio anuncio
// (imoveis/{id}.aguardandoRespostaDesde, ver models/imovel.dart): a mensagem
// de um interessado LIGA o relogio, qualquer resposta do dono DESLIGA.
// Passado o prazo com o relogio ligado, o anuncio some do mapa e da lista --
// e volta na hora em que o dono responder, sem ninguem ter que republicar.
//
// Nada disso roda em servidor: o projeto nao tem Cloud Functions (mesmo
// motivo explicado em notificacao_service.dart). Por isso o estado e
// CALCULADO na leitura, aqui, em vez de ser um campo "ativo" que alguem
// precisaria virar na hora certa -- sem servidor, essa hora nunca chegaria.

// Cinco meses contados em dias corridos. O prazo nao pode depender de quantos
// dias tem cada mes: senao o mesmo abandono sairia do mapa mais cedo ou mais
// tarde so conforme o mes em que a conversa comecou
const Duration prazoSemResposta = Duration(days: 150);

// quando o aviso comeca a aparecer pro dono. Um mes e tempo de sobra pra
// responder (ou apagar o anuncio) antes de perder o lugar no mapa
const Duration antecedenciaDoAviso = Duration(days: 30);

enum EstadoResposta {
  // ninguem esperando resposta, ou ainda longe do prazo
  emDia,
  // tem mensagem sem resposta e o prazo esta acabando -- so o dono ve isso
  prazoAcabando,
  // passou dos cinco meses: fora do mapa e da lista
  foraDoMapa,
}

// quanto tempo a mensagem mais antiga esta esperando. Nunca negativo: relogio
// do aparelho atrasado em relacao ao do servidor (que e quem grava a data)
// daria diferenca negativa, e "esperando ha -3 dias" nao significa nada
Duration _espera(DateTime desde, DateTime agora) {
  final diferenca = agora.difference(desde);
  return diferenca.isNegative ? Duration.zero : diferenca;
}

// `agora` e injetavel pro teste nao depender do relogio da maquina
EstadoResposta estadoDeResposta(DateTime? aguardandoDesde, {DateTime? agora}) {
  if (aguardandoDesde == null) return EstadoResposta.emDia;

  final espera = _espera(aguardandoDesde, agora ?? DateTime.now());
  if (espera >= prazoSemResposta) return EstadoResposta.foraDoMapa;
  if (espera >= prazoSemResposta - antecedenciaDoAviso) {
    return EstadoResposta.prazoAcabando;
  }
  return EstadoResposta.emDia;
}

// dias que faltam pro anuncio sair do mapa (0 quando o prazo ja acabou)
int diasParaSairDoMapa(DateTime aguardandoDesde, {DateTime? agora}) {
  final restante =
      prazoSemResposta - _espera(aguardandoDesde, agora ?? DateTime.now());
  return restante.isNegative ? 0 : restante.inDays;
}

String _contagem(int quantos, String singular, String plural) =>
    quantos == 1 ? '1 $singular' : '$quantos $plural';

// "4 meses", "12 dias" -- ha quanto tempo a mensagem espera resposta. Em mes
// a conta e por mes de 30 dias, igual ao prazo: o texto tem que bater com a
// contagem que tira o anuncio do mapa
String tempoSemResposta(DateTime desde, {DateTime? agora}) {
  final dias = _espera(desde, agora ?? DateTime.now()).inDays;
  if (dias < 1) return 'menos de um dia';
  if (dias < 30) return _contagem(dias, 'dia', 'dias');
  return _contagem(dias ~/ 30, 'mês', 'meses');
}

// etiqueta curta, pro card do anuncio no painel do dono. Vazia quando esta
// tudo em dia -- quem chama usa isso pra nao desenhar etiqueta nenhuma
String etiquetaResposta(DateTime? aguardandoDesde, {DateTime? agora}) {
  final estado = estadoDeResposta(aguardandoDesde, agora: agora);
  switch (estado) {
    case EstadoResposta.emDia:
      return '';
    case EstadoResposta.prazoAcabando:
      final dias = diasParaSairDoMapa(aguardandoDesde!, agora: agora);
      if (dias <= 0) return 'Sai do mapa hoje';
      return 'Sai do mapa em ${_contagem(dias, 'dia', 'dias')}';
    case EstadoResposta.foraDoMapa:
      return 'Fora do mapa';
  }
}

// o aviso por extenso, com o que fazer pra resolver. Vazio quando esta em dia
String avisoDeResposta(DateTime? aguardandoDesde, {DateTime? agora}) {
  final estado = estadoDeResposta(aguardandoDesde, agora: agora);
  switch (estado) {
    case EstadoResposta.emDia:
      return '';
    case EstadoResposta.prazoAcabando:
      final parado = tempoSemResposta(aguardandoDesde!, agora: agora);
      final dias = diasParaSairDoMapa(aguardandoDesde, agora: agora);
      final quando = dias <= 0
          ? 'ainda hoje'
          : 'em ${_contagem(dias, 'dia', 'dias')}';
      return 'Tem mensagem esperando resposta há $parado. '
          'Se ninguém responder, este anúncio sai do mapa $quando. '
          'Responda na aba Chat e o prazo zera.';
    case EstadoResposta.foraDoMapa:
      return 'Este anúncio saiu do mapa e da lista: ficou cinco meses com '
          'mensagem sem resposta. Responda quem te procurou na aba Chat e '
          'ele volta na hora.';
  }
}
