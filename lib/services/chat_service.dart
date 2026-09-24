import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat.dart';

// Leitura e escrita das conversas. O que da privacidade e o documento pai
// chats/{id}: e o campo participantes dele que as regras consultam pra
// liberar (ou negar) as mensagens da subcolecao.
class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  final _colecao = FirebaseFirestore.instance.collection('chats');

  CollectionReference<Map<String, dynamic>> mensagensDe(String chatId) =>
      _colecao.doc(chatId).collection('mensagens');

  Stream<QuerySnapshot<Map<String, dynamic>>> mensagensRecentes(String chatId) =>
      mensagensDe(chatId).orderBy('timestamp', descending: true).snapshots();

  // Minhas conversas, pra caixa de entrada, da mais recente pra mais antiga.
  //
  // Sem orderBy na consulta de proposito: array-contains + orderBy exigiria
  // indice composto no firestore, e sao poucas conversas por pessoa --
  // ordenar aqui sai de graca. A ordem sai do atualizadoEm que enviarMensagem
  // grava no pai a cada mensagem (texto, foto ou audio), entao quem acabou de
  // escrever sobe pro topo sozinho.
  //
  // E um listener, nao uma leitura: conversa que ja esta na lista muda de
  // previa e de lugar na hora, e conversa que nem existia (alguem escrevendo
  // pela primeira vez) entra sozinha, sem puxar pra atualizar
  Stream<List<Chat>> conversasDe(String uid) {
    return _colecao.where('participantes', arrayContains: uid).snapshots().map((snap) {
      final agora = DateTime.now();
      return snap.docs
          .map(Chat.fromDoc)
          .where((chat) => !chat.ocultoPara.contains(uid))
          .toList()
        ..sort((a, b) => b.ordenadaPor(agora).compareTo(a.ordenadaPor(agora)));
    });
  }

  // some da caixa de entrada de quem apagou, sem mexer no documento nem nas
  // mensagens dela pra frente -- a regra so libera update, nao delete
  Future<void> apagarConversa({required String chatId, required String meuUid}) {
    return _colecao.doc(chatId).update({
      'ocultoPara': FieldValue.arrayUnion([meuUid]),
    });
  }

  // O pai e gravado ANTES da mensagem, e nao junto num WriteBatch: a regra da
  // mensagem faz get() no pai, e dentro de um batch esse get() enxerga o
  // estado anterior -- com o pai ainda inexistente, a primeira mensagem de
  // toda conversa seria negada.
  //
  // "Antes" aqui e a ordem da FILA, nao esperar o servidor confirmar o pai
  // pra so entao escrever a mensagem. O firestore envia as escritas de um
  // mesmo aparelho na ordem em que foram pedidas, entao a regra da mensagem
  // ja encontra o pai la. Esperando a confirmacao, qualquer oscilacao de
  // conexao travava o envio pela metade: o pai ia, a mensagem nem chegava a
  // ser escrita, e quem digitou nao via nada acontecer
  Future<void> enviarMensagem({
    required String chatId,
    required Map<String, dynamic> dados,
    required String meuUid,
    required String contatoUid,
    required String previa,
    String imovelId = '',
    String imovelTitulo = '',
  }) async {
    final pai = _colecao.doc(chatId).set({
      'participantes': participantesOrdenados(meuUid, contatoUid),
      // so quando vem preenchido: quem abre a conversa pelo aviso de mensagem
      // nao sabe o anuncio, e gravar vazio aqui apagaria o vinculo que o chat
      // ja tem (e sumiria com o nome do anuncio na caixa de entrada)
      if (imovelId.isNotEmpty) 'imovelId': imovelId,
      if (imovelTitulo.isNotEmpty) 'imovelTitulo': imovelTitulo,
      'ultimaMensagem': previa,
      'atualizadoEm': FieldValue.serverTimestamp(),
      // quem apagou (eu ou quem recebe) volta a ver a conversa assim que
      // alguem escreve de novo
      'ocultoPara': FieldValue.arrayRemove([meuUid, contatoUid]),
    }, SetOptions(merge: true));

    final corpo = {
      ...dados,
      // a regra exige que bata com quem esta autenticado: sem isso dava pra
      // assinar mensagem com o uid de outra pessoa
      'remetenteUid': meuUid,
      'timestamp': FieldValue.serverTimestamp(),
    };

    try {
      await Future.wait([pai, mensagensDe(chatId).add(corpo)]);
    } on FirebaseException catch (e) {
      // A CORRIDA ENTRE O PAI E A MENSAGEM
      //
      // A regra de create da mensagem faz get() no documento pai pra conferir
      // se quem escreve esta em participantes. Os dois writes saem daqui
      // juntos, mas o servidor avalia cada um por conta propria: quando a
      // mensagem e avaliada antes de o pai ter sido gravado, o get() nao acha
      // nada e a escrita volta como permission-denied.
      //
      // Acontecia na primeira mensagem de uma conversa e, de vez em quando,
      // sempre que a rede atrasava um dos dois. Quem escreveu via "nao deu pra
      // enviar" e o texto voltava pro campo, mesmo com a conversa funcionando.
      //
      // Aqui a gente espera o pai ficar de pe e escreve a mensagem de novo,
      // que e quando a regra finalmente encontra o que procura. So no
      // permission-denied: nesse caso o firestore ja desfez a escrita local,
      // entao repetir nao duplica mensagem. Qualquer outro erro sobe pra
      // tela como antes.
      if (e.code != 'permission-denied') rethrow;

      // se quem falhou foi o pai, este await levanta o erro dele e a mensagem
      // nao e reescrita -- nao adianta insistir sem o pai
      await pai;
      await mensagensDe(chatId).add(corpo);
    }
  }
}
