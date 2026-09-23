import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moradia_app/models/passo_guia.dart';
import 'package:moradia_app/models/usuario.dart';
import 'package:moradia_app/utils/alvos_tutorial.dart';
import 'package:moradia_app/utils/passos_guia.dart';
import 'package:moradia_app/widgets/guia_interativo.dart';

void main() {
  Usuario perfil(
    String tipo, {
    String subtipo = '',
    bool completo = true,
    bool vinculoConfirmado = false,
  }) => Usuario(
    uid: 'u1',
    nome: 'Ana Souza',
    email: 'ana@exemplo.com',
    tipoUsuario: tipo,
    subtipoCorretor: subtipo,
    perfilCompleto: completo,
    vinculoConfirmado: vinculoConfirmado,
  );

  List<String> titulos(List<PassoGuia> passos) =>
      passos.map((p) => p.titulo).toList();

  String tudo(List<PassoGuia> passos) =>
      passos.map((p) => '${p.titulo}\n${p.texto}').join('\n');

  group('o que cada parte do guia ensina', () {
    test('a primeira parte só fala do que funciona sem cadastro', () {
      final passos = passosPrimeiroAcesso;
      // nada de anunciar nem de avaliar: são coisas que essa pessoa ainda não
      // pode fazer, e apontar pra um botão que não existe quebraria o furo
      expect(tudo(passos), isNot(contains('"Anunciar"')));
      expect(
        passos.map((p) => p.alvo),
        isNot(contains(AlvoTutorial.anunciar)),
      );
      expect(passos.map((p) => p.alvo), isNot(contains(AlvoTutorial.abaImoveis)));
      // e termina mandando concluir o cadastro, no avatar
      expect(passos.last.alvo, AlvoTutorial.avatar);
      expect(tudo(passos), contains('Concluir Perfil'));
    });

    test('a primeira parte passeia pelas três abas liberadas', () {
      final abas = passosPrimeiroAcesso
          .map((p) => p.abaParaAbrir)
          .whereType<int>()
          .toList();
      expect(abas, containsAllInOrder(<int>[1, 2, 0]));
    });

    test('estudante não aprende a anunciar, porque não pode', () {
      final passos = passosDoPerfil(perfil('estudante'));
      expect(passos.map((p) => p.alvo), isNot(contains(AlvoTutorial.anunciar)));
      expect(titulos(passos), isNot(contains('Toque em Imóveis')));
      expect(titulos(passos), contains('Toque em Chat'));
      expect(tudo(passos), contains('Avaliações'));
    });

    test('proprietário recebe painel, publicação e o prazo de resposta', () {
      final passos = passosDoPerfil(perfil('proprietario'));
      expect(
        titulos(passos),
        containsAll(<String>[
          'Toque em Imóveis',
          'Responda quem te procura',
          'Publique seu primeiro anúncio',
        ]),
      );
      expect(tudo(passos), contains('cinco meses'));
      expect(passos.map((p) => p.alvo), contains(AlvoTutorial.anunciar));
    });

    test('corretor de empresa sem aprovação não vê o botão de anunciar', () {
      final pendente = passosDoPerfil(perfil('corretor', subtipo: 'empresa'));
      expect(titulos(pendente), contains('Falta a imobiliária aprovar'));
      // o botão "Anunciar" não está na tela dele, então o guia não aponta
      expect(
        pendente.map((p) => p.alvo),
        isNot(contains(AlvoTutorial.anunciar)),
      );
      // o painel continua, porque a aba existe desde o cadastro
      expect(titulos(pendente), contains('Toque em Imóveis'));

      final aprovado = passosDoPerfil(
        perfil('corretor', subtipo: 'empresa', vinculoConfirmado: true),
      );
      expect(titulos(aprovado), isNot(contains('Falta a imobiliária aprovar')));
      expect(aprovado.map((p) => p.alvo), contains(AlvoTutorial.anunciar));
    });

    test('conta que responde por imobiliária ganha o passo dos pedidos', () {
      final com = passosDoPerfil(
        perfil('corretor', subtipo: 'autonomo'),
        ehContaDaImobiliaria: true,
      );
      final sem = passosDoPerfil(perfil('corretor', subtipo: 'autonomo'));
      expect(titulos(com), contains('Você responde por uma imobiliária'));
      expect(titulos(sem), isNot(contains('Você responde por uma imobiliária')));
      expect(com.length, sem.length + 1);
    });

    test('a chave separa os dois subtipos de corretor', () {
      expect(chaveGuiaDoPerfil(perfil('estudante')), 'estudante');
      expect(
        chaveGuiaDoPerfil(perfil('corretor', subtipo: 'autonomo')),
        'corretor_autonomo',
      );
      expect(
        chaveGuiaDoPerfil(perfil('corretor', subtipo: 'empresa')),
        'corretor_empresa',
      );
    });

    test('nenhum passo fica sem texto', () {
      final listas = [
        passosPrimeiroAcesso,
        passosDoPerfil(perfil('estudante')),
        passosDoPerfil(perfil('proprietario')),
        passosDoPerfil(perfil('corretor', subtipo: 'empresa')),
      ];
      for (final lista in listas) {
        expect(lista, isNotEmpty);
        for (final passo in lista) {
          expect(passo.titulo.trim(), isNotEmpty);
          expect(passo.texto.trim(), isNotEmpty);
        }
      }
    });
  });

  group('o guia por cima da tela', () {
    // dois botões de mentira no lugar de telas de verdade: um vira o alvo do
    // passo, o outro serve pra provar que o escuro segura o toque
    Widget hospedeiro(
      List<PassoGuia> passos, {
      required VoidCallback aoTocarAlvo,
      required VoidCallback aoTocarFora,
      required VoidCallback aoConcluir,
      required ValueChanged<int> aoTrocarAba,
    }) => MaterialApp(
      // disableAnimations por dentro do MaterialApp: o anel do furo pulsa em
      // loop e, sem isso, pumpAndSettle nunca encontraria um quadro parado
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Stack(
        children: [
          Scaffold(
            body: Column(
              children: [
                const SizedBox(height: 120),
                GestureDetector(
                  key: chaveAlvo(AlvoTutorial.busca),
                  onTap: aoTocarAlvo,
                  child: Container(width: 220, height: 48, color: Colors.red),
                ),
                const SizedBox(height: 40),
                GestureDetector(
                  onTap: aoTocarFora,
                  child: Container(width: 220, height: 48, color: Colors.blue),
                ),
              ],
            ),
          ),
          Positioned.fill(
            child: GuiaInterativo(
              passos: passos,
              onTrocarAba: aoTrocarAba,
              onConcluir: aoConcluir,
            ),
          ),
        ],
      ),
    );

    const passosDeTeste = [
      PassoGuia(
        alvo: AlvoTutorial.busca,
        titulo: 'Procure um lugar',
        texto: 'Digite aqui.',
        abaParaAbrir: 1,
      ),
      PassoGuia(titulo: 'Último', texto: 'Fim.'),
    ];

    testWidgets('o toque atravessa o furo: chega no botão e avança o guia', (
      tester,
    ) async {
      var tocouAlvo = 0, tocouFora = 0, concluiu = 0;
      final abas = <int>[];
      await tester.pumpWidget(
        hospedeiro(
          passosDeTeste,
          aoTocarAlvo: () => tocouAlvo++,
          aoTocarFora: () => tocouFora++,
          aoConcluir: () => concluiu++,
          aoTrocarAba: abas.add,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Procure um lugar'), findsOneWidget);
      expect(find.text('1 de 2'), findsOneWidget);

      await tester.tap(find.byKey(chaveAlvo(AlvoTutorial.busca)));
      await tester.pumpAndSettle();

      // o botão de verdade recebeu o toque...
      expect(tocouAlvo, 1);
      // ...e o guia seguiu sozinho, sem trocar a aba (quem trocou foi a pessoa)
      expect(find.text('Último'), findsOneWidget);
      expect(abas, isEmpty);
      expect(concluiu, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('tocar no escuro não avança nem vaza pro que está atrás', (
      tester,
    ) async {
      var tocouAlvo = 0, tocouFora = 0, concluiu = 0;
      await tester.pumpWidget(
        hospedeiro(
          passosDeTeste,
          aoTocarAlvo: () => tocouAlvo++,
          aoTocarFora: () => tocouFora++,
          aoConcluir: () => concluiu++,
          aoTrocarAba: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(40, 40));
      await tester.pumpAndSettle();

      expect(tocouFora, 0);
      expect(tocouAlvo, 0);
      expect(concluiu, 0);
      expect(find.text('Procure um lugar'), findsOneWidget);
    });

    testWidgets('"Próximo" troca de aba sozinho e o fim conclui', (
      tester,
    ) async {
      var concluiu = 0;
      final abas = <int>[];
      await tester.pumpWidget(
        hospedeiro(
          passosDeTeste,
          aoTocarAlvo: () {},
          aoTocarFora: () {},
          aoConcluir: () => concluiu++,
          aoTrocarAba: abas.add,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Próximo'));
      await tester.pumpAndSettle();
      // quem não toca no alvo não deveria ficar preso: o guia leva pra aba
      expect(abas, [1]);
      expect(find.text('Último'), findsOneWidget);

      await tester.tap(find.text('Entendi'));
      await tester.pumpAndSettle();
      expect(concluiu, 1);
    });

    testWidgets('"Sair do guia" encerra em qualquer passo', (tester) async {
      var concluiu = 0;
      await tester.pumpWidget(
        hospedeiro(
          passosDeTeste,
          aoTocarAlvo: () {},
          aoTocarFora: () {},
          aoConcluir: () => concluiu++,
          aoTrocarAba: (_) {},
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sair do guia'));
      await tester.pumpAndSettle();
      expect(concluiu, 1);
    });

    testWidgets('passo sem alvo escurece tudo e centraliza o cartão', (
      tester,
    ) async {
      var tocouFora = 0;
      await tester.pumpWidget(
        hospedeiro(
          const [PassoGuia(titulo: 'Bem-vindo', texto: 'Olá.')],
          aoTocarAlvo: () {},
          aoTocarFora: () => tocouFora++,
          aoConcluir: () {},
          aoTrocarAba: (_) {},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Bem-vindo'), findsOneWidget);
      expect(find.text('Entendi'), findsOneWidget);
      // sem furo, nada atrás recebe toque
      await tester.tapAt(const Offset(40, 40));
      await tester.pumpAndSettle();
      expect(tocouFora, 0);
    });

    testWidgets('alvo que não existe na tela vira cartão, sem quebrar', (
      tester,
    ) async {
      await tester.pumpWidget(
        hospedeiro(
          const [
            PassoGuia(
              // ninguém montou esse botão neste teste
              alvo: AlvoTutorial.anunciar,
              titulo: 'Anuncie',
              texto: 'Sem botão na tela.',
            ),
          ],
          aoTocarAlvo: () {},
          aoTocarFora: () {},
          aoConcluir: () {},
          aoTrocarAba: (_) {},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Anuncie'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('o guia inteiro do proprietário anda até o fim', (
      tester,
    ) async {
      var concluiu = 0;
      final passos = passosDoPerfil(perfil('proprietario'));
      await tester.pumpWidget(
        hospedeiro(
          passos,
          aoTocarAlvo: () {},
          aoTocarFora: () {},
          aoConcluir: () => concluiu++,
          aoTrocarAba: (_) {},
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 1; i < passos.length; i++) {
        expect(find.text('$i de ${passos.length}'), findsOneWidget);
        await tester.tap(find.text('Próximo'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Entendi'));
      await tester.pumpAndSettle();
      expect(concluiu, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
