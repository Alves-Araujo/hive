import 'package:flutter_test/flutter_test.dart';
import 'package:moradia_app/models/imobiliaria.dart';
import 'package:moradia_app/models/passo_guia.dart';
import 'package:moradia_app/models/perfil_publico.dart';
import 'package:moradia_app/models/usuario.dart';
import 'package:moradia_app/utils/passos_guia.dart';

// A conta master da imobiliaria: quem cadastra a empresa junto com o proprio
// perfil e passa a responder por ela.
//
// O que estava errado antes: o formulario da empresa nao aparecia no "concluir
// perfil" -- abria por um "cadastrar nova" solto dentro da folha de escolha da
// imobiliaria. O e-mail que ficava gravado era o DA EMPRESA, e como quem mandava
// na imobiliaria era deduzido desse e-mail, o cadastro nascia sem ninguem por
// ele: quem criou nao editava a empresa, nao aprovava corretor, e os pedidos de
// vinculo ficavam pendentes pra sempre.
//
// O lado do backend (imobiliaria so nasce com donoUid) esta em
// test/rules/cadastro.test.mjs, que precisa do emulador do firestore.
void main() {
  Usuario conta({
    String subtipo = 'empresa',
    String papel = '',
    bool vinculoConfirmado = false,
    bool vinculoRecusado = false,
    bool completo = true,
  }) => Usuario(
    uid: 'u1',
    nome: 'Ana Souza',
    email: 'ana@exemplo.com',
    tipoUsuario: 'corretor',
    subtipoCorretor: subtipo,
    papelImobiliaria: papel,
    imobiliariaId: 'imob1',
    perfilCompleto: completo,
    vinculoConfirmado: vinculoConfirmado,
    vinculoRecusado: vinculoRecusado,
  );

  group('quem responde pela imobiliaria', () {
    test('o admin é a conta master; o corretor da equipe não é', () {
      expect(conta(papel: 'admin').ehAdminImobiliaria, isTrue);
      expect(conta(papel: 'equipe').ehAdminImobiliaria, isFalse);
      expect(conta(papel: '').ehAdminImobiliaria, isFalse);
    });

    test('corretor autônomo nunca é admin, mesmo com o papel gravado', () {
      // o papel só existe dentro de "corretor de empresa" -- trocar o subtipo
      // não pode virar uma porta pra responder por uma imobiliária
      expect(conta(subtipo: 'autonomo', papel: 'admin').ehAdminImobiliaria, isFalse);
    });

    test('o admin anuncia sem esperar aprovação de ninguém', () {
      // é ele quem aprova: ficar pendente seria esperar a si mesmo
      expect(conta(papel: 'admin').podeAnunciar, isTrue);
      expect(conta(papel: 'admin').vinculoPendente, isFalse);
    });

    test('o corretor da equipe continua esperando a imobiliária', () {
      final pendente = conta(papel: 'equipe');
      expect(pendente.vinculoPendente, isTrue);
      expect(pendente.podeAnunciar, isFalse);

      final aprovado = conta(papel: 'equipe', vinculoConfirmado: true);
      expect(aprovado.vinculoPendente, isFalse);
      expect(aprovado.podeAnunciar, isTrue);

      final recusado = conta(papel: 'equipe', vinculoRecusado: true);
      expect(recusado.vinculoPendente, isFalse);
      expect(recusado.podeAnunciar, isFalse);
    });

    test('cadastro sem perfil completo não anuncia nem sendo admin', () {
      expect(conta(papel: 'admin', completo: false).podeAnunciar, isFalse);
    });

    test('o papel sobrevive à ida e volta do firestore', () {
      final salvo = conta(papel: 'admin').toMap();
      expect(Usuario.fromMap(salvo, 'u1').ehAdminImobiliaria, isTrue);
    });
  });

  group('a lista de pedidos que a imobiliaria responde', () {
    PerfilPublico publico(String papel, {bool confirmado = false}) =>
        PerfilPublico(
          uid: 'u1',
          nome: 'Ana Souza',
          tipoUsuario: 'corretor',
          subtipoCorretor: 'empresa',
          papelImobiliaria: papel,
          imobiliariaId: 'imob1',
          vinculoConfirmado: confirmado,
        );

    test('a própria conta master não entra na fila de aprovação', () {
      // sem isso a imobiliária abria o app e encontrava um pedido dela mesma,
      // esperando que alguém a aprovasse
      expect(publico('admin').vinculoPendente, isFalse);
      expect(publico('equipe').vinculoPendente, isTrue);
    });

    test('quem espera aprovação sai da fila quando é aprovado', () {
      expect(publico('equipe', confirmado: true).vinculoPendente, isFalse);
    });

    test('o papel sobrevive à ida e volta do firestore', () {
      final lido = PerfilPublico.fromMap(
        {'nome': 'Ana', 'papelImobiliaria': 'admin', 'imobiliariaId': 'imob1'},
        'u1',
      );
      expect(lido.ehAdminImobiliaria, isTrue);
      expect(lido.vinculoPendente, isFalse);
    });
  });

  group('o cadastro da imobiliaria', () {
    test('guarda o uid de quem a cadastrou', () {
      final salva = Imobiliaria(
        id: '',
        donoUid: 'uidMaster',
        nome: 'Imobiliária Central',
        cnpj: '11.222.333/0001-44',
        email: 'master@pessoal.com',
      ).toMap();

      expect(salva['donoUid'], 'uidMaster');
      expect(Imobiliaria.fromMap(salva, 'imob1').donoUid, 'uidMaster');
    });

    test('cadastro antigo, sem dono, é lido sem quebrar', () {
      // os que nasceram do "cadastrar nova" solto: continuam identificados só
      // pelo e-mail (ver souAImobiliaria em firestore.rules)
      final antiga = Imobiliaria.fromMap(
        {'nome': 'Imobiliária Sem Dono', 'emailBusca': 'contato@empresa.com'},
        'imob2',
      );
      expect(antiga.donoUid, '');
    });

    test('editar o cadastro não troca o dono', () {
      final minha = Imobiliaria(
        id: 'imob1',
        donoUid: 'uidMaster',
        nome: 'Imobiliária Central',
        cnpj: '11.222.333/0001-44',
        email: 'master@pessoal.com',
      );
      expect(minha.copiarCom(nome: 'Outro Nome').donoUid, 'uidMaster');
    });
  });

  group('o guia de quem responde pela imobiliaria', () {
    List<String> titulos(List<PassoGuia> passos) =>
        passos.map((p) => p.titulo).toList();

    String tudo(List<PassoGuia> passos) =>
        passos.map((p) => '${p.titulo}\n${p.texto}').join('\n');

    test('o admin tem guia próprio, separado do corretor de empresa', () {
      expect(chaveGuiaDoPerfil(conta(papel: 'admin')), 'imobiliaria_admin');
      expect(chaveGuiaDoPerfil(conta(papel: 'equipe')), 'corretor_empresa');
    });

    test('o admin aprende a aprovar, não a esperar aprovação', () {
      final passos = passosDoPerfil(conta(papel: 'admin'));
      expect(titulos(passos), contains('Você responde por uma imobiliária'));
      expect(titulos(passos), isNot(contains('Falta a imobiliária aprovar')));
      expect(tudo(passos), contains('Editar imobiliária'));
    });

    test('o corretor da equipe continua sendo mandado esperar', () {
      final passos = passosDoPerfil(conta(papel: 'equipe'));
      expect(titulos(passos), contains('Falta a imobiliária aprovar'));
      expect(titulos(passos), isNot(contains('Você responde por uma imobiliária')));
    });

    test('cadastro antigo ainda responde pelo e-mail do login', () {
      // a conta que entra com o e-mail de uma imobiliária sem dono: o perfil
      // dela não diz nada, então quem informa é a tela do mapa
      final passos = passosDoPerfil(
        conta(papel: 'equipe', vinculoConfirmado: true),
        ehContaDaImobiliaria: true,
      );
      expect(titulos(passos), contains('Você responde por uma imobiliária'));
    });
  });
}
