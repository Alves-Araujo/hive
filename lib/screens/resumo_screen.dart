import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart';
import '../models/imovel.dart';
import '../models/usuario.dart';
import '../utils/cor_foto.dart';
import '../widgets/card_imovel_vertical.dart';
import '../widgets/cabecalho_tela.dart';
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
      duration: const Duration(milliseconds: 300),
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
    setState(() => _filtroTipo = novoFiltro);
    _listAnimController.reset();
    _listAnimController.forward();
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
          rodape: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withAlpha(35)
                    : corPrimaria.withAlpha(10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withAlpha(12)
                      : corPrimaria.withAlpha(15),
                ),
              ),
              child: Row(
                children: [
                  _FiltroChip(
                    label: 'Todos',
                    icon: Icons.apps_rounded,
                    selected: _filtroTipo == 'Todos',
                    onTap: () => _mudarFiltro('Todos'),
                    isDark: isDark,
                  ),
                  const SizedBox(width: 2),
                  _FiltroChip(
                    label: 'Moradias',
                    icon: Icons.home_rounded,
                    selected: _filtroTipo == 'Moradias',
                    onTap: () => _mudarFiltro('Moradias'),
                    isDark: isDark,
                  ),
                  const SizedBox(width: 2),
                  _FiltroChip(
                    label: 'Eventos',
                    icon: Icons.celebration_rounded,
                    selected: _filtroTipo == 'Eventos',
                    onTap: () => _mudarFiltro('Eventos'),
                    isDark: isDark,
                    isEvento: true,
                  ),
                ],
              ),
            ),
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
                  if (_filtroTipo == 'Todos') return true;
                  if (_filtroTipo == 'Moradias')
                    return i.tipo == TipoListing.moradia;
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
                          CurvedAnimation(
                            parent: _listAnimController,
                            curve: Interval(delay, end, curve: AppMotion.suave),
                          ),
                        );
                    final fadeAnim = Tween<double>(begin: 0.0, end: 1.0)
                        .animate(
                          CurvedAnimation(
                            parent: _listAnimController,
                            curve: Interval(delay, end, curve: Curves.easeOut),
                          ),
                        );

                    return FadeTransition(
                      opacity: fadeAnim,
                      child: SlideTransition(
                        position: slideAnim,
                        child: CardImovelVertical(
                          imovel: imovel,
                          isDark: isDark,
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

class _FiltroChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;
  final bool isEvento;

  const _FiltroChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.isDark,
    this.isEvento = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.rapida,
        constraints: const BoxConstraints(minHeight: 42),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          gradient: selected
              ? (isEvento ? gradienteEvento : gradientePrincipal)
              : null,
          color: selected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected
                  ? Colors.white
                  : (isDark ? Colors.white60 : Colors.black54),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? Colors.white
                    : (isDark ? Colors.white60 : Colors.black87),
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// card vertical estilo premium — imagem grande no topo, info em baixo,
// com preco flutuando sobre a imagem
