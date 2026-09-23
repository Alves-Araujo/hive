import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

// Escritas do anuncio que nao pertencem a nenhuma tela -- hoje, o relogio de
// resposta que tira do mapa o anuncio abandonado (ver utils/inatividade.dart).
//
// Quem chama e o envio de mensagem, dos DOIS lados da conversa: e a mensagem
// que diz se alguem esta esperando resposta ou se o dono ja respondeu. Nao da
// pra decidir isso lendo a caixa de entrada do dono, porque o mapa e lido por
// qualquer um -- e as conversas, nao: as regras so liberam quem participa
// delas. Por isso o estado fica no proprio anuncio, que todo mundo le
class ImovelService {
  ImovelService._();
  static final ImovelService instance = ImovelService._();

  // o mesmo nome esta em firestore.rules, na regra que deixa o interessado
  // ligar o relogio de um anuncio que nao e dele
  static const String campoAguardandoResposta = 'aguardandoRespostaDesde';

  final _colecao = FirebaseFirestore.instance.collection('imoveis');

  // Toda mensagem de um chat de anuncio passa por aqui.
  //
  // - mensagem de interessado: liga o relogio, se ele ja nao estiver ligado.
  //   "Se ja nao estiver" e o que faz o prazo contar da PRIMEIRA mensagem sem
  //   resposta. Contando da ultima, quem insistisse adiaria a propria espera
  // - mensagem do dono: desliga. Responder um interessado ja mostra que o
  //   anuncio tem alguem atras dele -- que e o unico ponto do prazo
  //
  // O campo e apagado (FieldValue.delete) em vez de virar nulo: a regra do
  // firestore confere a AUSENCIA dele pra saber que o relogio esta desligado
  Future<void> registrarMensagem({
    required String imovelId,
    required String remetenteUid,
  }) async {
    // chat de perfil pra perfil nao tem anuncio nenhum envolvido
    if (imovelId.isEmpty || remetenteUid.isEmpty) return;

    try {
      final doc = _colecao.doc(imovelId);
      final snapshot = await doc.get();
      final dados = snapshot.data();
      // anuncio apagado no meio da conversa: o chat continua, o relogio nao
      if (dados == null) return;

      final bool souODono = dados['donoUid'] == remetenteUid;
      final bool relogioLigado = dados[campoAguardandoResposta] != null;

      // nada a fazer: dono respondendo um anuncio que nao devia resposta, ou
      // interessado escrevendo de novo num relogio que ja esta correndo
      if (souODono != relogioLigado) return;

      await doc.update({
        campoAguardandoResposta: souODono
            ? FieldValue.delete()
            : FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // o relogio e consequencia da mensagem, nao a mensagem: se falhar aqui,
      // o que a pessoa escreveu ja foi e nao pode sumir da tela por causa
      // disso. Na proxima mensagem da conversa a conta se acerta sozinha
      debugPrint('não deu pra atualizar o prazo de resposta do anúncio: $e');
    }
  }
}
