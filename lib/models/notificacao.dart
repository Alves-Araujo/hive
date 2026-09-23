import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/texto.dart';

// o que aconteceu -- decide o icone, a cor e pra onde o toque leva
enum TipoNotificacao {
  novaMoradia,
  novoEvento,
  novaImobiliaria,
  novaMensagem,
  novaAvaliacao,
  // a imobiliaria aprovou (ou recusou) o pedido de vinculo -- chega so pro
  // corretor que pediu. O pedido no sentido contrario nao vira aviso gravado:
  // a imobiliaria nao e uma conta, e identificada pelo e-mail, entao quem
  // administra recebe os pedidos ao entrar (ver map_screen)
  vinculoRespondido,
}

// Existem dois tipos de destino, gravados em lugares diferentes:
// - avisos pra TODO mundo (anuncio novo, imobiliaria nova) ficam na colecao
//   "notificacoes", e cada um ignora os que ele mesmo gerou
// - avisos pra UMA pessoa (mensagem, avaliacao) ficam em
//   "usuarios/{uid}/notificacoes", que so o dono le
// Separar evita indice composto no firestore: cada consulta e so um orderBy
//
// Quem recebe o aviso de uma mensagem nao precisa mais ser calculado: toda
// conversa e entre duas pessoas (ver models/chat.dart), entao o destinatario
// e sempre o outro lado. Antes o chat de anuncio juntava todos os
// interessados numa sala so, e era preciso descobrir a quem avisar

class Notificacao {
  final String id;
  final TipoNotificacao tipo;
  final String titulo;
  final String corpo;
  final String autorUid;

  // id do que abrir ao tocar: imovel, imobiliaria ou chat, conforme o tipo
  final String alvoId;

  // so pra mensagem: com quem o DESTINATARIO conversa ao abrir o aviso (ou
  // seja, quem mandou) e o titulo do anuncio, quando o chat e de um anuncio
  final String contatoUid;
  final String imovelTitulo;

  final DateTime? criadoEm;

  Notificacao({
    required this.id,
    required this.tipo,
    required this.titulo,
    required this.corpo,
    required this.autorUid,
    this.alvoId = '',
    this.contatoUid = '',
    this.imovelTitulo = '',
    this.criadoEm,
  });

  factory Notificacao.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    // criadoEm vem nulo enquanto o horario do servidor esta pendente (aviso
    // recem-gravado) -- quem ordena trata nulo como "agora"
    final map = doc.data() ?? {};
    return Notificacao(
      id: doc.id,
      tipo: TipoNotificacao.values.firstWhere(
        (t) => t.name == map['tipo'],
        orElse: () => TipoNotificacao.novaMoradia,
      ),
      titulo: normalizarTracosOuVazio(map['titulo']),
      corpo: normalizarTracosOuVazio(map['corpo']),
      autorUid: map['autorUid'] ?? '',
      alvoId: map['alvoId'] ?? '',
      contatoUid: map['contatoUid'] ?? '',
      imovelTitulo: normalizarTracosOuVazio(map['imovelTitulo']),
      criadoEm: (map['criadoEm'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tipo': tipo.name,
      'titulo': normalizarTracos(titulo),
      'corpo': normalizarTracos(corpo),
      'autorUid': autorUid,
      'alvoId': alvoId,
      if (contatoUid.isNotEmpty) 'contatoUid': contatoUid,
      if (imovelTitulo.isNotEmpty) 'imovelTitulo': normalizarTracos(imovelTitulo),
      'criadoEm': FieldValue.serverTimestamp(),
    };
  }
}
