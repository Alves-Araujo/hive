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

  const AnimatedGradientButton({
    super.key,
    required this.label,
    this.onTap,
    this.isLoading = false,
    this.icon,
    this.height = 56,
    this.borderRadius = AppRadius.md,
  });

  @override
  State<AnimatedGradientButton> createState() => _AnimatedGradientButtonState();
}

class _AnimatedGradientButtonState extends State<AnimatedGradientButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;
  double _scale = 1.0;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
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
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: AnimatedBuilder(
          animation: _shimmerController,
          builder: (context, child) {
            final shimmerValue = _shimmerController.value;
            return Container(
              height: widget.height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  // mesmo azul escuro do gradientePrincipal, usado no botao de
                  // rota e na pilula da barra. O roxo #7C3AED que estava aqui
                  // nao existe em mais lugar nenhum da identidade
                  colors: const [
                    Color(0xFF12294A),
                    Color(0xFF17456F),
                    Color(0xFF1C5A8F),
                  ],
                  stops: [
                    0.0,
                    0.5 + (shimmerValue * 0.3),
                    1.0,
                  ],
                ),
                boxShadow: AppShadows.marca(forca: 0.9),
              ),
              child: Center(
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
            );
          },
        ),
      ),
    );
  }
}
