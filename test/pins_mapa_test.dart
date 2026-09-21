import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moradia_app/utils/pins_mapa.dart';

// Os pins do mapa sao desenhados em codigo (Canvas), nao sao PNG de asset.
// A unica forma de conferir o desenho era rodar o app, achar um marcador na
// tela e olhar -- e pra imobiliaria isso exige um cadastro real. Aqui o
// mesmo desenho e gravado em build/pins/, que da pra abrir e comparar.
//
// RESSALVA: no ambiente de teste a fonte de icones nao esta disponivel,
// entao o icone sai como um quadradinho vazio (o "tofu" de glifo ausente).
// O que este teste garante e a forma, o tamanho e as cores de cada tipo; o
// icone em si e constante do Material e nao compila se nao existir.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desenha todos os pins pra conferencia', (tester) async {
    const double densidade = 3.0;
    final saida = Directory('build/pins');
    saida.createSync(recursive: true);

    // runAsync: rasterizar imagem precisa do relogio de verdade. Dentro do
    // tempo falso do teste o segundo toImage() nunca completa e o teste
    // simplesmente trava
    await tester.runAsync(() async {
      for (final tipo in TipoPin.values) {
        final imagem = await PinsMapa.desenharImagem(tipo, densidade);
        final bytes = await imagem.toByteData(format: ui.ImageByteFormat.png);
        expect(bytes, isNotNull, reason: 'pin ${tipo.name} nao virou imagem');

        final arquivo = File('${saida.path}/${tipo.name}.png');
        arquivo.writeAsBytesSync(bytes!.buffer.asUint8List());

        // pin em branco significaria desenho quebrado: um PNG valido desse
        // tamanho nunca sai com poucos bytes
        expect(arquivo.lengthSync(), greaterThan(500),
            reason: 'pin ${tipo.name} saiu vazio');
        debugPrint('pin ${tipo.name}: ${imagem.width}x${imagem.height} '
            '(${arquivo.lengthSync()} bytes)');
      }
    });
  });
}
