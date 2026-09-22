import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart';
import '../models/imovel.dart';
import '../models/usuario.dart';
import '../utils/moeda.dart';
import '../widgets/cabecalho_tela.dart';
import '../widgets/pressionavel.dart';
import 'detalhes_imovel_screen.dart';
import 'novo_anuncio_screen.dart';

// dashboard so pra proprietarios/corretores -- lista os proprios imoveis
// cadastrados, atualizando ao vivo
class PainelScreen extends StatelessWidget {
  final Usuario perfil;
  const PainelScreen({super.key, required this.perfil});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        CabecalhoTela(
          titulo: 'Meus Imóveis',
          acao: Container(
            padding: const EdgeInsets.all(AppSpacing.sm + 2),
            decoration: BoxDecoration(
              gradient: gradientePrincipal,
              borderRadius: BorderRadius.circular(AppRadius.md),
              boxShadow: AppShadows.marca(forca: 0.4),
            ),
            child: const Icon(Icons.home_rounded, color: Colors.white, size: 22),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('imoveis')
                .where('donoUid', isEqualTo: perfil.uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: corPrimaria));
              }

              final imoveis = snapshot.data?.docs
                      .map((doc) => Imovel.fromMap(doc.data() as Map<String, dynamic>, doc.id))
                      .toList() ??
                  [];

              if (imoveis.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.home_work_outlined, size: 56, color: isDark ? Colors.white24 : Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text(
                        'Você ainda não cadastrou nenhum imóvel.',
                        style: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: imoveis.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) => _ItemPainel(imovel: imoveis[index], isDark: isDark),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ItemPainel extends StatelessWidget {
  final Imovel imovel;
  final bool isDark;

  const _ItemPainel({required this.imovel, required this.isDark});

  // Antes o card era so uma vitrine: o anuncio publicado nao tinha como ser
  // corrigido nem tirado do ar por dentro do app. O toque abre as duas acoes
  // que faltavam, e a exclusao ainda passa por uma confirmacao -- apagar
  // anuncio nao tem volta
  void _abrirAcoes(BuildContext context) {
    final bool isEvento = imovel.tipo == TipoListing.evento;
    final String oQue = isEvento ? 'evento' : 'imóvel';

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? corCardEscuro : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (folhaContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withAlpha(30) : Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                imovel.titulo,
                style: AppTextStyles.heading3.copyWith(color: isDark ? Colors.white : Colors.black87),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.lg),
              _opcao(
                context: folhaContext,
                icone: Icons.visibility_rounded,
                rotulo: 'Ver anúncio',
                descricao: 'Abre a ficha como as outras pessoas veem',
                onTap: () {
                  Navigator.pop(folhaContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => DetalhesImovelScreen(imovel: imovel)),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
              _opcao(
                context: folhaContext,
                icone: Icons.edit_rounded,
                rotulo: 'Alterar',
                descricao: 'Editar fotos, preço, endereço e detalhes',
                onTap: () {
                  Navigator.pop(folhaContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => NovoAnuncioScreen(imovel: imovel)),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
              _opcao(
                context: folhaContext,
                icone: Icons.delete_outline_rounded,
                rotulo: 'Apagar',
                descricao: 'Remove este $oQue do app',
                destrutiva: true,
                onTap: () {
                  Navigator.pop(folhaContext);
                  _confirmarExclusao(context, oQue);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _opcao({
    required BuildContext context,
    required IconData icone,
    required String rotulo,
    required String descricao,
    required VoidCallback onTap,
    bool destrutiva = false,
  }) {
    final Color cor = destrutiva ? corErro : corPrimaria;
    return Pressionavel(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md + 2),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withAlpha(8) : Colors.grey.withAlpha(15),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: cor.withAlpha(isDark ? 55 : 22),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icone, color: cor, size: 20),
            ),
            const SizedBox(width: AppSpacing.md + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rotulo,
                    style: AppTextStyles.bodyBold.copyWith(
                      color: destrutiva ? corErro : (isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    descricao,
                    style: AppTextStyles.caption.copyWith(color: isDark ? Colors.white38 : Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmarExclusao(BuildContext context, String oQue) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? corCardEscuro : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text(
          'Apagar este $oQue?',
          style: AppTextStyles.heading3.copyWith(color: isDark ? Colors.white : Colors.black87),
        ),
        content: Text(
          '"${imovel.titulo}" sai do mapa e da lista pra todo mundo. Não dá pra desfazer.',
          style: AppTextStyles.body.copyWith(color: isDark ? Colors.white70 : Colors.black87),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancelar', style: TextStyle(color: isDark ? Colors.white60 : Colors.black54)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'Apagar',
              style: TextStyle(color: corErro, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmou != true || !context.mounted) return;

    final mensageiro = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance.collection('imoveis').doc(imovel.id).delete();
      mensageiro.showSnackBar(SnackBar(content: Text('Anúncio apagado.'), backgroundColor: corSucesso));
    } catch (e) {
      mensageiro.showSnackBar(SnackBar(content: Text('Não deu pra apagar: $e'), backgroundColor: corErro));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isEvento = imovel.tipo == TipoListing.evento;

    return Pressionavel(
      onTap: () => _abrirAcoes(context),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? corSuperficieEscura : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: isDark ? Colors.white.withAlpha(8) : Colors.black.withAlpha(6)),
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: imovel.fotos.isEmpty ? gradientePrincipal : null,
                borderRadius: BorderRadius.circular(14),
              ),
              child: imovel.fotos.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(imovel.fotos.first, fit: BoxFit.cover),
                    )
                  : const Icon(Icons.home_rounded, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    imovel.titulo,
                    style: AppTextStyles.bodyBold.copyWith(color: isDark ? Colors.white : Colors.black87),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isEvento ? 'Evento' : (imovel.tipoImovel.isNotEmpty ? imovel.tipoImovel : 'Moradia'),
                    style: AppTextStyles.caption.copyWith(color: isDark ? Colors.white38 : Colors.grey),
                  ),
                ],
              ),
            ),
            if (!isEvento)
              Text(formatarPreco(imovel.preco), style: AppTextStyles.bodyBold.copyWith(color: corPrimaria)),
            // os tres pontinhos: e o que diz que o card abre acoes ao ser tocado
            const SizedBox(width: AppSpacing.xs),
            Icon(Icons.more_vert_rounded, size: 20, color: isDark ? Colors.white38 : Colors.grey),
          ],
        ),
      ),
    );
  }
}
