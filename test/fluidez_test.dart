import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moradia_app/utils/pintor_icones_padrao.dart';
import 'package:moradia_app/widgets/animated_gradient_button.dart';

void main() {
  testWidgets(
    'cache de símbolos mantém os mesmos pixels após repetição e giro',
    (tester) async {
      await tester.runAsync(() async {
        for (final cor in [
          Colors.white.withAlpha(12),
          Colors.blue.withAlpha(17),
        ]) {
          Future<List<int>> desenhar(bool reutilizar) async {
            final gravador = ui.PictureRecorder();
            final canvas = Canvas(gravador);
            final cache = PintorIconesPadrao(cor: cor, tamanho: 17);
            const icones = [Icons.home_outlined, Icons.hexagon_outlined];
            for (var i = 0; i < 30; i++) {
              final icone = icones[i % icones.length];
              canvas.save();
              canvas.translate(15.0 + i % 5 * 26, 15.0 + i ~/ 5 * 26);
              canvas.rotate(-0.16 + i % 5 * 0.08);
              if (reutilizar) {
                cache.pintar(canvas, icone);
              } else {
                final pintor = TextPainter(
                  text: TextSpan(
                    text: String.fromCharCode(icone.codePoint),
                    style: TextStyle(
                      fontSize: 17,
                      fontFamily: icone.fontFamily,
                      package: icone.fontPackage,
                      color: cor,
                    ),
                  ),
                  textDirection: TextDirection.ltr,
                )..layout();
                pintor.paint(
                  canvas,
                  Offset(-pintor.width / 2, -pintor.height / 2),
                );
                pintor.dispose();
              }
              canvas.restore();
            }
            cache.dispose();
            final desenho = gravador.endRecording();
            final imagem = await desenho.toImage(160, 180);
            final bytes = await imagem.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            );
            final pixels = bytes!.buffer.asUint8List().toList();
            imagem.dispose();
            desenho.dispose();
            return pixels;
          }

          final original = await desenhar(false);
          expect(original.any((byte) => byte != 0), isTrue);
          expect(await desenhar(true), original);
        }
      });
    },
  );

  testWidgets(
    'brilho anima sem repintar a tela e para com movimento reduzido',
    (tester) async {
      var pinturas = 0;
      var toques = 0;
      Widget montar({
        bool reduzir = false,
        bool ativo = true,
        bool carregando = false,
      }) {
        return MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduzir),
            child: TickerMode(
              enabled: ativo,
              child: Scaffold(
                body: _ContadorPinturas(
                  aoPintar: () => pinturas++,
                  child: Center(
                    child: SizedBox(
                      width: 240,
                      child: AnimatedGradientButton(
                        label: 'Continuar',
                        isLoading: carregando,
                        onTap: () => toques++,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      await tester.pumpWidget(montar());
      await tester.pump(const Duration(milliseconds: 100));
      final antes = pinturas;
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        pinturas,
        antes,
        reason: 'O brilho deve repintar apenas sua camada',
      );
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      await tester.pumpWidget(montar(ativo: false));
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);
      await tester.pumpWidget(montar(reduzir: true));
      await tester.pumpAndSettle();
      expect(tester.binding.transientCallbackCount, 0);
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();
      expect(toques, 1);

      await tester.pumpWidget(montar(reduzir: true, carregando: true));
      await tester.tap(find.byType(AnimatedGradientButton));
      await tester.pump(const Duration(milliseconds: 200));
      expect(toques, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}

class _ContadorPinturas extends SingleChildRenderObjectWidget {
  const _ContadorPinturas({required this.aoPintar, required super.child});
  final VoidCallback aoPintar;

  @override
  RenderObject createRenderObject(BuildContext context) => _Pinturas(aoPintar);
}

class _Pinturas extends RenderProxyBox {
  _Pinturas(this.aoPintar);
  final VoidCallback aoPintar;

  @override
  void paint(PaintingContext context, Offset offset) {
    aoPintar();
    super.paint(context, offset);
  }
}
