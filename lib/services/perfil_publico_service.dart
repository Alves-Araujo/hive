import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/perfil_publico.dart';
import '../models/usuario.dart';

// espelha os campos nao-sensiveis do Usuario numa colecao separada, legivel
// por qualquer pessoa logada (busca, chat, avaliacoes, perfil publico...)
class PerfilPublicoService {
  PerfilPublicoService._();
  static final PerfilPublicoService instance = PerfilPublicoService._();

  final _colecao = FirebaseFirestore.instance.collection('perfisPublicos');

  // A resposta da imobiliaria ao pedido de vinculo vive AQUI, e quem a escreve
  // e ela, nao o corretor. Entao a sincronizacao nao pode simplesmente mandar
  // o que o perfil local acha: um corretor recem-aprovado que salvasse o
  // perfil antes do app puxar a resposta apagaria a propria aprovacao.
  //
  // Continuando na mesma imobiliaria, o que vale e o que ja esta gravado aqui;
  // trocando de imobiliaria, a resposta da anterior e descartada -- aprovacao
  // vale pra quem aprovou, nao pra qualquer empresa que a pessoa escolher
  Future<void> sincronizar(Usuario usuario) async {
    final atual = await buscarPorUid(usuario.uid);
    final mesmaImobiliaria =
        atual != null && atual.imobiliariaId == usuario.imobiliariaId;

    return _colecao.doc(usuario.uid).set({
      'nome': usuario.nome,
      'nomeBusca': usuario.nomeBusca,
      'fotoUrl': usuario.fotoUrl,
      'tipoUsuario': usuario.tipoUsuario,
      'subtipoCorretor': usuario.subtipoCorretor,
      'papelImobiliaria': usuario.papelImobiliaria,
      'cidade': usuario.cidade,
      'imobiliariaId': usuario.imobiliariaId,
      'vinculoConfirmado': mesmaImobiliaria && atual.vinculoConfirmado,
      'vinculoRecusado': mesmaImobiliaria && atual.vinculoRecusado,
    }, SetOptions(merge: true));
  }

  Future<void> atualizarUltimoAcesso(String uid) {
    return _colecao.doc(uid).set({'ultimoAcesso': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  Future<PerfilPublico?> buscarPorUid(String uid) async {
    if (uid.isEmpty) return null;
    final doc = await _colecao.doc(uid).get();
    if (!doc.exists) return null;
    return PerfilPublico.fromMap(doc.data()!, doc.id);
  }

  // prefixo do nome (mesma tecnica usada no filtro de moradias por texto)
  Future<List<PerfilPublico>> buscarPorPrefixoDeNome(String termo, {int limite = 10}) async {
    if (termo.isEmpty) return [];
    final query = await _colecao
        .orderBy('nomeBusca')
        .startAt([termo])
        .endAt(['$termo'])
        .limit(limite)
        .get();
    return query.docs.map((d) => PerfilPublico.fromMap(d.data(), d.id)).toList();
  }
}
