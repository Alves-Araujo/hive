import 'package:flutter/material.dart';
import '../main.dart';
import '../utils/cor_foto.dart';

// widget de avatar com as iniciais do nome
// gera um gradiente diferente pra cada nome
class AvatarWidget extends StatelessWidget {
  final String nome;
  final double size;
  final IconData? iconOverride;
  final List<Color>? gradientColors;
  final bool showOnlineIndicator;
  final String? fotoUrl;

  const AvatarWidget({
    super.key,
    required this.nome,
    this.size = 48,
    this.iconOverride,
    this.gradientColors,
    this.showOnlineIndicator = false,
    this.fotoUrl,
  });

  String get _iniciais {
    final partes = nome.trim().split(RegExp(r'\s+'));
    if (partes.isEmpty || partes[0].isEmpty) return '?';
    if (partes.length == 1) return partes[0][0].toUpperCase();
    return '${partes[0][0]}${partes.last[0]}'.toUpperCase();
  }

  // pega um gradiente baseado no hash do nome pra ficar sempre igual
  List<Color> get _gradientFromName {
    if (gradientColors != null) return gradientColors!;
    final hash = nome.hashCode.abs();
    final gradients = [
      [corPrimaria, corPrimaria2],
      [const Color(0xFF06B6D4), const Color(0xFF3B82F6)],
      [const Color(0xFFF59E0B), const Color(0xFFEF4444)],
      [const Color(0xFF10B981), const Color(0xFF06B6D4)],
      [const Color(0xFFEC4899), const Color(0xFF8B5CF6)],
      [const Color(0xFF6366F1), const Color(0xFFA855F7)],
    ];
    return gradients[hash % gradients.length];
  }

  Widget _buildConteudoPadrao() {
    return iconOverride != null
        ? Icon(iconOverride, color: Colors.white, size: size * 0.45)
        : Text(
            _iniciais,
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.36,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          );
  }

  @override
  Widget build(BuildContext context) {
    final colors = _gradientFromName;

    return Stack(
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: colors[0].withAlpha(50),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: (fotoUrl != null && fotoUrl!.isNotEmpty)
              ? ClipOval(
                  child: Image(
                    image: fotoAvatar(fotoUrl!, size, MediaQuery.devicePixelRatioOf(context)),
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (context, error, stackTrace) => _buildConteudoPadrao(),
                  ),
                )
              : Center(child: _buildConteudoPadrao()),
        ),
        if (showOnlineIndicator)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.28,
              height: size * 0.28,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
