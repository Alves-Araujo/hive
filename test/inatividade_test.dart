import 'package:flutter_test/flutter_test.dart';
import 'package:moradia_app/models/imovel.dart';
import 'package:moradia_app/utils/inatividade.dart';

import 'package:google_maps_flutter/google_maps_flutter.dart';

// O prazo que tira do mapa anuncio abandonado nao tem como ser conferido no
// aparelho: seria preciso deixar uma mensagem sem resposta por cinco meses
// pra ver o anuncio sumir. Aqui a data entra pronta e a conta e verificada
// nos dois lados da virada.
void main() {
  // um dia antes do fim e o ultimo dia no mapa; o dia seguinte ja e fora
  final agora = DateTime(2026, 9, 23, 12);
  DateTime haDias(int dias) => agora.subtract(Duration(days: dias));

  Imovel anuncio({DateTime? aguardando, TipoListing tipo = TipoListing.moradia}) => Imovel(
        id: 'a1',
        titulo: 'Kitnet perto do Inatel',
        descricao: '',
        preco: 900,
        posicao: const LatLng(-22.25, -45.69),
        tipo: tipo,
        tags: const [],
        endereco: '',
        aguardandoRespostaDesde: aguardando,
      );

  group('estadoDeResposta', () {
    test('sem ninguem esperando, nao ha prazo correndo', () {
      expect(estadoDeResposta(null, agora: agora), EstadoResposta.emDia);
    });

    test('mensagem recente nao avisa nada', () {
      // o aviso so faz sentido perto do fim: avisar no primeiro mes viraria
      // ruido em cima de quem esta respondendo normalmente
      expect(estadoDeResposta(haDias(30), agora: agora), EstadoResposta.emDia);
      expect(estadoDeResposta(haDias(119), agora: agora), EstadoResposta.emDia);
    });

    test('avisa durante o ultimo mes', () {
      expect(estadoDeResposta(haDias(120), agora: agora), EstadoResposta.prazoAcabando);
      expect(estadoDeResposta(haDias(149), agora: agora), EstadoResposta.prazoAcabando);
    });

    test('cinco meses sem resposta tira do mapa', () {
      expect(estadoDeResposta(haDias(150), agora: agora), EstadoResposta.foraDoMapa);
      expect(estadoDeResposta(haDias(400), agora: agora), EstadoResposta.foraDoMapa);
    });

    test('data no futuro nao derruba anuncio nenhum', () {
      // a data e gravada pelo servidor e lida por um aparelho que pode estar
      // com o relogio atrasado -- sem tratar, a diferenca negativa quebraria
      // a conta em vez de simplesmente nao ter prazo nenhum
      expect(
        estadoDeResposta(agora.add(const Duration(days: 2)), agora: agora),
        EstadoResposta.emDia,
      );
    });
  });

  group('diasParaSairDoMapa', () {
    test('conta o que falta, e nunca menos que zero', () {
      expect(diasParaSairDoMapa(haDias(120), agora: agora), 30);
      expect(diasParaSairDoMapa(haDias(149), agora: agora), 1);
      expect(diasParaSairDoMapa(haDias(150), agora: agora), 0);
      expect(diasParaSairDoMapa(haDias(300), agora: agora), 0);
    });
  });

  group('textos do aviso', () {
    test('etiqueta so aparece quando ha prazo correndo', () {
      expect(etiquetaResposta(null, agora: agora), '');
      expect(etiquetaResposta(haDias(10), agora: agora), '');
      expect(etiquetaResposta(haDias(120), agora: agora), 'Sai do mapa em 30 dias');
      expect(etiquetaResposta(haDias(149), agora: agora), 'Sai do mapa em 1 dia');
      expect(etiquetaResposta(haDias(150), agora: agora), 'Fora do mapa');
    });

    test('o aviso diz o que fazer pra desfazer', () {
      final avisando = avisoDeResposta(haDias(130), agora: agora);
      expect(avisando, contains('sai do mapa'));
      expect(avisando, contains('Chat'));

      final fora = avisoDeResposta(haDias(160), agora: agora);
      expect(fora, contains('saiu do mapa'));
      expect(fora, contains('volta'));
    });

    test('a espera e contada em meses de 30 dias, igual ao prazo', () {
      // se o texto dissesse "5 meses" antes de o prazo acabar, o dono leria
      // que ja era tarde enquanto ainda dava pra responder
      expect(tempoSemResposta(haDias(1), agora: agora), '1 dia');
      expect(tempoSemResposta(haDias(29), agora: agora), '29 dias');
      expect(tempoSemResposta(haDias(60), agora: agora), '2 meses');
      expect(tempoSemResposta(haDias(149), agora: agora), '4 meses');
      expect(tempoSemResposta(haDias(150), agora: agora), '5 meses');
    });
  });

  group('Imovel', () {
    test('le a data gravada e decide se sai do mapa', () {
      expect(anuncio().foraDoMapaPorFaltaDeResposta, isFalse);
      expect(anuncio(aguardando: DateTime.now().subtract(const Duration(days: 10)))
          .foraDoMapaPorFaltaDeResposta, isFalse);
      expect(anuncio(aguardando: DateTime.now().subtract(const Duration(days: 200)))
          .foraDoMapaPorFaltaDeResposta, isTrue);
    });

    test('evento nao sai do mapa por falta de resposta', () {
      // evento tem data pra acabar e some da vitrine por conta disso; o prazo
      // existe pra moradia que fica anunciada pra sempre sem ninguem atender
      final velho = anuncio(
        aguardando: DateTime.now().subtract(const Duration(days: 200)),
        tipo: TipoListing.evento,
      );
      expect(velho.estadoResposta, EstadoResposta.emDia);
      expect(velho.foraDoMapaPorFaltaDeResposta, isFalse);
    });

    test('o campo nao vai pro banco na gravacao do anuncio', () {
      // a tela de edicao monta um Imovel novo e grava com merge: se o campo
      // saisse aqui, salvar uma correcao de preco zeraria o prazo de quem
      // esta esperando resposta ha meses
      final mapa = anuncio(aguardando: haDias(100)).toMap();
      expect(mapa.containsKey('aguardandoRespostaDesde'), isFalse);
    });
  });
}
