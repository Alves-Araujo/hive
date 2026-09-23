import 'package:flutter/material.dart';

/// Vidro translucido sem ler/desfocar a superficie nativa do mapa.
class MapGlassSurface extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  const MapGlassSurface({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;

    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          // Uma unica camada; transparencia residual reduzida pela metade.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0, 0.48, 0.78, 1],
            colors: dark
                ? const [
                    Color(0xF4203247),
                    Color(0xE90D1B29),
                    Color(0xED101F2F),
                    Color(0xF21A3044),
                  ]
                : const [
                    Color(0xF7F7FAFD),
                    Color(0xEDEFF3F8),
                    Color(0xF1E5EDF5),
                    Color(0xF5DCE8F3),
                  ],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(dark ? 36 : 18),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: CustomPaint(
          foregroundPainter: _BordaVidro(radius: radius, dark: dark),
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// O gradiente ocupa apenas o contorno, deixando o centro transparente.
class _BordaVidro extends CustomPainter {
  final double radius;
  final bool dark;

  const _BordaVidro({required this.radius, required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      stops: const [0, 0.35, 0.65, 1],
      colors: dark
          ? const [
              Color(0xCC6D91B3),
              Color(0x802C4961),
              Color(0x6634536D),
              Color(0xB34E779A),
            ]
          : const [
              Color(0xE6FAFDFF),
              Color(0xA6B9CDDE),
              Color(0x80D2DFE9),
              Color(0xB3B2CADF),
            ],
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(radius - 0.5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = gradient.createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_BordaVidro oldDelegate) =>
      radius != oldDelegate.radius || dark != oldDelegate.dark;
}
