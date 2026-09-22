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

  // Minhas conversas, pra caixa de entrada. Sem orderBy na consulta de
  // proposito: array-contains + orderBy exigiria indice composto no firestore,
  // e sao poucas conversas por pessoa -- ordenar aqui sai de graca.
  // atualizadoEm vem nulo enquanto o horario do servidor esta pendente
  // (mensagem recem-enviada), e esse caso conta como "agora", no topo
  Stream<List<Chat>> conversasDe(String uid) {
    return _colecao.where('participantes', arrayContains: uid).snapshots().map((snap) {
      final agora = DateTime.now();
      return snap.docs.map(Chat.fromDoc).toList()
        ..sort((a, b) => (b.atualizadoEm ?? agora).compareTo(a.atualizadoEm ?? agora));
    });
  }

  // O pai e gravado ANTES da mensagem, e nao junto num WriteBatch: a regra da
  // mensagem faz get() no pai, e dentro de um batch esse get() enxerga o
  // estado anterior -- com o pai ainda inexistente, a primeira mensagem de
  // toda conversa seria negada
  Future<void> enviarMensagem({
    required String chatId,
    required Map<String, dynamic> dados,
    required String meuUid,
    required String contatoUid,
    required String previa,
    String imovelId = '',
    String imovelTitulo = '',
  }) async {
    await _colecao.doc(chatId).set({
      'participantes': participantesOrdenados(meuUid, contatoUid),
      // so quando vem preenchido: quem abre a conversa pelo aviso de mensagem
      // nao sabe o anuncio, e gravar vazio aqui apagaria o vinculo que o chat
      // ja tem (e sumiria com o nome do anuncio na caixa de entrada)
      if (imovelId.isNotEmpty) 'imovelId': imovelId,
      if (imovelTitulo.isNotEmpty) 'imovelTitulo': imovelTitulo,
      'ultimaMensagem': previa,
      'atualizadoEm': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await mensagensDe(chatId).add({
      ...dados,
      // a regra exige que bata com quem esta autenticado: sem isso dava pra
      // assinar mensagem com o uid de outra pessoa
      'remetenteUid': meuUid,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
