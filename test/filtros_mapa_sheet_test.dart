import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moradia_app/models/filtro_state.dart';
import 'package:moradia_app/widgets/filtros_mapa_sheet.dart';

void main() {
  Future<void> abrir(
    WidgetTester tester, {
    FiltrosMapa? inicial,
    void Function(FiltrosMapa?)? aoFechar,
    ValueNotifier<int>? atualizacoes,
    bool Function()? proximidade,
    int Function(FiltrosMapa)? contar,
    double fonte = 1,
    double teclado = 0,
    Brightness brilho = Brightness.dark,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dados = atualizacoes ?? ValueNotifier(0);
    if (atualizacoes == null) addTearDown(dados.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: brilho,
          colorSchemeSeed: const Color(0xFF00509E),
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(fonte),
            viewInsets: EdgeInsets.only(bottom: teclado),
          ),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                child: const Text('Abrir'),
                onPressed: () async {
                  final resultado = await showModalBottomSheet<FiltrosMapa>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) => FiltrosMapaSheet(
                      inicial: inicial ?? FiltrosMapa(),
                      atualizacoes: dados,
                      proximidadeDisponivel: proximidade ?? () => true,
                      contarImoveis: contar ?? (f) => f.tipos.isEmpty ? 8 : 2,
                    ),
                  );
                  aoFechar?.call(resultado);
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'alterna abas preservando rascunho e aplica critérios separados',
    (tester) async {
      FiltrosMapa? aplicado;
      await abrir(tester, aoFechar: (f) => aplicado = f);
      await tester.ensureVisible(find.text('Tipo de imóvel'));
      await tester.tap(find.text('Tipo de imóvel'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.widgetWithText(FilterChip, 'Casa'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilterChip, 'Casa'));
      await tester.pumpAndSettle();
      expect(find.text('2 imóveis encontrados'), findsOneWidget);
      await tester.tap(find.text('No mapa'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('categoria-mercado')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Imóveis · 1'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Casa'))
            .selected,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('aplicar-filtros')));
      await tester.pumpAndSettle();
      expect(aplicado!.tipos, {'Casa'});
      expect(aplicado!.categoriasOcultas, {'mercado'});
      expect(aplicado!.localidades, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('fechar descarta alterações; limpar só altera o rascunho', (
    tester,
  ) async {
    final inicial = FiltrosMapa(
      tipos: ['Casa'],
      contas: ['Água'],
      categoriasOcultas: ['evento'],
    );
    var fechado = false;
    FiltrosMapa? resultado;
    await abrir(
      tester,
      inicial: inicial,
      aoFechar: (f) {
        fechado = true;
        resultado = f;
      },
    );
    await tester.tap(find.text('Limpar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Fechar filtros'));
    await tester.pumpAndSettle();
    expect(fechado, isTrue);
    expect(resultado, isNull);
    expect(inicial.tipos, {'Casa'});
    expect(inicial.contas, {'Água'});
    expect(inicial.categoriasOcultas, {'evento'});
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'contagem atualiza com os dados e permite aplicar zero resultados',
    (tester) async {
      final dados = ValueNotifier(0);
      addTearDown(dados.dispose);
      var quantidade = 3;
      FiltrosMapa? aplicado;
      await abrir(
        tester,
        atualizacoes: dados,
        contar: (_) => quantidade,
        aoFechar: (f) => aplicado = f,
      );
      expect(find.text('3 imóveis encontrados'), findsOneWidget);
      quantidade = 0;
      dados.value++;
      await tester.pumpAndSettle();
      expect(find.text('Nenhum imóvel com esses filtros'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('aplicar-filtros')));
      await tester.pumpAndSettle();
      expect(aplicado, isNotNull);
    },
  );

  testWidgets(
    'preço funciona com teclado aberto e não perde controller ao fechar',
    (tester) async {
      FiltrosMapa? aplicado;
      await abrir(tester, teclado: 300, aoFechar: (f) => aplicado = f);
      await tester.enterText(
        find.byKey(const ValueKey('preco-minimo')),
        '1500',
      );
      await tester.enterText(find.byKey(const ValueKey('preco-maximo')), '600');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('aplicar-filtros')));
      await tester.pumpAndSettle();
      expect(aplicado!.precoMinimo, 600);
      expect(aplicado!.precoMaximo, 1500);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('layout claro e fonte ampliada mantêm o botão acessível', (
    tester,
  ) async {
    await abrir(tester, fonte: 1.4, brilho: Brightness.light);
    expect(
      find.byKey(const ValueKey('aplicar-filtros')).hitTestable(),
      findsOneWidget,
    );
    await tester.tap(find.text('No mapa'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('aplicar-filtros')).hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
