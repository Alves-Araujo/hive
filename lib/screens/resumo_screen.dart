import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart';
import '../utils/distancia.dart';
import '../models/filtro_state.dart' show cidadeFiltroGlobal;
import '../models/imovel.dart';
import '../utils/moeda.dart';
import '../models/usuario.dart';
import '../widgets/card_imovel_vertical.dart';
import 'notificacoes_screen.dart';

class TelaResumo extends StatefulWidget {
  final Usuario perfil;
  const TelaResumo({super.key, required this.perfil});

  @override
  State<TelaResumo> createState() => _TelaResumoState();
}

class _TelaResumoState extends State<TelaResumo> with SingleTickerProviderStateMixin {
  String _filtroTipo = 'Todos';
  late AnimationController _listAnimController;

  @override
  void initState() {
    super.initState();
    _listAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _listAnimController.forward();
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

  String get _primeiroNome {
    final partes = widget.perfil.nome.split(' ');
    return partes.isNotEmpty && partes[0].isNotEmpty ? partes[0] : 'Visitante';
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final double topPadding = MediaQuery.of(context).padding.top;

    return Column(
      children: [
        // header — design premium, boas-vindas personalizadas
        Container(
          padding: EdgeInsets.only(
            top: topPadding + AppSpacing.md,
            left: AppSpacing.xl,
            right: AppSpacing.xl,
            bottom: AppSpacing.xl,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.55, 1],
              colors: isDark
                  ? [
                      Color.alphaBlend(Colors.white.withAlpha(15), superficieEscura),
                      superficieEscura.withAlpha(250),
                      Color.alphaBlend(corPrimaria.withAlpha(20), superficieEscura),
                    ]
                  : [
                      superficieClara,
                      superficieClara,
                      Color.alphaBlend(corPrimaria.withAlpha(8), superficieClara),
                    ],
            ),
            boxShadow: AppShadows.nivel2(isDark),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Avatar do usuario ou icone fallback
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: gradientePrincipal,
                      boxShadow: AppShadows.marca(forca: 0.3),
                      border: Border.all(
                        color: isDark ? Colors.white.withAlpha(40) : Colors.white,
                        width: 2,
                      ),
                    ),
                    child: ClipOval(
                      child: widget.perfil.fotoUrl.isNotEmpty
                          ? Image.network(
                              widget.perfil.fotoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => const Icon(Icons.person_rounded, color: Colors.white),
                            )
                          : const Icon(Icons.person_rounded, color: Colors.white, size: 24),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Olá, $_primeiroNome!',
                          style: AppTextStyles.heading2.copyWith(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 22,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Encontre o lugar ideal para você',
                          style: AppTextStyles.caption.copyWith(
                            color: isDark ? Colors.white54 : Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  const BotaoNotificacoes(),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              // chips de filtro — mais elaborados com icones
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _FiltroChip(
                      label: 'Todos',
                      icon: Icons.apps_rounded,
                      selected: _filtroTipo == 'Todos',
                      onTap: () => _mudarFiltro('Todos'),
                      isDark: isDark,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _FiltroChip(
                      label: 'Moradias',
                      icon: Icons.home_rounded,
                      selected: _filtroTipo == 'Moradias',
                      onTap: () => _mudarFiltro('Moradias'),
                      isDark: isDark,
                    ),
                    const SizedBox(width: AppSpacing.sm),
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
            ],
          ),
        ),

        // lista de imoveis
        Expanded(
          child: ValueListenableBuilder<String?>(
            valueListenable: cidadeFiltroGlobal,
            builder: (context, cidadeFiltro, _) => StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('imoveis').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: corPrimaria));
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text('Erro ao carregar dados.', style: AppTextStyles.body.copyWith(color: corErro)),
                  );
                }

                final imoveisDoBanco = snapshot.data?.docs.map((doc) {
                  return Imovel.fromMap(doc.data() as Map<String, dynamic>, doc.id);
                }).toList() ?? [];

                final imoveisFiltrados = imoveisDoBanco.where((i) {
                  if (cidadeFiltro != null && i.cidade != cidadeFiltro) return false;
                  if (_filtroTipo == 'Todos') return true;
                  if (_filtroTipo == 'Moradias') return i.tipo == TipoListing.moradia;
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
                            color: isDark ? superficieEscura.withAlpha(80) : superficieClara.withAlpha(180),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.search_off_rounded,
                            size: 48,
                            color: isDark ? Colors.white.withAlpha(51) : Colors.grey.shade300,
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md + 2,
                  ),
                  physics: const BouncingScrollPhysics(),
                  itemCount: imoveisFiltrados.length,
                  itemBuilder: (context, index) {
                    final imovel = imoveisFiltrados[index];

                    final delay = (index * 0.08).clamp(0.0, 0.6);
                    final end = (delay + 0.4).clamp(0.0, 1.0);
                    final slideAnim = Tween<Offset>(
                      begin: const Offset(0, 0.1),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: _listAnimController,
                      curve: Interval(delay, end, curve: AppMotion.suave),
                    ));
                    final fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
                      CurvedAnimation(
                        parent: _listAnimController,
                        curve: Interval(delay, end, curve: Curves.easeOut),
                      ),
                    );

                    return FadeTransition(
                      opacity: fadeAnim,
                      child: SlideTransition(
                        position: slideAnim,
                        child: CardImovelVertical(imovel: imovel, isDark: isDark),
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
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          gradient: selected ? (isEvento ? gradienteEvento : gradientePrincipal) : null,
          color: selected
              ? null
              : (isDark ? Colors.white.withAlpha(10) : Colors.grey.withAlpha(20)),
          borderRadius: BorderRadius.circular(99.0),
          boxShadow: selected ? AppShadows.nivel1(isDark) : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? Colors.white : (isDark ? Colors.white60 : Colors.black54),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : (isDark ? Colors.white60 : Colors.black87),
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
