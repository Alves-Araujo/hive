import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moradia_app/widgets/abas_persistentes.dart';

void main() {
  Widget montar(
    int indice,
    List<Widget> telas, {
    bool reduzirMovimento = false,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduzirMovimento),
        child: AbasPersistentes(indice: indice, telas: telas),
      ),
    );
  }

  Finder fades() => find.descendant(
    of: find.byType(AbasPersistentes),
    matching: find.byType(FadeTransition),
  );

  testWidgets('anima todos os pares de abas, incluindo ida e volta ao mapa', (
    tester,
  ) async {
    final telas = List.generate(4, (i) => Center(child: Text('Pagina $i')));
    for (var origem = 0; origem < telas.length; origem++) {
      for (var destino = 0; destino < telas.length; destino++) {
        if (origem == destino) continue;
        await tester.pumpWidget(montar(origem, telas));
        await tester.pumpAndSettle();
        await tester.pumpWidget(montar(destino, telas));
        await tester.pump(const Duration(milliseconds: 80));

        expect(find.text('Pagina $origem'), findsOneWidget);
        expect(find.text('Pagina $destino'), findsOneWidget);
        final superior = origem > destino ? origem : destino;
        final fade = tester.widget<FadeTransition>(
          find.ancestor(of: find.text('Pagina $superior'), matching: fades()),
        );
        expect(
          fade.opacity.value,
          inExclusiveRange(0, 1),
          reason: '$origem → $destino precisa animar',
        );
        await tester.pumpAndSettle();
        expect(find.text('Pagina $origem'), findsNothing);
        expect(find.text('Pagina $destino'), findsOneWidget);
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('trocas rapidas preservam estado e nunca aplicam fade ao mapa', (
    tester,
  ) async {
    final mapa = GlobalKey<_PainelState>();
    final resumo = GlobalKey<_PainelState>();
    final telas = [
      _Painel(key: mapa),
      _Painel(key: resumo),
      const Text('Chat'),
    ];
    await tester.pumpWidget(montar(0, telas));
    final mapaOriginal = mapa.currentState;
    final resumoOriginal = resumo.currentState;
    await tester.tap(find.text('Contagem: 0'));
    await tester.pump();
    await tester.pumpWidget(montar(1, telas));
    expect(TickerMode.valuesOf(mapa.currentContext!).enabled, isFalse);
    expect(TickerMode.valuesOf(resumo.currentContext!).enabled, isTrue);
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpWidget(montar(2, telas));
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpWidget(montar(0, telas));
    await tester.pumpAndSettle();
    expect(mapa.currentState, same(mapaOriginal));
    expect(resumo.currentState, same(resumoOriginal));
    expect(find.text('Contagem: 1'), findsOneWidget);
    expect(
      find.ancestor(of: find.byKey(mapa), matching: fades()),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('inverter durante a animacao continua da opacidade atual', (
    tester,
  ) async {
    final telas = [const Text('Mapa'), const Text('Resumo')];
    await tester.pumpWidget(montar(0, telas));
    await tester.pumpWidget(montar(1, telas));
    await tester.pump(const Duration(milliseconds: 70));
    final antes = tester.widget<FadeTransition>(fades()).opacity.value;
    await tester.pumpWidget(montar(0, telas));
    final depois = tester.widget<FadeTransition>(fades()).opacity.value;
    expect(depois, closeTo(antes, 0.00001));
    await tester.pumpAndSettle();
    expect(find.text('Mapa'), findsOneWidget);
    expect(find.text('Resumo'), findsNothing);
  });

  testWidgets('a pagina saindo nao recebe toques', (tester) async {
    final mapa = GlobalKey<_PainelState>();
    final resumo = GlobalKey<_PainelState>();
    final telas = [_Painel(key: mapa), _Painel(key: resumo)];
    await tester.pumpWidget(montar(1, telas));
    await tester.pumpWidget(montar(0, telas));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(
      find.descendant(of: find.byKey(mapa), matching: find.byType(TextButton)),
    );
    expect(mapa.currentState!.contador, 1);
    expect(resumo.currentState!.contador, 0);
    await tester.pumpAndSettle();
  });

  testWidgets('mesma aba nao reinicia a transicao', (tester) async {
    final telas = [const Text('Mapa'), const Text('Resumo')];
    await tester.pumpWidget(montar(0, telas));
    await tester.pumpWidget(montar(1, telas));
    await tester.pumpAndSettle();
    await tester.pumpWidget(montar(1, telas));
    expect(tester.widget<FadeTransition>(fades()).opacity.value, 1);
    expect(find.text('Mapa'), findsNothing);
  });

  testWidgets('reduzir movimento desliga as transicoes em todos os sentidos', (
    tester,
  ) async {
    final telas = [
      const Text('Mapa'),
      const Text('Resumo'),
      const Text('Chat'),
    ];
    for (final indice in [0, 1, 2, 1, 0, 2, 0]) {
      await tester.pumpWidget(montar(indice, telas, reduzirMovimento: true));
      expect(find.text(['Mapa', 'Resumo', 'Chat'][indice]), findsOneWidget);
      expect(
        tester
            .widgetList<FadeTransition>(fades())
            .every((w) => w.opacity.value == 1),
        isTrue,
      );
      expect(find.byType(Text), findsOneWidget);
    }
  });
}

class _Painel extends StatefulWidget {
  const _Painel({super.key});
  @override
  State<_Painel> createState() => _PainelState();
}

class _PainelState extends State<_Painel> {
  int contador = 0;
  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => setState(() => contador++),
      child: Text('Contagem: $contador'),
    ),
  );
}
