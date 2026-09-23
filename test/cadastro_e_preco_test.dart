import 'package:flutter_test/flutter_test.dart';
import 'package:moradia_app/models/usuario.dart';
import 'package:moradia_app/utils/moderacao.dart';
import 'package:moradia_app/utils/moeda.dart';

// As tres regras de negocio que vieram do relatorio de bugs e nao dependem de
// tela: evento pode ser gratuito, nome aceita acento, e quem pode anunciar.
void main() {
  group('preco de evento gratuito', () {
    test('sem valor o anuncio aparece como "Gratuito", nao como zero em reais', () {
      expect(formatarPrecoOuGratuito(0), 'Gratuito');
      // valor negativo nao existe no formulario, mas se chegar do banco e o
      // mesmo caso: nao ha preco a mostrar
      expect(formatarPrecoOuGratuito(-10), 'Gratuito');
    });

    test('com valor continua mostrando o preco', () {
      expect(formatarPrecoOuGratuito(35), 'R\$35,00');
      expect(formatarPrecoOuGratuito(1200), 'R\$1.200,00');
    });
  });

  group('nome com acento', () {
    test('acentuacao do portugues passa', () {
      for (final nome in ['João Gonçalves', 'Inês Araújo', 'Ângela Sá', 'Núria Peña']) {
        expect(nomeTemCaracteresValidos(nome), isTrue, reason: nome);
      }
    });

    test('hifen e apostrofo de sobrenome passam', () {
      expect(nomeTemCaracteresValidos('Ana Paula Silva-Costa'), isTrue);
      expect(nomeTemCaracteresValidos("Maria D'Ávila"), isTrue);
    });

    test('numero e simbolo continuam de fora', () {
      expect(nomeTemCaracteresValidos('Ana 2'), isFalse);
      expect(nomeTemCaracteresValidos('Ana <3'), isFalse);
      expect(nomeTemCaracteresValidos('ana@email.com'), isFalse);
    });

    test('nome com acento nao colide com a checagem de palavrao', () {
      expect(contemPalavraImpropria('João Gonçalves'), isFalse);
    });
  });

  group('quem pode anunciar', () {
    Usuario conta({
      required String tipo,
      String subtipo = '',
      bool completo = true,
      bool confirmado = false,
    }) => Usuario(
      uid: 'u1',
      nome: 'Teste',
      email: 't@e.com',
      tipoUsuario: tipo,
      subtipoCorretor: subtipo,
      perfilCompleto: completo,
      imobiliariaId: subtipo == 'empresa' ? 'imob1' : '',
      vinculoConfirmado: confirmado,
    );

    test('proprietario anuncia', () {
      expect(conta(tipo: 'proprietario').podeAnunciar, isTrue);
    });

    test('estudante nao anuncia', () {
      expect(conta(tipo: 'estudante').podeAnunciar, isFalse);
    });

    test('corretor autonomo anuncia -- nao ha imobiliaria pra aprovar', () {
      expect(conta(tipo: 'corretor', subtipo: 'autonomo').podeAnunciar, isTrue);
    });

    test('corretor de empresa so anuncia depois de aprovado', () {
      final pendente = conta(tipo: 'corretor', subtipo: 'empresa');
      expect(pendente.podeAnunciar, isFalse);
      expect(pendente.vinculoPendente, isTrue);

      final aprovado = conta(tipo: 'corretor', subtipo: 'empresa', confirmado: true);
      expect(aprovado.podeAnunciar, isTrue);
      expect(aprovado.vinculoPendente, isFalse);
    });

    test('vinculo recusado nao fica pendente pra sempre', () {
      final recusado = Usuario(
        uid: 'u1',
        nome: 'Teste',
        email: 't@e.com',
        tipoUsuario: 'corretor',
        subtipoCorretor: 'empresa',
        perfilCompleto: true,
        imobiliariaId: 'imob1',
        vinculoRecusado: true,
      );
      expect(recusado.vinculoPendente, isFalse);
      expect(recusado.podeAnunciar, isFalse);
    });

    test('perfil incompleto nao anuncia, seja qual for o tipo', () {
      expect(conta(tipo: 'proprietario', completo: false).podeAnunciar, isFalse);
      expect(conta(tipo: 'corretor', subtipo: 'autonomo', completo: false).podeAnunciar, isFalse);
    });
  });
}
