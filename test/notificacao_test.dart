import 'package:flutter_test/flutter_test.dart';
import 'package:moradia_app/models/chat.dart';
import 'package:moradia_app/utils/tempo.dart';

// O id da conversa e o que decide quem entra nela: e por ele que a regra do
// firestore confere os participantes. Os dois lados montam o id sozinhos, em
// telas diferentes, entao ele PRECISA sair igual dos dois -- e isso nao da
// pra conferir no aparelho sem duas contas.
void main() {
  group('gerarIdChat', () {
    const eu = 'uid_eu';
    const outro = 'uid_outro';
    const imovel = 'imovel123';

    test('mesma dupla da o mesmo id, em qualquer ordem', () {
      // quem abre o anuncio e quem responde pela caixa de entrada passam os
      // uids em ordem trocada, e tem que cair na mesma conversa
      expect(
        gerarIdChat(imovelId: imovel, uidA: eu, uidB: outro),
        gerarIdChat(imovelId: imovel, uidA: outro, uidB: eu),
      );
      expect(
        gerarIdChat(imovelId: '', uidA: eu, uidB: outro),
        gerarIdChat(imovelId: '', uidA: outro, uidB: eu),
      );
    });

    test('formato bate com o que a regra do firestore remonta', () {
      // idDerivado() em firestore.rules refaz exatamente estas duas linhas;
      // se o formato mudar aqui sem mudar la, ninguem cria conversa nova
      expect(gerarIdChat(imovelId: '', uidA: outro, uidB: eu), 'direto_${eu}_$outro');
      expect(gerarIdChat(imovelId: imovel, uidA: outro, uidB: eu), '${imovel}_${eu}_$outro');
    });

    test('cada interessado tem sua conversa no mesmo anuncio', () {
      // era o vazamento: com o id sendo so o imovelId, os dois caiam na
      // mesma sala e liam a conversa um do outro
      const dono = 'uid_dono';
      expect(
        gerarIdChat(imovelId: imovel, uidA: eu, uidB: dono),
        isNot(gerarIdChat(imovelId: imovel, uidA: outro, uidB: dono)),
      );
    });

    test('conversa de anuncio nao colide com a conversa direta da mesma dupla', () {
      expect(
        gerarIdChat(imovelId: imovel, uidA: eu, uidB: outro),
        isNot(gerarIdChat(imovelId: '', uidA: eu, uidB: outro)),
      );
    });
  });

  group('imovelIdDoChat', () {
    const eu = 'uid_eu';
    const outro = 'uid_outro';
    const imovel = 'imovel123';

    test('desmonta o id e devolve o anuncio da conversa', () {
      // quem abre a conversa pelo aviso de mensagem nova so tem o chatId, e
      // e o anuncio que diz qual prazo de resposta essa mensagem mexe
      expect(imovelIdDoChat(gerarIdChat(imovelId: imovel, uidA: eu, uidB: outro)), imovel);
    });

    test('conversa de perfil pra perfil nao tem anuncio', () {
      expect(imovelIdDoChat(gerarIdChat(imovelId: '', uidA: eu, uidB: outro)), '');
    });

    test('conversa antiga, de quando o id era so o imovelId, ainda aponta certo', () {
      expect(imovelIdDoChat(imovel), imovel);
    });
  });

  group('Chat.contatoUid', () {
    test('o contato e sempre o outro lado', () {
      final chat = Chat(id: 'x', participantes: const ['uid_a', 'uid_b']);
      expect(chat.contatoUid('uid_a'), 'uid_b');
      expect(chat.contatoUid('uid_b'), 'uid_a');
    });

    test('conversa sem participantes nao aponta pra ninguem', () {
      expect(Chat(id: 'x', participantes: const []).contatoUid('uid_a'), '');
    });
  });

  group('formatarTempoRelativo', () {
    test('horario ainda pendente do servidor conta como agora', () {
      expect(formatarTempoRelativo(null), 'agora');
    });

    test('escadinha de minuto a semana', () {
      final agora = DateTime.now();
      expect(formatarTempoRelativo(agora.subtract(const Duration(seconds: 20))), 'agora');
      expect(formatarTempoRelativo(agora.subtract(const Duration(minutes: 5))), 'há 5 min');
      expect(formatarTempoRelativo(agora.subtract(const Duration(hours: 3))), 'há 3h');
      expect(formatarTempoRelativo(agora.subtract(const Duration(days: 1, hours: 1))), 'ontem');
      expect(formatarTempoRelativo(agora.subtract(const Duration(days: 4))), 'há 4 dias');
    });

    test('mais de uma semana vira data', () {
      expect(formatarTempoRelativo(DateTime(2026, 3, 7)), '07/03');
    });
  });
}
