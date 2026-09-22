import 'package:flutter/material.dart';
import '../main.dart';
import '../models/imovel.dart';
import '../screens/detalhes_imovel_screen.dart';
import '../utils/moeda.dart';
import '../utils/distancia.dart';
import '../utils/icones_tag.dart';

class CardImovelVertical extends StatelessWidget {
  final Imovel imovel;
  final bool isDark;

  const CardImovelVertical({super.key, required this.imovel, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bool isEvento = imovel.tipo == TipoListing.evento;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? corSuperficieEscura : Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: isDark ? Colors.white.withAlpha(10) : Colors.black.withAlpha(8),
          ),
          boxShadow: AppShadows.nivel2(isDark),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => DetalhesImovelScreen(imovel: imovel)),
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Area da Imagem
                SizedBox(
                  height: 180,
                  child: Stack(
                    children: [
                      // Imagem de fundo
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
                          gradient: imovel.fotos.isEmpty
                              ? (isEvento ? gradienteEvento : gradientePrincipal)
                              : null,
                        ),
                        child: imovel.fotos.isNotEmpty
                            ? ClipRRect(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
                                child: Image.network(
                                  imovel.fotos.first,
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => Icon(
                                    isEvento ? Icons.celebration_rounded : Icons.home_rounded,
                                    color: Colors.white,
                                    size: 48,
                                  ),
                                ),
                              )
                            : Center(
                                child: Icon(
                                  isEvento ? Icons.celebration_rounded : Icons.home_rounded,
                                  color: Colors.white.withAlpha(180),
                                  size: 64,
                                ),
                              ),
                      ),
                      // Degradê sutil em baixo da imagem para dar contraste
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: const [0.6, 1.0],
                              colors: [
                                Colors.transparent,
                                Colors.black.withAlpha(120),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Preço flutuante
                      Positioned(
                        bottom: AppSpacing.md,
                        left: AppSpacing.md,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.sm - 2,
                          ),
                          decoration: BoxDecoration(
                            color: isEvento ? corAtencao : corDestaque,
                            borderRadius: BorderRadius.circular(99.0),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(40),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: isEvento
                              ? const Text(
                                  'Evento',
                                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.baseline,
                                  textBaseline: TextBaseline.alphabetic,
                                  children: [
                                    Text(
                                      formatarPreco(imovel.preco),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                        color: Colors.white,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    Text(
                                      '/mês',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.white.withAlpha(200),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Info do imovel
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        imovel.titulo,
                        style: AppTextStyles.bodyBold.copyWith(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 18,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // bairro logo abaixo do titulo: e a primeira coisa que
                      // quem procura moradia quer saber, e antes so aparecia
                      // dentro da tela de detalhes
                      if (imovel.bairro.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            Icon(Icons.place_rounded,
                                size: 13,
                                color: isDark ? Colors.white38 : corPrimaria.withAlpha(150)),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                imovel.cidade.isNotEmpty
                                    ? '${imovel.bairro} · ${imovel.cidade}'
                                    : imovel.bairro,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyles.caption.copyWith(
                                  color: isDark ? Colors.white54 : Colors.black54,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        imovel.descricao,
                        style: AppTextStyles.caption.copyWith(
                          color: isDark ? Colors.white54 : Colors.black54,
                          fontSize: 14,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (imovel.tags.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: imovel.tags.take(3).map((tag) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm + 2,
                                vertical: AppSpacing.xs + 2,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withAlpha(10)
                                    : Colors.black.withAlpha(5),
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    iconeDaTag(tag),
                                    size: 14,
                                    color: isDark
                                        ? Colors.white.withAlpha(160)
                                        : Colors.black87,
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Text(
                                    tag == tagPertoDaFaculdade
                                        ? rotuloDistanciaFaculdade(imovel.posicao)
                                        : tag,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white.withAlpha(180)
                                          : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
