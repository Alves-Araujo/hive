import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import '../models/imobiliaria.dart';
import '../screens/perfil_publico_screen.dart';
import '../utils/pins_mapa.dart';
import 'painel_inatel.dart';

// painel da imobiliaria -- abre ao tocar no pin dela no mapa. Mesma estrutura
// do painel do estabelecimento (PainelLugar): foto em cima, nome e endereco,
// acoes embaixo. Antes daqui o pin so tinha o balaozinho do Google com nome e
// endereco, e o toque morria ali: nao dava pra ver a foto, ligar, tracar rota
// nem chegar nos anuncios da empresa
class PainelImobiliaria extends StatelessWidget {
  final Imobiliaria imobiliaria;
  final VoidCallback? aoTracarRota;
  final String rotuloRota;

  const PainelImobiliaria({
    super.key,
    required this.imobiliaria,
    this.aoTracarRota,
    this.rotuloRota = 'Do seu local atual',
  });

  static void mostrar(
    BuildContext context,
    Imobiliaria imobiliaria, {
    VoidCallback? aoTracarRota,
    String rotuloRota = 'Do seu local atual',
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? superficieEscura : superficieClara,
      isScrollControlled: true,
      // mesma curva e duracao do painel do estabelecimento: as duas folhas
      // saem do mesmo gesto (tocar num pin) e precisam abrir igual
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
      builder: (_) => PainelImobiliaria(
        imobiliaria: imobiliaria,
        aoTracarRota: aoTracarRota,
        rotuloRota: rotuloRota,
      ),
    );
  }

  Future<void> _abrir(BuildContext context, String url, String erro) async {
    final messenger = ScaffoldMessenger.of(context);
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
        SnackBar(content: Text(erro), backgroundColor: corErro),
      );
    }
  }

  Future<void> _abrirNoGoogleMaps(BuildContext context) async {
    final posicao = imobiliaria.posicao;
    // a imobiliaria so tem pin quando o endereco foi geocodificado, entao a
    // coordenada existe aqui; o endereco cobre o caso de abrir o painel de
    // outro lugar que nao seja o mapa
    final busca = posicao != null
        ? '${posicao.latitude},${posicao.longitude}'
        : imobiliaria.endereco;
    await _abrir(
      context,
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(busca)}',
      'Não foi possível abrir o Google Maps.',
    );
  }

  Future<void> _ligar(BuildContext context) async {
    final numero = imobiliaria.telefone.replaceAll(RegExp(r'[^0-9+]'), '');
    await _abrir(context, 'tel:$numero', 'Não foi possível abrir o telefone.');
  }

  void _abrirPerfil(BuildContext context) {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PerfilPublicoScreen(imobiliaria: imobiliaria),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final cores = PinsMapa.cores(TipoPin.imobiliaria);
    final gradiente = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: cores,
    );
    const icone = Icons.real_estate_agent_rounded;

    return SafeArea(
      top: false,
      // o puxador fica FORA da area rolavel: dentro dela o scroll ganha o
      // gesto e a folha nao fecha ao arrastar
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
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    // com fotos do escritorio, a galeria e a mesma do painel
                    // do estabelecimento (arrasta de lado, bolinhas embaixo);
                    // sem elas, sobra o logotipo -- e sem logotipo, o fundo
                    // na cor do pin
                    child: imobiliaria.fotos.isEmpty
                        ? _FotoImobiliaria(
                            fotoUrl: imobiliaria.fotoUrl,
                            gradiente: gradiente,
                            icone: icone,
                          )
                        : GaleriaFotos(
                            fotos: [
                              for (final f in imobiliaria.fotos) FotoInatel(f),
                            ],
                            isDark: isDark,
                            iconeReserva: icone,
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
                              child: const Icon(
                                icone,
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
                                    imobiliaria.nome,
                                    style: AppTextStyles.heading3.copyWith(
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                  Text(
                                    imobiliaria.emailVerificado
                                        ? 'Imobiliária · Cadastro confirmado'
                                        : 'Imobiliária',
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

                        // descricao e telefone so existem quando a propria
                        // imobiliaria preencheu (ver EditarImobiliariaScreen):
                        // cadastro criado por um corretor nasce sem os dois
                        if (imobiliaria.descricao.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            imobiliaria.descricao,
                            style: AppTextStyles.body.copyWith(
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],

                        if (imobiliaria.endereco.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.lg),
                          _LinhaInfo(
                            isDark: isDark,
                            icone: Icons.place_rounded,
                            texto: imobiliaria.endereco,
                          ),
                        ],
                        if (imobiliaria.telefone.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.sm),
                          _LinhaInfo(
                            isDark: isDark,
                            icone: Icons.phone_rounded,
                            texto: imobiliaria.telefone,
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
                          icone: Icons.storefront_rounded,
                          titulo: 'Ver perfil da imobiliária',
                          subtitulo: 'Anúncios, corretores e avaliações',
                          externo: false,
                          onTap: () => _abrirPerfil(context),
                        ),
                        if (imobiliaria.telefone.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.md),
                          BotaoPainel(
                            isDark: isDark,
                            icone: Icons.call_rounded,
                            titulo: 'Ligar para a imobiliária',
                            subtitulo: imobiliaria.telefone,
                            onTap: () => _ligar(context),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.md),
                        BotaoPainel(
                          isDark: isDark,
                          icone: Icons.map_outlined,
                          titulo: 'Abrir no Google Maps',
                          subtitulo: 'Horários, telefone e avaliações',
                          onTap: () => _abrirNoGoogleMaps(context),
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

// a foto do cadastro da imobiliaria costuma ser logotipo, nao fotografia:
// entra em BoxFit.contain sobre o fundo da cor do pin, senao o corte de uma
// logo quadrada numa faixa larga come o nome da empresa. Sem foto (ou com ela
// fora do ar) sobra so o fundo com o icone, igual o painel do estabelecimento
class _FotoImobiliaria extends StatelessWidget {
  final String fotoUrl;
  final Gradient gradiente;
  final IconData icone;

  const _FotoImobiliaria({
    required this.fotoUrl,
    required this.gradiente,
    required this.icone,
  });

  @override
  Widget build(BuildContext context) {
    final semFoto = fotoUrl.trim().isEmpty;
    return Container(
      height: semFoto ? 120 : 190,
      decoration: BoxDecoration(
        gradient: gradiente,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: semFoto
          ? Icon(icone, color: Colors.white38, size: 44)
          : Image.network(
              fotoUrl,
              fit: BoxFit.contain,
              // decodifica no tamanho de exibicao: foto cheia decodificada
              // durante a animacao da folha e o que trava a abertura
              cacheWidth:
                  (MediaQuery.sizeOf(context).width *
                          MediaQuery.devicePixelRatioOf(context))
                      .round(),
              gaplessPlayback: true,
              loadingBuilder: (context, filho, progresso) => progresso == null
                  ? filho
                  : const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white70,
                        ),
                      ),
                    ),
              errorBuilder: (context, erro, pilha) =>
                  Icon(icone, color: Colors.white38, size: 44),
            ),
    );
  }
}

// endereco e telefone: icone + texto, do mesmo jeito que o painel do
// estabelecimento mostra o endereco
class _LinhaInfo extends StatelessWidget {
  final bool isDark;
  final IconData icone;
  final String texto;

  const _LinhaInfo({
    required this.isDark,
    required this.icone,
    required this.texto,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icone, size: 18, color: isDark ? Colors.white38 : Colors.black38),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            texto,
            style: AppTextStyles.caption.copyWith(
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}
