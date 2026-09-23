import 'usuario.dart';
import '../utils/alvos_tutorial.dart';

// pedido de "rodar o guia de novo" (ver pedidoDeGuiaGlobal, em main.dart).
// Carrega o perfil porque o guia e diferente por tipo de conta, e o flag da
// imobiliaria porque so o mapa sabe se este e-mail responde por uma
class PedidoDeGuia {
  final Usuario perfil;
  final bool ehContaDaImobiliaria;

  const PedidoDeGuia({
    required this.perfil,
    required this.ehContaDaImobiliaria,
  });
}

// Um passo do guia interativo: o que acender na tela e o que dizer sobre ele.
//
// A diferenca pro tutorial em slides que existia antes: aqui o passo nao
// desenha uma copia do app, ele aponta pro proprio botao. O texto e curto de
// proposito -- quem esta lendo tem o botao aceso na frente e a mao ja no
// caminho dele.
class PassoGuia {
  final AlvoTutorial alvo;
  final String titulo;
  final String texto;

  // aba que este passo mostra (0 Mapa, 1 Resumo, 2 Chat, 3 Imóveis).
  //
  // Quando vem preenchida, o guia troca de aba sozinho se a pessoa usar o
  // "Próximo" -- tocar no alvo leva pro mesmo lugar, entao os dois caminhos
  // terminam na mesma tela e o passo seguinte fala do que esta na frente dela
  final int? abaParaAbrir;

  // toque no alvo abre uma folha ou outra tela por cima (filtros,
  // configuracoes, perfil). O guia some enquanto ela esta aberta e volta
  // depois; esses passos nao avancam pelo toque, senao a pessoa voltaria da
  // folha e encontraria o guia ja falando de outra coisa
  final bool abreOutraTela;

  const PassoGuia({
    required this.titulo,
    required this.texto,
    this.alvo = AlvoTutorial.nenhum,
    this.abaParaAbrir,
    this.abreOutraTela = false,
  });
}
