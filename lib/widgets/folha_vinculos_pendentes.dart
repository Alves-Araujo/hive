import 'package:flutter/material.dart';
import '../main.dart';
import '../models/imobiliaria.dart';
import '../models/perfil_publico.dart';
import '../services/imobiliaria_service.dart';
import 'avatar_widget.dart';

// Corretores que pediram vinculo com a imobiliaria desta conta, um a um, com
// aprovar e recusar. Aparece pra quem entra com o e-mail da imobiliaria --
// que e o unico jeito que o app tem hoje de saber quem responde por ela.
//
// A resposta e por pessoa de proposito: aprovar todo mundo de uma vez tambem
// aprovaria quem so DIZ que trabalha la, que e exatamente o que essa tela
// existe pra filtrar.
class FolhaVinculosPendentes extends StatefulWidget {
  final Imobiliaria imobiliaria;
  final List<PerfilPublico> pendentes;
  final bool isDark;

  const FolhaVinculosPendentes({
    super.key,
    required this.imobiliaria,
    required this.pendentes,
    required this.isDark,
  });

  @override
  State<FolhaVinculosPendentes> createState() => _FolhaVinculosPendentesState();
}

class _FolhaVinculosPendentesState extends State<FolhaVinculosPendentes> {
  // quem ja foi respondido nesta folha sai da lista na hora, sem esperar uma
  // releitura do Firestore
  final Set<String> _respondidos = {};
  String? _processando;

  Future<void> _responder(PerfilPublico corretor, bool aprovado) async {
    setState(() => _processando = corretor.uid);
    try {
      await ImobiliariaService.instance.responderVinculo(
        imobiliariaId: widget.imobiliaria.id,
        corretorUid: corretor.uid,
        aprovado: aprovado,
      );
      if (!mounted) return;
      setState(() => _respondidos.add(corretor.uid));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível responder agora: $e'), backgroundColor: corErro),
      );
    } finally {
      if (mounted) setState(() => _processando = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final restantes =
        widget.pendentes.where((p) => !_respondidos.contains(p.uid)).toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.xxl,
        AppSpacing.xxl,
        AppSpacing.xxl + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.apartment_rounded, color: corPrimaria, size: 40),
          const SizedBox(height: AppSpacing.md),
          Text(
            restantes.isEmpty
                ? 'Tudo respondido'
                : 'Pedidos de vínculo com "${widget.imobiliaria.nome}"',
            style: AppTextStyles.heading3.copyWith(
              color: isDark ? Colors.white : Colors.black87,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            restantes.isEmpty
                ? 'Os corretores aprovados já podem anunciar pela imobiliária.'
                : 'Aprove só quem trabalha aí. Quem for aprovado passa a anunciar '
                    'imóveis em nome da imobiliária.',
            style: AppTextStyles.caption.copyWith(
              color: isDark ? Colors.white54 : Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          if (restantes.isNotEmpty)
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: restantes.length,
                separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
                itemBuilder: (context, i) => _linhaCorretor(restantes[i], isDark),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              restantes.isEmpty ? 'Fechar' : 'Responder depois',
              style: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linhaCorretor(PerfilPublico corretor, bool isDark) {
    final ocupado = _processando == corretor.uid;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(8) : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(14) : corPrimaria.withAlpha(20),
        ),
      ),
      child: Row(
        children: [
          AvatarWidget(
            nome: corretor.nome,
            fotoUrl: corretor.fotoUrl,
            size: 40,
            showOnlineIndicator: false,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              corretor.nome.isNotEmpty ? corretor.nome : 'Corretor sem nome',
              style: AppTextStyles.bodyBold.copyWith(
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          if (ocupado)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: corPrimaria),
            )
          else ...[
            IconButton(
              tooltip: 'Recusar',
              onPressed: () => _responder(corretor, false),
              icon: const Icon(Icons.close_rounded, color: corErro),
            ),
            IconButton(
              tooltip: 'Aprovar',
              onPressed: () => _responder(corretor, true),
              icon: const Icon(Icons.check_rounded, color: corSucesso),
            ),
          ],
        ],
      ),
    );
  }
}
