import 'package:shared_preferences/shared_preferences.dart';

// O guia roda duas vezes por conta: uma no primeiro acesso, com o cadastro
// ainda incompleto, e outra quando o cadastro e concluido (ver
// utils/passos_guia.dart). O que ja rodou fica gravado NO APARELHO, e nao no
// perfil do Firestore: o guia ensina a mexer na tela, entao quem instala o app
// num celular novo merece a explicacao de novo, e quem ja viu nao leva a mesma
// coisa na cara a cada login. Mesmo mecanismo do cache de cores do avatar, ver
// utils/cor_foto.dart
const String _chaveInicial = 'guia_primeiro_acesso';
const String _prefixoPerfil = 'guia_perfil:';

SharedPreferences? _prefs;

// copia em memoria pra consulta SINCRONA: a decisao de rodar o guia acontece
// no primeiro frame da tela principal, e esperar um Future ali deixaria o guia
// aparecer atrasado, por cima de uma tela que a pessoa ja comecou a usar
final Set<String> _vistos = {};

// carregado no main, antes do runApp
Future<void> iniciarTutorial() async {
  try {
    _prefs = await SharedPreferences.getInstance();
    for (final chave in _prefs!.getKeys()) {
      final ehDoGuia =
          chave == _chaveInicial || chave.startsWith(_prefixoPerfil);
      if (ehDoGuia && _prefs!.getBool(chave) == true) _vistos.add(chave);
    }
  } catch (_) {
    // sem prefs o guia reaparece na proxima abertura: chato, mas nao quebra
    // nada e ninguem fica sem entrar no app por causa disso
  }
}

bool get viuGuiaInicial => _vistos.contains(_chaveInicial);

void marcarGuiaInicialVisto() => _marcar(_chaveInicial);

// a chave e por TIPO DE CONTA (ver chaveGuiaDoPerfil): o guia do proprietario
// fala de coisas que o do estudante nem menciona, entao quem abre uma conta
// nova com outro papel no mesmo celular ve o guia dela
bool viuGuiaDoPerfil(String chavePerfil) =>
    _vistos.contains('$_prefixoPerfil$chavePerfil');

void marcarGuiaDoPerfilVisto(String chavePerfil) =>
    _marcar('$_prefixoPerfil$chavePerfil');

void _marcar(String chave) {
  _vistos.add(chave);
  // sem await de proposito: marcar que viu nao pode segurar a tela
  _prefs?.setBool(chave, true);
}
