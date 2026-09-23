import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moradia_app/widgets/seletor_tipo_resumo.dart';

void main() {
  Widget montar(
    String valor, {
    bool reduzir = false,
    double fonte = 1,
    double largura = 360,
    ValueChanged<String>? aoMudar,
  }) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: MediaQuery(
          data: MediaQueryData(
            disableAnimations: reduzir,
            textScaler: TextScaler.linear(fonte),
          ),
          child: SizedBox(
            width: largura,
            height: 80,
            child: SeletorTipoResumo(
              selecionado: valor,
              onChanged: aoMudar ?? (_) {},
            ),
          ),
        ),
      ),
    ),
  );
  final destaque = find.byKey(const ValueKey('destaque-tipo-resumo'));

  testWidgets('destaque desliza nos seis caminhos, sem saltar para o destino', (
    tester,
  ) async {
    for (final origem in SeletorTipoResumo.opcoes) {
      for (final destino in SeletorTipoResumo.opcoes) {
        if (origem == destino) continue;
        await tester.pumpWidget(montar(origem));
        await tester.pumpAndSettle();
        final inicio = tester.getCenter(destaque).dx;
        final fim = tester
            .getCenter(find.widgetWithText(TextButton, destino))
            .dx;
        await tester.pumpWidget(montar(destino));
        expect(tester.getCenter(destaque).dx, closeTo(inicio, .01));
        await tester.pump(const Duration(milliseconds: 80));
        final meio = tester.getCenter(destaque).dx;
        expect(meio, greaterThan(inicio < fim ? inicio : fim));
        expect(meio, lessThan(inicio > fim ? inicio : fim));
        await tester.pumpAndSettle();
        expect(tester.getCenter(destaque).dx, closeTo(fim, .01));
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'troca rápida inverte a partir da posição atual e respeita movimento reduzido',
    (tester) async {
      await tester.pumpWidget(montar('Todos'));
      await tester.pumpAndSettle();
      final inicio = tester.getCenter(destaque).dx;
      await tester.pumpWidget(montar('Eventos'));
      await tester.pump(const Duration(milliseconds: 60));
      final interrompido = tester.getCenter(destaque).dx;
      await tester.pumpWidget(montar('Todos'));
      expect(tester.getCenter(destaque).dx, closeTo(interrompido, .01));
      await tester.pumpAndSettle();
      expect(tester.getCenter(destaque).dx, closeTo(inicio, .01));
      await tester.pumpWidget(montar('Eventos', reduzir: true));
      await tester.pump();
      expect(
        tester.getCenter(destaque).dx,
        closeTo(
          tester.getCenter(find.widgetWithText(TextButton, 'Eventos')).dx,
          .01,
        ),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'toque muda o filtro uma vez e fonte grande permite rolar sem cortar rótulos',
    (tester) async {
      final valores = <String>[];
      await tester.pumpWidget(
        montar('Todos', fonte: 2, largura: 280, aoMudar: valores.add),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Todos'));
      expect(valores, isEmpty);
      await tester.ensureVisible(find.widgetWithText(TextButton, 'Eventos'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Eventos'));
      expect(valores, ['Eventos']);
      expect(tester.takeException(), isNull);
    },
  );
}
