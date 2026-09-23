import 'package:flutter/material.dart';
import '../main.dart';

// botao principal do app com gradiente e efeito de shimmer
class AnimatedGradientButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isLoading;
  final IconData? icon;
  final double height;
  final double borderRadius;

  // trocar as cores e excecao, nao configuracao: serve pra tela que TEM
  // identidade propria (a ficha de evento, que e roxa inteira). Quem nao
  // passa nada continua com o gradiente da marca
  final List<Color>? cores;

  const AnimatedGradientButton({
    super.key,
    required this.label,
    this.onTap,
    this.isLoading = false,
    this.icon,
    this.height = 56,
    this.borderRadius = AppRadius.md,
    this.cores,
  });

  @override
  State<AnimatedGradientButton> createState() => _AnimatedGradientButtonState();
}

class _AnimatedGradientButtonState extends State<AnimatedGradientButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;
  // a faixa cruza o botao na primeira parte do ciclo e fica parada fora dele
  // no resto -- sem a pausa, um brilho passando sem parar cansa a vista
  late final Animation<double> _varredura;
  double _scale = 1.0;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );
    _varredura = Tween<double>(begin: -1, end: 1).animate(
      _shimmerController.drive(
        CurveTween(curve: const Interval(0, 0.45, curve: Curves.easeInOut)),
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _shimmerController.stop();
      _shimmerController.value = 0;
    } else if (!_shimmerController.isAnimating) {
      _shimmerController.repeat();
    }
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.97),
      onTapUp: (_) {
        setState(() => _scale = 1.0);
        if (!widget.isLoading && widget.onTap != null) {
          widget.onTap!();
        }
      },
      onTapCancel: () => setState(() => _scale = 1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              // as cores VEM do gradientePrincipal, nao sao uma copia
              // delas: eram os mesmos tres valores escritos de novo aqui,
              // e um ajuste de identidade deixaria este botao pra tras
              colors: widget.cores ?? gradientePrincipal.colors,
            ),
            boxShadow: AppShadows.marca(forca: 0.9),
          ),
          child: Stack(
            children: [
              // brilho: uma faixa clara que atravessa o botao e SAI do outro
              // lado antes do ciclo recomecar. Antes o shimmer mexia no stop
              // do meio do gradiente de 0.5 a 0.8 e, no repeat(), voltava pra
              // 0.5 de uma vez -- um salto visivel a cada 2,4s, com cara de
              // video cortado. Agora o reinicio acontece com a faixa fora do
              // botao, entao nao da pra ver
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  // Só a faixa se repinta; texto, sombra e tela não refazem
                  // build/layout a cada quadro da animação.
                  child: RepaintBoundary(
                    child: CustomPaint(painter: _BrilhoPainter(_varredura)),
                  ),
                ),
              ),
              Center(
                child: widget.isLoading
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.icon != null) ...[
                            Icon(widget.icon, color: Colors.white, size: 20),
                            const SizedBox(width: 10),
                          ],
                          Text(
                            widget.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// desloca o gradiente na horizontal em fracoes da largura do botao: -1 poe
// a faixa inteira fora pela esquerda, 1 fora pela direita
class _DeslizarGradiente extends GradientTransform {
  final double fracao;
  const _DeslizarGradiente(this.fracao);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * fracao, 0, 0);
}

class _BrilhoPainter extends CustomPainter {
  _BrilhoPainter(this.varredura) : super(repaint: varredura);

  final Animation<double> varredura;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final gradiente = LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: const [Color(0x00FFFFFF), Color(0x26FFFFFF), Color(0x00FFFFFF)],
      stops: const [0.35, 0.5, 0.65],
      transform: _DeslizarGradiente(varredura.value),
    );
    canvas.drawRect(rect, Paint()..shader = gradiente.createShader(rect));
  }

  @override
  bool shouldRepaint(_BrilhoPainter anterior) =>
      anterior.varredura != varredura;
}
