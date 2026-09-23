import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

// Avisa que a pilha de telas mudou.
//
// Existe por causa do guia interativo: quando a pessoa toca no alvo e abre a
// folha de filtros (ou o perfil, ou o formulario de anuncio), o guia precisa
// sumir e voltar sozinho quando ela fechar. Sem isso, o cartao do guia ficaria
// escondido atras da folha e o furo apontaria pra um botao que nao esta mais
// na tela.
//
// O guia nao pergunta "qual rota abriu": ele so se redesenha e olha o proprio
// ModalRoute.isCurrent. Por isso aqui basta um contador -- quem escuta decide
// o que fazer com a novidade.
final ValueNotifier<int> mudancasDeRota = ValueNotifier(0);

// instancia unica, criada uma vez: o MaterialApp e reconstruido a cada troca
// de tema, e um observador novo a cada build sairia registrando e
// desregistrando do Navigator sem parar
final ObservadorDeRotas observadorDeRotas = ObservadorDeRotas();

class ObservadorDeRotas extends NavigatorObserver {
  void _mudou() {
    // Uma rota pode ser empilhada durante um build (um showModalBottomSheet
    // disparado de dentro de um callback de frame, por exemplo). Mexer no
    // notifier ali no meio marcaria widget sujo durante o proprio build --
    // esperar o fim do frame evita isso e nao atrasa nada perceptivel
    SchedulerBinding.instance.addPostFrameCallback((_) {
      mudancasDeRota.value++;
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _mudou();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _mudou();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _mudou();

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _mudou();
}
