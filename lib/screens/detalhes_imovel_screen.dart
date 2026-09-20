import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../main.dart';
import '../models/avaliacao.dart';
import '../models/imovel.dart';
import '../models/perfil_publico.dart';
import '../services/avaliacao_service.dart';
import '../services/busca_service.dart';
import '../services/localizacao_service.dart';
import '../services/perfil_publico_service.dart';
import '../services/rota_service.dart';
import '../utils/distancia.dart';
import '../utils/moeda.dart';
import '../utils/tempo.dart';
import '../widgets/animated_gradient_button.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/painel_localizacao.dart';
import '../widgets/pressionavel.dart';
import 'chat_detail_screen.dart';
import 'perfil_publico_screen.dart';

// pagina dedicada de detalhes -- aberta ao tocar num marker do mapa ou num
// card na aba Resumo. O calculo de rota so dispara o pedido (rotaPendenteGlobal)
// e volta pro mapa principal, que e quem de fato traca e mostra a rota
class DetalhesImovelScreen extends StatefulWidget {
  final Imovel imovel;
  const DetalhesImovelScreen({super.key, required this.imovel});

  @override
  State<DetalhesImovelScreen> createState() => _DetalhesImovelScreenState();
}

class _DetalhesImovelScreenState extends State<DetalhesImovelScreen> {
  bool _buscandoLocalizacao = false;

  // carrossel do cabecalho
  final PageController _fotoController = PageController();
  int _fotoAtual = 0;

  @override
  void dispose() {
    _fotoController.dispose();
    super.dispose();
  }

  void _dispararRotaEVoltar({required LatLng origem, required LatLng destino, required String nomeDestino}) {
    rotaPendenteGlobal.value = RotaPendente(origem: origem, destino: destino, nomeDestino: nomeDestino);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _rotaDaMinhaLocalizacaoAteAqui() async {
    // a rota sai de onde a pessoa esta: sem permissao, explica e pergunta --
    // mesmo painel do mapa, pra o pedido ser sempre o mesmo em todo o app
    if (!LocalizacaoService.instance.permitida) {
      final liberou = await pedirLocalizacaoComExplicacao(context);
      if (!liberou || !mounted) return;
    }

    setState(() => _buscandoLocalizacao = true);
    LatLng? origem;
    try {
      origem = await LocalizacaoService.instance.posicaoParaRota();
    } catch (e) {
      origem = null;
    }
    if (!mounted) return;
    setState(() => _buscandoLocalizacao = false);

    if (origem == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não conseguimos acessar sua localização agora.'), backgroundColor: corErro),
      );
      return;
    }
    _dispararRotaEVoltar(origem: origem, destino: widget.imovel.posicao, nomeDestino: widget.imovel.titulo);
  }

  // mesmo motor de busca hibrida da barra principal do mapa (locais
  // conhecidos + imoveis cadastrados + Nominatim online) -- em vez de
  // geocodificar o texto cru (que falhava toda hora com "nao encontramos
  // esse endereco"), a rota usa direto a coordenada da sugestao escolhida
  Future<void> _rotaDaquiParaDestinoDigitado() async {
    List<Imovel> imoveis = [];
    try {
      final snap = await FirebaseFirestore.instance.collection('imoveis').get();
      imoveis = snap.docs.map((d) => Imovel.fromMap(d.data(), d.id)).toList();
    } catch (_) {
      // sem os imoveis cadastrados a busca ainda funciona (locais conhecidos + online)
    }
    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sugestaoEscolhida = await showModalBottomSheet<SugestaoBusca>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? superficieEscura : superficieClara,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) => _SeletorDeDestino(imoveis: imoveis),
    );
    if (sugestaoEscolhida == null || !mounted) return;

    _dispararRotaEVoltar(
      origem: widget.imovel.posicao,
      destino: sugestaoEscolhida.destino,
      nomeDestino: sugestaoEscolhida.texto,
    );
  }

  void _abrirModalDeRota() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? superficieEscura : superficieClara,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withAlpha(30) : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Text(
                  'Como você quer traçar a rota?',
                  style: AppTextStyles.heading3.copyWith(color: isDark ? Colors.white : Colors.black87),
                ),
                const SizedBox(height: 16),
                _opcaoRota(
                  isDark: isDark,
                  icone: Icons.my_location_rounded,
                  titulo: 'Definir rota até o local do anúncio',
                  subtitulo: 'Da sua localização atual até aqui',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _rotaDaMinhaLocalizacaoAteAqui();
                  },
                ),
                const SizedBox(height: 12),
                _opcaoRota(
                  isDark: isDark,
                  icone: Icons.edit_location_alt_rounded,
                  titulo: 'Ver rota da casa até um destino',
                  subtitulo: 'Digite pra onde você quer ir',
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _rotaDaquiParaDestinoDigitado();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _opcaoRota({
    required bool isDark,
    required IconData icone,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withAlpha(8) : Colors.grey.withAlpha(15),
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(gradient: gradientePrincipal, borderRadius: BorderRadius.circular(12)),
              child: Icon(icone, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitulo,
                    style: TextStyle(color: isDark ? Colors.white38 : Colors.grey, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: isDark ? Colors.white38 : Colors.grey),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final imovel = widget.imovel;
    final bool isEvento = imovel.tipo == TipoListing.evento;

    return Scaffold(
      backgroundColor: isDark ? corSuperficieEscura : const Color(0xFFF8F7FF),
      // cabecalho em imagem cheia: o body passa por tras da status bar pra
      // foto sangrar ate o topo, igual app de viagem/imovel moderno
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // SliverAppBar colapsavel: a foto encolhe ao rolar e o titulo
              // migra pra barra. Isso e o movimento que a tela nao tinha --
              // antes era um carrossel solto no meio de uma ListView
              SliverAppBar(
                expandedHeight: 330,
                pinned: true,
                stretch: true,
                elevation: 0,
                backgroundColor: isDark ? corSuperficieEscura : Colors.white,
                surfaceTintColor: Colors.transparent,
                leadingWidth: 64,
                leading: Center(child: _botaoVoltar(isEvento)),
                // titulo so aparece com a barra colapsada, senao competiria
                // com o titulo grande que esta sobre a foto
                title: _TituloColapsado(titulo: imovel.titulo, isDark: isDark),
                flexibleSpace: FlexibleSpaceBar(
                  stretchModes: const [StretchMode.zoomBackground],
                  background: _cabecalhoFoto(imovel, isEvento, isDark),
                ),
              ),

              SliverToBoxAdapter(
                // a folha sobe 26px por cima da foto -- sobreposicao e o que
                // da profundidade e amarra o conteudo ao cabecalho
                child: Transform.translate(
                  offset: const Offset(0, -26),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? corSuperficieEscura : const Color(0xFFF8F7FF),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
                    ),
                    // o topo paga os 26px que a folha subiu por cima da foto,
                    // senao o titulo encosta na imagem -- era o que acontecia:
                    // 24 de padding menos 26 de sobreposicao davam ZERO de
                    // respiro entre a foto e o texto
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xxl, AppSpacing.xxl + 26, AppSpacing.xxl, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // puxador: marca onde a folha comeca. Sem foto (ou com
                        // foto escura) a superficie se confundia com a imagem
                        // e nao dava pra ver onde uma acabava e a outra comecava
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white24 : Colors.black12,
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                            ),
                          ),
                        ),
                        Text(
                          imovel.titulo,
                          style: AppTextStyles.heading2.copyWith(
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Icon(Icons.location_on_rounded, size: 15, color: corPrimaria.withAlpha(180)),
                            const SizedBox(width: AppSpacing.xs + 1),
                            Expanded(
                              child: Text(
                                imovel.endereco.isNotEmpty ? imovel.endereco : 'Endereço não informado',
                                style: AppTextStyles.caption.copyWith(
                                  color: isDark ? Colors.white38 : Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),

                        if (imovel.bairro.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.md),
                          _chipBairro(imovel, isDark),
                        ],

                        if (!isEvento) ...[
                          const SizedBox(height: AppSpacing.xl),
                          _cartaoPreco(imovel, isDark),
                        ],

                        if (imovel.descricao.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xl),
                          Text(
                            imovel.descricao,
                            style: AppTextStyles.body.copyWith(
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ],

                        if (imovel.tags.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xl),
                          Wrap(
                            spacing: AppSpacing.sm,
                            runSpacing: AppSpacing.sm,
                            // a tag de faculdade vira a distancia real medida ate o Inatel --
                            // "Perto da Faculdade" e opiniao de quem anunciou,
                            // "320 m da faculdade" e verificavel
                            children: imovel.tags
                                .map((tag) => _pilula(
                                      tag == tagPertoDaFaculdade
                                          ? rotuloDistanciaFaculdade(imovel.posicao)
                                          : tag,
                                      isDark,
                                    ))
                                .toList(),
                          ),
                        ],

                        if (!isEvento) ...[
                          const SizedBox(height: AppSpacing.xl),
                          _secaoInclusos(imovel, isDark),
                          const SizedBox(height: AppSpacing.xl),
                          _secaoDetalhes(imovel, isDark),
                        ],

                        const SizedBox(height: AppSpacing.xl),
                        _secaoLocalizacao(imovel, isDark),

                        const SizedBox(height: AppSpacing.xl),
                        _buildSecaoAnunciante(isDark),

                        // respiro pra barra de acoes fixa nao cobrir o fim
                        // do conteudo quando a rolagem chega no fim
                        const SizedBox(height: 120),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // acoes fixas na base: antes eram dois botoes no fim da rolagem, o
          // que obrigava a rolar a tela toda pra pedir rota ou mandar mensagem
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _barraDeAcoes(imovel, isEvento, isDark),
          ),
        ],
      ),
    );
  }

  Widget _botaoVoltar(bool isEvento) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(99.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(99.0),
        onTap: () => Navigator.pop(context),
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: isEvento ? gradienteEvento : gradientePrincipal,
            borderRadius: BorderRadius.circular(99.0),
            boxShadow: AppShadows.marca(forca: 0.8),
          ),
          child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  // foto cheia com scrim, ou um estado vazio decente. O estado vazio importa
  // muito aqui: boa parte dos anuncios do banco nao tem foto, e antes a tela
  // simplesmente abria com um vazio enorme que parecia tela quebrada
  // bairro do imovel, clicavel: leva pro mapa com o contorno tracejado da
  // regiao, igual o Google Maps faz quando voce toca no nome de um bairro.
  // Antes o bairro so aparecia perdido na lista de "Detalhes", como texto
  Widget _chipBairro(Imovel imovel, bool isDark) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Pressionavel(
        onTap: () {
          bairroPendenteGlobal.value = BairroPendente(
            nome: imovel.bairro,
            perto: imovel.posicao,
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withAlpha(14) : Colors.white,
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
              Icon(Icons.map_outlined,
                  size: 15, color: isDark ? Colors.white54 : corPrimaria),
              const SizedBox(width: AppSpacing.xs + 2),
              Text(
                'Bairro ${imovel.bairro}',
                style: AppTextStyles.captionBold.copyWith(
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.arrow_forward_ios_rounded,
                  size: 11, color: isDark ? Colors.white38 : Colors.black38),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cabecalhoFoto(Imovel imovel, bool isEvento, bool isDark) {
    final bool temFoto = imovel.fotos.isNotEmpty;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (temFoto)
          PageView.builder(
            controller: _fotoController,
            itemCount: imovel.fotos.length,
            onPageChanged: (i) => setState(() => _fotoAtual = i),
            itemBuilder: (_, i) => Image.network(
              imovel.fotos[i],
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fundoSemFoto(isEvento),
              loadingBuilder: (_, filho, progresso) =>
                  progresso == null ? filho : _fundoSemFoto(isEvento),
            ),
          )
        else
          _fundoSemFoto(isEvento),

        // scrim so na base -- sem ele o titulo branco some em foto clara
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: 120,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withAlpha(0),
                    Colors.black.withAlpha(isDark ? 150 : 110),
                  ],
                ),
              ),
            ),
          ),
        ),

        if (temFoto && imovel.fotos.length > 1)
          Positioned(
            bottom: AppSpacing.xxl + AppSpacing.sm,
            left: 0,
            right: 0,
            child: _indicadorDeFotos(imovel.fotos.length),
          ),
      ],
    );
  }

  Widget _fundoSemFoto(bool isEvento) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: isEvento ? gradienteEvento : gradientePrincipal,
      ),
      child: Center(
        child: Icon(
          isEvento ? Icons.celebration_rounded : Icons.home_work_rounded,
          size: 64,
          color: Colors.white.withAlpha(90),
        ),
      ),
    );
  }

  // pontinhos de pagina: a largura do ativo cresce, em vez de so mudar de cor
  Widget _indicadorDeFotos(int total) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < total; i++)
          AnimatedContainer(
            duration: AppMotion.media,
            curve: AppMotion.suave,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == _fotoAtual ? 20 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(i == _fotoAtual ? 245 : 120),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          ),
      ],
    );
  }

  Widget _cartaoPreco(Imovel imovel, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl, vertical: AppSpacing.lg),
      decoration: BoxDecoration(
        color: isDark ? corSuperficieEscura : Colors.white,
        borderRadius: BorderRadius.circular(99.0),
        boxShadow: AppShadows.nivel1(isDark),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(14) : corPrimaria.withAlpha(20),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'Aluguel mensal',
            style: AppTextStyles.caption.copyWith(
              color: isDark ? Colors.white38 : Colors.grey,
            ),
          ),
          ShaderMask(
            shaderCallback: (bounds) => gradienteSecundario.createShader(bounds),
            child: Text(
              '${formatarPreco(imovel.preco)}/mês',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pilula(String texto, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md + 2, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(10) : corPrimaria.withAlpha(12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(14) : corPrimaria.withAlpha(28),
        ),
      ),
      child: Text(
        texto,
        style: AppTextStyles.captionBold.copyWith(
          fontSize: 12,
          color: isDark ? Colors.white70 : corPrimaria,
        ),
      ),
    );
  }

  Widget _barraDeAcoes(Imovel imovel, bool isEvento, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? superficieEscura : superficieClara,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 70 : 18),
            blurRadius: 26,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: AnimatedGradientButton(
                  label: 'Calcular Rota',
                  icon: Icons.alt_route_rounded,
                  isLoading: _buscandoLocalizacao,
                  onTap: _abrirModalDeRota,
                ),
              ),
              if (!isEvento) ...[
                const SizedBox(width: AppSpacing.md),
                // so o icone: dois botoes de largura cheia lado a lado nao
                // cabem, e "Calcular Rota" e a acao principal aqui
                Pressionavel(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ChatDetailScreen(
                          imovelTitulo: imovel.titulo,
                          imovelId: imovel.id,
                          donoUid: imovel.donoUid,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withAlpha(14) : corPrimaria.withAlpha(14),
                      borderRadius: BorderRadius.circular(99.0),
                      border: Border.all(
                        color: isDark ? Colors.white.withAlpha(20) : corPrimaria.withAlpha(34),
                      ),
                    ),
                    child: Icon(Icons.chat_bubble_outline_rounded, color: corPrimaria, size: 22),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _tituloSecao(String texto, bool isDark) => Text(
        texto,
        style: AppTextStyles.captionBold.copyWith(
          color: isDark ? Colors.white70 : Colors.black87,
        ),
      );

  // contas inclusas -- campos que o modelo Imovel sempre teve e a tela nunca
  // mostrou. Exibe os tres com estado ligado/desligado em vez de so os
  // inclusos: saber que a luz NAO esta inclusa e tao util quanto o contrario
  Widget _secaoInclusos(Imovel imovel, bool isDark) {
    final itens = [
      ('Luz', Icons.bolt_rounded, imovel.incluiLuz),
      ('Água', Icons.water_drop_rounded, imovel.incluiAgua),
      ('Wi-Fi', Icons.wifi_rounded, imovel.incluiWifi),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tituloSecao('Contas inclusas', isDark),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            for (final (rotulo, icone, incluso) in itens) ...[
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md + 2),
                  decoration: BoxDecoration(
                    color: incluso
                        ? corSucesso.withAlpha(isDark ? 32 : 20)
                        : (isDark ? Colors.white.withAlpha(8) : Colors.grey.withAlpha(18)),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: incluso
                          ? corSucesso.withAlpha(70)
                          : (isDark ? Colors.white.withAlpha(12) : Colors.grey.withAlpha(35)),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        icone,
                        size: 20,
                        color: incluso ? corSucesso : (isDark ? Colors.white30 : Colors.grey),
                      ),
                      const SizedBox(height: AppSpacing.xs + 2),
                      Text(
                        rotulo,
                        style: AppTextStyles.label.copyWith(
                          fontWeight: FontWeight.w600,
                          color: incluso
                              ? corSucesso
                              : (isDark ? Colors.white30 : Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (rotulo != 'Wi-Fi') const SizedBox(width: AppSpacing.sm),
            ],
          ],
        ),
      ],
    );
  }

  // ficha do imovel -- so mostra linha que tem valor, pra nao virar lista de
  // "nao informado"
  Widget _secaoDetalhes(Imovel imovel, bool isDark) {
    final linhas = <(String, String)>[
      if (imovel.tipoImovel.isNotEmpty) ('Tipo', imovel.tipoImovel),
      if (imovel.andar.isNotEmpty) ('Andar', imovel.andar),
      if (imovel.bairro.isNotEmpty) ('Bairro', imovel.bairro),
      if (imovel.cidade.isNotEmpty)
        ('Cidade', imovel.estado.isNotEmpty ? '${imovel.cidade} - ${imovel.estado}' : imovel.cidade),
      if (imovel.iptuValor > 0) ('IPTU', formatarPreco(imovel.iptuValor)),
    ];
    if (linhas.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tituloSecao('Ficha do imóvel', isDark),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withAlpha(8) : Colors.white,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: AppShadows.nivel1(isDark),
          ),
          child: Column(
            children: [
              for (var i = 0; i < linhas.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    color: isDark ? Colors.white.withAlpha(10) : Colors.grey.withAlpha(20),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md + 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        linhas[i].$1,
                        style: AppTextStyles.caption.copyWith(
                          color: isDark ? Colors.white38 : Colors.grey,
                        ),
                      ),
                      Text(
                        linhas[i].$2,
                        style: AppTextStyles.captionBold.copyWith(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // previa do local em LITE MODE: o Android desenha um bitmap estatico em vez
  // de instanciar um mapa interativo. Isso importa muito aqui -- platform view
  // interativa foi a origem dos travamentos do mapa principal, e uma previa
  // nao precisa de gesto nenhum
  Widget _secaoLocalizacao(Imovel imovel, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tituloSecao('Localização', isDark),
        const SizedBox(height: AppSpacing.md),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: SizedBox(
            height: 170,
            child: Stack(
              children: [
                // AbsorbPointer e obrigatorio aqui, nao e zelo: desligar os
                // gestos do GoogleMap NAO basta -- a platform view do Android
                // ainda consome o toque, e arrastar em cima da previa deixava
                // de rolar a pagina e disparava a rota (visto no aparelho).
                // Com o toque absorvido, o arraste vai pro Scrollable e o
                // InkWell de cima fica so com o tap
                AbsorbPointer(
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(target: imovel.posicao, zoom: 15.5),
                    liteModeEnabled: true,
                    zoomControlsEnabled: false,
                    myLocationButtonEnabled: false,
                    // nenhum gesto: e uma imagem, nao um mapa pra explorar
                    zoomGesturesEnabled: false,
                    scrollGesturesEnabled: false,
                    rotateGesturesEnabled: false,
                    tiltGesturesEnabled: false,
                    markers: {
                      Marker(markerId: const MarkerId('previa'), position: imovel.posicao),
                    },
                  ),
                ),
                // toque na previa abre a rota, que e o que a pessoa quer
                // fazer depois de ver onde fica
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(onTap: _abrirModalDeRota),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSecaoAnunciante(bool isDark) {
    if (widget.imovel.donoUid.isEmpty) return const SizedBox.shrink();

    return FutureBuilder<PerfilPublico?>(
      future: PerfilPublicoService.instance.buscarPorUid(widget.imovel.donoUid),
      builder: (context, snapshot) {
        final carregando = snapshot.connectionState == ConnectionState.waiting;
        final dono = snapshot.data;
        final nomeExibido = (dono?.nome.isNotEmpty ?? false) ? dono!.nome : 'Anunciante';

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: isDark ? superficieEscura : superficieClara, borderRadius: BorderRadius.circular(18)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Anunciante', style: AppTextStyles.captionBold.copyWith(color: isDark ? Colors.white70 : Colors.black87)),
              const SizedBox(height: 12),
              Row(
                children: [
                  AvatarWidget(nome: nomeExibido, fotoUrl: dono?.fotoUrl, size: 52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nomeExibido,
                          style: TextStyle(fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black87),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        if (carregando)
                          SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: isDark ? Colors.white38 : Colors.grey),
                          )
                        else if (dono == null)
                          Text(
                            'Dados indisponíveis',
                            style: AppTextStyles.caption.copyWith(color: isDark ? Colors.white38 : Colors.grey),
                          )
                        else ...[
                          StreamBuilder<List<Avaliacao>>(
                            stream: AvaliacaoService.instance.streamAvaliacoes('usuarios', dono.uid),
                            builder: (context, avSnap) {
                              final avaliacoes = avSnap.data ?? [];
                              if (avaliacoes.isEmpty) {
                                return Text(
                                  'Sem avaliações ainda',
                                  style: AppTextStyles.caption.copyWith(color: isDark ? Colors.white38 : Colors.grey),
                                );
                              }
                              final media = avaliacoes.map((a) => a.nota).reduce((a, b) => a + b) / avaliacoes.length;
                              return Row(
                                children: [
                                  const Icon(Icons.star_rounded, color: corAtencao, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${media.toStringAsFixed(1)} (${avaliacoes.length})',
                                    style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              );
                            },
                          ),
                          Row(
                            children: [
                              Icon(Icons.circle, size: 6, color: corSucesso.withAlpha(180)),
                              const SizedBox(width: 5),
                              Text(
                                formatarUltimoAcesso(dono.ultimoAcesso),
                                style: AppTextStyles.caption.copyWith(color: isDark ? Colors.white38 : Colors.grey, fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (dono != null)
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => PerfilPublicoScreen(pessoa: dono)),
                      ),
                      child: const Text('Ver perfil'),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// campo de busca hibrida (a mesma logica da barra do mapa) dentro do modal
// de rota -- sugere locais conhecidos, imoveis do sistema e, depois de um
// pouco, ruas/bairros de verdade via busca online. Devolve a SugestaoBusca
// escolhida (com a coordenada ja pronta) via Navigator.pop
class _SeletorDeDestino extends StatefulWidget {
  final List<Imovel> imoveis;
  const _SeletorDeDestino({required this.imoveis});

  @override
  State<_SeletorDeDestino> createState() => _SeletorDeDestinoState();
}

class _SeletorDeDestinoState extends State<_SeletorDeDestino> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<SugestaoBusca> _sugestoes = [];
  bool _buscando = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _aoDigitar(String texto) {
    _debounce?.cancel();
    if (texto.trim().length < 2) {
      setState(() {
        _sugestoes = [];
        _buscando = false;
      });
      return;
    }

    setState(() {
      _sugestoes = BuscaService.instance.buscarSugestoes(texto, widget.imoveis);
      _buscando = true;
    });

    _debounce = Timer(const Duration(milliseconds: 400), () async {
      // achou instituicao conhecida (Inatel, UNIFEI...) -- nao busca online
      // pra evitar bairro homonimo competindo com o pin certo
      final achouInstituicao = _sugestoes.any((s) => s.tipo == TipoSugestao.faculdade);
      if (!achouInstituicao) {
        final online = await BuscaService.instance.buscarLocaisOnline(texto);
        if (mounted && _controller.text == texto) {
          setState(() {
            final jaTem = _sugestoes.map((s) => s.texto.toLowerCase()).toSet();
            for (final s in online) {
              if (jaTem.add(s.texto.toLowerCase())) _sugestoes.add(s);
            }
          });
        }
      }
      if (mounted) setState(() => _buscando = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withAlpha(30) : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Pra onde você quer ir?', style: AppTextStyles.heading3.copyWith(color: isDark ? Colors.white : Colors.black87)),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _aoDigitar,
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
              decoration: InputDecoration(
                hintText: 'Ex: Inatel, um bairro, uma rua...',
                hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                prefixIcon: const Icon(Icons.search_rounded, color: corPrimaria),
                filled: true,
                fillColor: isDark ? Colors.white.withAlpha(8) : Colors.grey.withAlpha(15),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: _sugestoes.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        _buscando ? 'Buscando...' : 'Digite pra ver sugestões de ruas, bairros, instituições e imóveis.',
                        style: AppTextStyles.caption.copyWith(color: isDark ? Colors.white38 : Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _sugestoes.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        color: isDark ? Colors.white.withAlpha(10) : Colors.grey.withAlpha(20),
                      ),
                      itemBuilder: (context, index) {
                        final sugestao = _sugestoes[index];
                        final icone = switch (sugestao.tipo) {
                          TipoSugestao.cidade => Icons.location_city_rounded,
                          TipoSugestao.faculdade => Icons.school_rounded,
                          TipoSugestao.moradia => Icons.home_rounded,
                          TipoSugestao.endereco => Icons.signpost_outlined,
                        };
                        return ListTile(
                          leading: Icon(icone, color: corPrimaria),
                          title: Text(
                            sugestao.texto,
                            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () => Navigator.pop(context, sugestao),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}


// titulo que so aparece quando a SliverAppBar esta colapsada. Enquanto a foto
// esta aberta ele ficaria competindo com o titulo grande logo abaixo, entao
// aparece por fade conforme a barra fecha.
//
// Le a fracao de colapso do FlexibleSpaceBarSettings em vez de escutar o
// ScrollController: e o proprio Sliver que publica esse valor, e assim o
// widget nao precisa saber nada sobre a rolagem
class _TituloColapsado extends StatelessWidget {
  final String titulo;
  final bool isDark;

  const _TituloColapsado({required this.titulo, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final ajustes = context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    double opacidade = 0;
    if (ajustes != null) {
      final vao = ajustes.maxExtent - ajustes.minExtent;
      if (vao > 0) {
        final fechado = 1 - ((ajustes.currentExtent - ajustes.minExtent) / vao);
        // so comeca a aparecer depois de 70% fechada, senao os dois titulos
        // ficam visiveis ao mesmo tempo no meio do caminho
        opacidade = (((fechado - 0.7) / 0.3)).clamp(0.0, 1.0);
      }
    }

    return Opacity(
      opacity: opacidade,
      child: Text(
        titulo,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.heading3.copyWith(
          fontSize: 17,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
    );
  }
}
