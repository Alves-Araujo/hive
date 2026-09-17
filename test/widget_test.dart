import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moradia_app/screens/login_screen.dart';

void main() {
  testWidgets('App smoke test - tela de login renderiza', (WidgetTester tester) async {
    // testa a TelaLogin direto, sem passar pela AuthGate -- ela precisa do
    // Firebase inicializado (authStateChanges), o que nao existe nesse teste
    await tester.pumpWidget(const MaterialApp(home: TelaLogin()));
    // A tela de login deve exibir o botão "Entrar"
    expect(find.text('Entrar'), findsOneWidget);
  });
}
