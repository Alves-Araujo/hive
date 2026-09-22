import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/texto.dart';

// Uma conversa e sempre entre DUAS pessoas. O documento chats/{id} guarda
// quem sao elas, e e esse campo que as regras do firestore leem pra decidir
// quem entra -- a subcolecao de mensagens nao decide nada sozinha.
//
// O id e derivado dos participantes, entao os dois lados chegam nele sozinhos
// (quem abre o anuncio e quem recebe o aviso), sem precisar procurar a sala.
// A regra idDerivado() em firestore.rules remonta esse mesmo id na hora de
// criar: se o formato mudar aqui, tem que mudar la junto.
const String prefixoChatDireto = 'direto';

// no chat de perfil -> perfil nao ha anuncio, e o prefixo e fixo; no de
// anuncio, o proprio imovelId separa as conversas de cada interessado
String gerarIdChat({required String imovelId, required String uidA, required String uidB}) {
  final ordenados = [uidA, uidB]..sort();
  final prefixo = imovelId.isEmpty ? prefixoChatDireto : imovelId;
  return '${prefixo}_${ordenados[0]}_${ordenados[1]}';
}

// a ordem tambem vai gravada no documento: a regra exige p[0] < p[1], que e o
// que garante os dois lados no mesmo id (e barra conversa de alguem consigo
// mesmo)
List<String> participantesOrdenados(String uidA, String uidB) => [uidA, uidB]..sort();

class Chat {
  final String id;
  final List<String> participantes;

  // vazio no chat direto
  final String imovelId;
  final String imovelTitulo;

  // previa mostrada na caixa de entrada -- fica no proprio documento pra
  // lista nao precisar abrir um stream de mensagens por conversa
  final String ultimaMensagem;
  final DateTime? atualizadoEm;

  Chat({
    required this.id,
    required this.participantes,
    this.imovelId = '',
    this.imovelTitulo = '',
    this.ultimaMensagem = '',
    this.atualizadoEm,
  });

  // o outro lado da conversa: e quem da nome e foto ao item da lista
  String contatoUid(String meuUid) =>
      participantes.firstWhere((uid) => uid != meuUid, orElse: () => '');

  factory Chat.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? {};
    return Chat(
      id: doc.id,
      participantes: List<String>.from(map['participantes'] ?? const []),
      imovelId: map['imovelId'] ?? '',
      imovelTitulo: normalizarTracosOuVazio(map['imovelTitulo']),
      ultimaMensagem: normalizarTracosOuVazio(map['ultimaMensagem']),
      // nulo enquanto o horario do servidor esta pendente (mensagem
      // recem-enviada) -- quem ordena trata nulo como "agora"
      atualizadoEm: (map['atualizadoEm'] as Timestamp?)?.toDate(),
    );
  }
}
