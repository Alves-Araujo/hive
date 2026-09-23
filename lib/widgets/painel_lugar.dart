import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../services/lugares_service.dart';
import '../utils/distancia.dart';
import '../utils/pins_mapa.dart';
import 'painel_inatel.dart';

// painel de um estabelecimento perto das moradias (mercado, farmacia,
// restaurante, posto, hotel, hospital) -- abre ao tocar no pin do mapa ou na
// etiqueta "320 m da farmacia" dos detalhes do anuncio. Mesma estrutura do
// painel do Inatel:
// fotos em cima, nome e endereco, acoes embaixo
class PainelLugar extends StatelessWidget {
  final Lugar lugar;
  // distancia ate a moradia de onde a pessoa veio; nula no mapa, onde nao ha
  // uma moradia "de referencia"
  final double? metros;
  final VoidCallback? aoTracarRota;
  final String rotuloRota;

  const PainelLugar({
    super.key,
    required this.lugar,
    this.metros,
    this.aoTracarRota,
    this.rotuloRota = 'Do seu local atual',
  });

  static void mostrar(
    BuildContext context,
    Lugar lugar, {
    double? metros,
    VoidCallback? aoTracarRota,
    String rotuloRota = 'Do seu local atual',
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? superficieEscura : superficieClara,
      isScrollControlled: true,
      // curva e duracao proprias: a padrao abre seca e fecha abrupta
      sheetAnimationStyle: const AnimationStyle(
        duration: Duration(milliseconds: 380),
        reverseDuration: Duration(milliseconds: 260),
        curve: Curves.easeOutQuart,
        reverseCurve: Curves.easeInCubic,
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => PainelLugar(
        lugar: lugar,
        metros: metros,
        aoTracarRota: aoTracarRota,
        rotuloRota: rotuloRota,
      ),
    );
  }

  Future<void> _abrirNoGoogleMaps(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    // sem o link do Google, uma busca pela coordenada abre o mesmo ponto
    final url =
        lugar.linkGoogleMaps ??
        'https://www.google.com/maps/search/?api=1&query=${lugar.posicao.latitude},${lugar.posicao.longitude}';
    bool ok = false;
    try {
      ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir o Google Maps.'),
          backgroundColor: corErro,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final cores = PinsMapa.cores(lugar.categoria.pin);
    final gradiente = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: cores,
    );

    return SafeArea(
      top: false,
      // o puxador fica FORA da area rolavel: dentro dela o scroll ganha o
      // gesto e a folha nao fecha ao arrastar. Fora, o arrasto vai pra folha
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // sem foto no Google, o fundo na cor da categoria ocupa o lugar
                  // -- painel sem nada em cima parecia quebrado
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: lugar.fotos.isEmpty
                        ? Container(
                            height: 120,
                            decoration: BoxDecoration(
                              gradient: gradiente,
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                            ),
                            child: Icon(
                              lugar.categoria.icone,
                              color: Colors.white38,
                              size: 44,
                            ),
                          )
                        : GaleriaFotos(
                            fotos: [
                              for (final f in lugar.fotos)
                                FotoInatel(
                                  f.url(),
                                  credito: 'Foto: ${f.autor}',
                                ),
                            ],
                            isDark: isDark,
                            iconeReserva: lugar.categoria.icone,
                            gradienteReserva: gradiente,
                          ),
                  ),

                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.sm + 2),
                              decoration: BoxDecoration(
                                gradient: gradiente,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                              ),
                              child: Icon(
                                lugar.categoria.icone,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    lugar.nome,
                                    style: AppTextStyles.heading3.copyWith(
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                  Text(
                                    metros == null
                                        ? lugar.categoria.rotulo
                                        : '${lugar.categoria.rotulo} · ${formatarDistancia(metros!)} da moradia',
                                    style: AppTextStyles.caption.copyWith(
                                      color: isDark
                                          ? Colors.white54
                                          : Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        if (lugar.endereco.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.lg),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.place_rounded,
                                size: 18,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  lugar.endereco,
                                  style: AppTextStyles.caption.copyWith(
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xl),

                        if (aoTracarRota != null) ...[
                          BotaoPainel(
                            isDark: isDark,
                            icone: Icons.directions_rounded,
                            titulo: 'Traçar rota até aqui',
                            subtitulo: rotuloRota,
                            destaque: true,
                            externo: false,
                            onTap: () {
                              Navigator.pop(context);
                              aoTracarRota!();
                            },
                          ),
                          const SizedBox(height: AppSpacing.md),
                        ],
                        BotaoPainel(
                          isDark: isDark,
                          icone: Icons.map_outlined,
                          titulo: 'Abrir no Google Maps',
                          subtitulo: 'Horários, telefone e avaliações',
                          onTap: () => _abrirNoGoogleMaps(context),
                        ),

                        // nome, endereco e fotos vem do Google Places: os termos
                        // pedem a atribuicao visivel quando o dado aparece fora do
                        // mapa do Google
                        const SizedBox(height: AppSpacing.md),
                        Center(
                          child: Text(
                            'Informações do Google',
                            style: AppTextStyles.caption.copyWith(
                              fontSize: 11,
                              color: isDark ? Colors.white30 : Colors.black38,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
