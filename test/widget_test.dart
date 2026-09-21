import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moradia_app/screens/login_screen.dart';

void main() {
  testWidgets('App smoke test - tela de login renderiza', (WidgetTester tester) async {
    // a janela padrao de teste e 800x600 (paisagem): a tela de login e
    // desenhada pra celular em pe e estourava, derrubando o teste por um
    // motivo que nao existe no aparelho. Usa a tela do aparelho de teste
    // (SM A920F: 1080x2220 a 2.625, ou seja 411x845 em pontos logicos).
    //
    // ATENCAO: com 360 pontos de largura (celular menor) essa tela estoura
    // 48px de verdade -- o SingleChildScrollView dela tem um SizedBox de
    // altura FIXA dentro, entao o conteudo nao tem pra onde rolar. Nao e
    // problema do teste; e um ajuste pendente na propria tela
    tester.view.physicalSize = const Size(1080, 2220);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    // testa a TelaLogin direto, sem passar pela AuthGate -- ela precisa do
    // Firebase inicializado (authStateChanges), o que nao existe nesse teste
    await tester.pumpWidget(const MaterialApp(home: TelaLogin()));
    // A tela de login deve exibir o botão "Entrar"
    expect(find.text('Entrar'), findsOneWidget);
  });
}
