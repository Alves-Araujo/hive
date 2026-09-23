import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart';
import '../models/imovel.dart';
import '../models/usuario.dart';
import '../utils/cor_foto.dart';
import '../widgets/card_imovel_vertical.dart';
import '../widgets/cabecalho_tela.dart';
import '../widgets/seletor_tipo_resumo.dart';
import '../widgets/papel_parede_resumo.dart';

class TelaResumo extends StatefulWidget {
  final Usuario perfil;
  const TelaResumo({super.key, required this.perfil});

  @override
  State<TelaResumo> createState() => _TelaResumoState();
}

class _TelaResumoState extends State<TelaResumo>
    with SingleTickerProviderStateMixin {
  String _filtroTipo = 'Todos';
  late AnimationController _listAnimController;
  // Nao reinicia a assinatura quando o tema ou os filtros mudam.
  late final Stream<QuerySnapshot> _imoveisStream = FirebaseFirestore.instance
      .collection('imoveis')
      .snapshots();

  @override
  void initState() {
    super.initState();
    _listAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      // A aba ja tem sua entrada animada; os cards ficam prontos para exibir.
      value: 1,
    );
  }

  @override
  void dispose() {
    _listAnimController.dispose();
    super.dispose();
  }

  void _mudarFiltro(String novoFiltro) {
    if (_filtroTipo == novoFiltro) return;
    setState(() => _filtroTipo = novoFiltro);
    if (MediaQuery.disableAnimationsOf(context)) {
      _listAnimController.value = 1;
    } else {
      _listAnimController.forward(from: 0);
    }
  }

  // null = Todos, pro papel de parede saber qual familia de simbolo desenhar
  TipoListing? get _tipoDoFiltro => switch (_filtroTipo) {
    'Moradias' => TipoListing.moradia,
    'Eventos' => TipoListing.evento,
    _ => null,
  };

  String get _primeiroNome {
    final partes = widget.perfil.nome.split(' ');
    return partes.isNotEmpty && partes[0].isNotEmpty ? partes[0] : 'Visitante';
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        CabecalhoTela(
          padronizarAltura: true,
          titulo: 'Olá, $_primeiroNome!',
          subtitulo: 'Encontre o lugar ideal para você',
          inicio: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: gradientePrincipal,
              border: Border.all(color: corPrimaria2, width: 1.5),
            ),
            child: ClipOval(
              child: widget.perfil.fotoUrl.isNotEmpty
                  ? Image(
                      image: fotoAvatar(
                        widget.perfil.fotoUrl,
                        40,
                        MediaQuery.devicePixelRatioOf(context),
                      ),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.person_rounded, color: Colors.white),
                    )
                  : const Icon(
                      Icons.person_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
            ),
          ),
          rodape: SeletorTipoResumo(
            selecionado: _filtroTipo,
            onChanged: _mudarFiltro,
          ),
        ),

        // lista de imoveis
        Expanded(
          child: PapelDeParedeResumo(
            tipo: _tipoDoFiltro,
            child: StreamBuilder<QuerySnapshot>(
              stream: _imoveisStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: corPrimaria),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Erro ao carregar dados.',
                      style: AppTextStyles.body.copyWith(color: corErro),
                    ),
                  );
                }

                final imoveisDoBanco =
                    snapshot.data?.docs.map((doc) {
                      return Imovel.fromMap(
                        doc.data() as Map<String, dynamic>,
                        doc.id,
                      );
                    }).toList() ??
                    [];

                final imoveisFiltrados = imoveisDoBanco.where((i) {
                  // mesmo corte do mapa: anuncio abandonado (cinco meses com
                  // mensagem sem resposta) tambem nao aparece na lista, senao
                  // sumir do mapa nao resolveria nada -- ver
                  // utils/inatividade.dart
                  if (i.foraDoMapaPorFaltaDeResposta) return false;
                  if (_filtroTipo == 'Todos') return true;
                  if (_filtroTipo == 'Moradias') {
                    return i.tipo == TipoListing.moradia;
                  }
                  return i.tipo == TipoListing.evento;
                }).toList();

                if (imoveisFiltrados.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          decoration: BoxDecoration(
                            color: isDark
                                ? superficieEscura.withAlpha(80)
                                : superficieClara.withAlpha(180),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.search_off_rounded,
                            size: 48,
                            color: isDark
                                ? Colors.white.withAlpha(51)
                                : Colors.grey.shade300,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'Nenhum resultado encontrado.',
                          style: AppTextStyles.body.copyWith(
                            color: isDark ? Colors.white30 : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md + 2,
                    AppSpacing.lg,
                    // com extendBody: true o body vai ate a base da tela e a
                    // barra inferior fica por cima -- sem esse reforco o
                    // ultimo card da lista ficava escondido atras dela.
                    // MediaQuery.padding.bottom aqui ja e a altura REAL da
                    // barra (o Scaffold soma ela ao inset por causa do
                    // extendBody), igual e feito no mapa em map_screen.dart
                    MediaQuery.of(context).padding.bottom + AppSpacing.md + 2,
                  ),
                  physics: const BouncingScrollPhysics(),
                  itemCount: imoveisFiltrados.length,
                  itemBuilder: (context, index) {
                    final imovel = imoveisFiltrados[index];

                    final delay = (index * 0.08).clamp(0.0, 0.6);
                    final end = (delay + 0.4).clamp(0.0, 1.0);
                    final slideAnim =
                        Tween<Offset>(
                          begin: const Offset(0, 0.1),
                          end: Offset.zero,
                        ).animate(
                          _listAnimController.drive(
                            CurveTween(
                              curve: Interval(
                                delay,
                                end,
                                curve: AppMotion.suave,
                              ),
                            ),
                          ),
                        );
                    final fadeAnim = Tween<double>(begin: 0.0, end: 1.0)
                        .animate(
                          _listAnimController.drive(
                            CurveTween(
                              curve: Interval(
                                delay,
                                end,
                                curve: Curves.easeOut,
                              ),
                            ),
                          ),
                        );

                    return FadeTransition(
                      key: ValueKey(imovel.id),
                      opacity: fadeAnim,
                      child: SlideTransition(
                        position: slideAnim,
                        child: RepaintBoundary(
                          child: CardImovelVertical(
                            imovel: imovel,
                            isDark: isDark,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
