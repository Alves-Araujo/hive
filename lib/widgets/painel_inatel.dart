import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../main.dart';
import 'pressionavel.dart';

// uma foto da galeria da faculdade.
//
// O credito e opcional porque as fotos vem de duas origens: material do
// proprio Inatel (sem credito a exibir) e foto de licenca aberta, que EXIGE
// atribuicao visivel -- dai o rotulo no canto do slide quando o campo existe.
class FotoInatel {
  final String url;
  final String? credito;

  const FotoInatel(this.url, {this.credito});
}

// Fotos do painel da faculdade.
//
// Ficam nesta lista, e so aqui, pra trocar sem mexer em layout: basta editar
// as URLs (ou apontar pra assets do projeto trocando Image.network por
// Image.asset no _Galeria). Sao imagens publicas do site do Inatel mais uma
// de licenca aberta; se um dia o site reorganizar as pastas, o slide cai no
// fundo de marca em vez de quebrar a tela.
const List<FotoInatel> fotosInatel = [
  FotoInatel('https://inatel.br/home/images/seo-home.jpg'),
  FotoInatel(
      'https://inatel.br/vestibular/images/2026/banner-vestibular-1440.jpg'),
  FotoInatel(
    'https://upload.wikimedia.org/wikipedia/commons/thumb/9/96/Visita_ao_INATEL_%2850230360692%29.jpg/1280px-Visita_ao_INATEL_%2850230360692%29.jpg',
    credito: 'Foto: MCTI · CC BY 2.0',
  ),
];

const String siteInatel = 'https://inatel.br/home/';
const String vestibularInatel = 'https://inatel.br/vestibular/';
const String enderecoInatel =
    'Av. João de Camargo, 510 - Santa Rita do Sapucaí, MG';

// uma engenharia da graduacao, com a pagina oficial do curso
class CursoInatel {
  final String nome;

  // como aparece no chip -- "Biomédica" em vez de "Engenharia Biomédica",
  // porque a secao inteira ja diz que sao engenharias
  final String curto;
  final String url;

  const CursoInatel(this.nome, this.curto, this.url);
}

// as 7 engenharias da graduacao, na ordem em que o vestibular as lista.
// Cada uma abre a propria pagina no site do Inatel.
const List<CursoInatel> engenhariasInatel = [
  CursoInatel('Engenharia Biomédica', 'Biomédica',
      'https://inatel.br/vestibular/engenharia-biomedica'),
  CursoInatel('Engenharia de Computação', 'Computação',
      'https://inatel.br/vestibular/engenharia-de-computacao'),
  CursoInatel('Engenharia de Controle e Automação', 'Controle e Automação',
      'https://inatel.br/vestibular/engenharia-de-controle-e-automacao'),
  CursoInatel('Engenharia Elétrica', 'Elétrica',
      'https://inatel.br/vestibular/engenharia-eletrica'),
  CursoInatel('Engenharia de Produção', 'Produção',
      'https://inatel.br/vestibular/engenharia-de-producao'),
  CursoInatel('Engenharia de Software', 'Software',
      'https://inatel.br/vestibular/engenharia-de-software'),
  CursoInatel('Engenharia de Telecomunicações', 'Telecomunicações',
      'https://inatel.br/vestibular/engenharia-de-telecomunicacoes'),
];

// painel que abre ao tocar no pin fixo da faculdade -- fotos, endereco e os
// links oficiais. Mesma linguagem do resto do app: superficie do tema, raios
// dos tokens, azul da marca na acao principal
class PainelInatel extends StatelessWidget {
  // acao de tracar rota ate a faculdade; nula esconde o botao
  final VoidCallback? aoTracarRota;

  const PainelInatel({super.key, this.aoTracarRota});

  static void mostrar(BuildContext context, {VoidCallback? aoTracarRota}) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? superficieEscura : superficieClara,
      // com fotos, cursos e links o painel passa da metade da tela: sem
      // isScrollControlled a folha para em 50% e corta o conteudo
      isScrollControlled: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => PainelInatel(aoTracarRota: aoTracarRota),
    );
  }

  Future<void> _abrir(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    bool ok = false;
    try {
      // externalApplication: o site abre no navegador do celular, nao numa
      // webview de dentro do app -- e conteudo de terceiro, com login e
      // formulario de inscricao
      ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Não foi possível abrir o link.'),
          backgroundColor: corErro,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // puxador -- sinaliza que a folha arrasta pra fechar
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(
                    top: AppSpacing.md, bottom: AppSpacing.md),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: GaleriaFotos(
                fotos: fotosInatel,
                isDark: isDark,
                iconeReserva: Icons.school_rounded,
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.sm + 2),
                        decoration: BoxDecoration(
                          gradient: gradientePrincipal,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          boxShadow: AppShadows.marca(forca: 0.4),
                        ),
                        child: const Icon(Icons.school_rounded,
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Inatel',
                              style: AppTextStyles.heading2.copyWith(
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            Text(
                              'Instituto Nacional de Telecomunicações',
                              style: AppTextStyles.caption.copyWith(
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.place_rounded,
                          size: 18,
                          color: isDark ? Colors.white38 : Colors.black38),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          enderecoInatel,
                          style: AppTextStyles.caption.copyWith(
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // engenharias da graduacao -- cada chip abre a pagina do
                  // curso. Em chip e nao em lista porque sao sete: em linhas
                  // empilhadas empurrariam os links pra fora da tela
                  Row(
                    children: [
                      Text(
                        'Engenharias',
                        style: AppTextStyles.bodyBold.copyWith(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '${engenhariasInatel.length} cursos',
                        style: AppTextStyles.caption.copyWith(
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final curso in engenhariasInatel)
                        _ChipCurso(
                          curso: curso,
                          isDark: isDark,
                          onTap: () => _abrir(context, curso.url),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  BotaoPainel(
                    isDark: isDark,
                    icone: Icons.school_outlined,
                    titulo: 'Vestibular',
                    subtitulo: 'Inscrições, provas e bolsas',
                    destaque: true,
                    onTap: () => _abrir(context, vestibularInatel),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  BotaoPainel(
                    isDark: isDark,
                    icone: Icons.language_rounded,
                    titulo: 'Site do Inatel',
                    subtitulo: 'inatel.br',
                    onTap: () => _abrir(context, siteInatel),
                  ),

                  if (aoTracarRota != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    BotaoPainel(
                      isDark: isDark,
                      icone: Icons.directions_rounded,
                      titulo: 'Traçar rota até aqui',
                      subtitulo: 'Do seu local atual',
                      externo: false,
                      onTap: () {
                        Navigator.pop(context);
                        aoTracarRota!();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// chip de um curso -- toque abre a pagina oficial dele
class _ChipCurso extends StatelessWidget {
  final CursoInatel curso;
  final bool isDark;
  final VoidCallback onTap;

  const _ChipCurso({
    required this.curso,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Pressionavel(
      onTap: onTap,
      // o nome completo fica no leitor de tela, ja que o chip mostra o curto
      child: Semantics(
        label: curso.nome,
        button: true,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm + 1),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withAlpha(12) : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: isDark
                  ? Colors.white.withAlpha(20)
                  : corPrimaria.withAlpha(26),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.engineering_rounded,
                  size: 15, color: isDark ? Colors.white54 : corPrimaria),
              const SizedBox(width: AppSpacing.xs + 2),
              Text(
                curso.curto,
                style: AppTextStyles.captionBold.copyWith(
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// carrossel das fotos, com os pontinhos de posicao. Publico porque o painel
// dos estabelecimentos (painel_lugar.dart) usa o mesmo
class GaleriaFotos extends StatefulWidget {
  final List<FotoInatel> fotos;
  final bool isDark;
  // icone do fundo que aparece enquanto a foto carrega ou quando ela falha
  final IconData iconeReserva;
  final Gradient gradienteReserva;

  const GaleriaFotos({
    super.key,
    required this.fotos,
    required this.isDark,
    required this.iconeReserva,
    this.gradienteReserva = gradientePrincipal,
  });

  @override
  State<GaleriaFotos> createState() => _GaleriaFotosState();
}

class _GaleriaFotosState extends State<GaleriaFotos> {
  final PageController _controller = PageController();
  int _atual = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fotos = widget.fotos;
    if (fotos.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: SizedBox(
            height: 190,
            child: PageView.builder(
              controller: _controller,
              itemCount: fotos.length,
              onPageChanged: (i) => setState(() => _atual = i),
              itemBuilder: (context, i) {
                final foto = fotos[i];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      foto.url,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, filho, progresso) =>
                          progresso == null ? filho : _reserva(mostrarSpinner: true),
                      // foto fora do ar nao pode derrubar o painel: cai no
                      // fundo de marca, que e o mesmo do resto do app
                      errorBuilder: (context, erro, pilha) =>
                          _reserva(mostrarSpinner: false),
                    ),
                    if (foto.credito != null)
                      Positioned(
                        right: AppSpacing.sm,
                        bottom: AppSpacing.sm,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withAlpha(120),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            foto.credito!,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 10),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        if (fotos.length > 1) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < fotos.length; i++)
                AnimatedContainer(
                  duration: AppMotion.rapida,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _atual ? 18 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == _atual
                        ? corPrimaria
                        : (widget.isDark ? Colors.white24 : Colors.black26),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _reserva({required bool mostrarSpinner}) => _Reserva(
        mostrarSpinner: mostrarSpinner,
        icone: widget.iconeReserva,
        gradiente: widget.gradienteReserva,
      );
}

// fundo que ocupa o lugar da foto enquanto ela carrega ou quando ela falha
class _Reserva extends StatelessWidget {
  final bool mostrarSpinner;
  final IconData icone;
  final Gradient gradiente;
  const _Reserva({required this.mostrarSpinner, required this.icone, required this.gradiente});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(gradient: gradiente),
      child: Center(
        child: mostrarSpinner
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white70),
              )
            : Icon(icone, color: Colors.white38, size: 40),
      ),
    );
  }
}

// linha de acao do painel -- icone, titulo, apoio e a seta de "abre fora".
// Publica porque o painel dos estabelecimentos usa a mesma
class BotaoPainel extends StatelessWidget {
  final bool isDark;
  final IconData icone;
  final String titulo;
  final String subtitulo;
  final bool destaque;

  // acao que sai do app -- muda so a seta da direita: a diagonal e a convencao
  // de "abre fora daqui", e usa-la numa acao interna promete o que nao cumpre
  final bool externo;
  final VoidCallback onTap;

  const BotaoPainel({
    super.key,
    required this.isDark,
    required this.icone,
    required this.titulo,
    required this.subtitulo,
    required this.onTap,
    this.destaque = false,
    this.externo = true,
  });

  @override
  Widget build(BuildContext context) {
    final Color corTexto =
        destaque ? Colors.white : (isDark ? Colors.white : Colors.black87);
    final Color corApoio = destaque
        ? Colors.white70
        : (isDark ? Colors.white38 : Colors.black45);

    return Pressionavel(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md + 2),
        decoration: BoxDecoration(
          gradient: destaque ? gradientePrincipal : null,
          color: destaque
              ? null
              : (isDark ? Colors.white.withAlpha(12) : Colors.white),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: destaque
              ? null
              : Border.all(
                  color: isDark
                      ? Colors.white.withAlpha(18)
                      : corPrimaria.withAlpha(22),
                ),
          boxShadow:
              destaque ? AppShadows.marca(forca: 0.5) : AppShadows.nivel1(isDark),
        ),
        child: Row(
          children: [
            Icon(icone, color: corTexto, size: 22),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo,
                      style: AppTextStyles.bodyBold.copyWith(color: corTexto)),
                  Text(subtitulo,
                      style: AppTextStyles.caption.copyWith(color: corApoio)),
                ],
              ),
            ),
            Icon(
              externo
                  ? Icons.arrow_outward_rounded
                  : Icons.arrow_forward_ios_rounded,
              color: corApoio,
              size: externo ? 18 : 14,
            ),
          ],
        ),
      ),
    );
  }
}
