import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart';
import '../models/imovel.dart';
import '../models/usuario.dart';
import '../utils/moeda.dart';

// dashboard so pra proprietarios/corretores -- lista os proprios imoveis
// cadastrados, atualizando ao vivo
class PainelScreen extends StatelessWidget {
  final Usuario perfil;
  const PainelScreen({super.key, required this.perfil});

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final double topPadding = MediaQuery.of(context).padding.top;

    return Column(
      children: [
        Container(
          padding: EdgeInsets.only(top: topPadding + 12, left: 20, right: 20, bottom: 16),
          decoration: BoxDecoration(
            color: isDark ? corCardEscuro : Colors.white,
            boxShadow: [
              BoxShadow(color: Colors.black.withAlpha(isDark ? 30 : 10), blurRadius: 10, offset: const Offset(0, 2)),
            ],
          ),
          child: Row(
            children: [
              Text(
                'Meus Imóveis',
                style: AppTextStyles.heading2.copyWith(color: isDark ? Colors.white : Colors.black87),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(gradient: gradientePrincipal, borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.home_rounded, color: Colors.white, size: 22),
              ),
            ],
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

  @override
  Widget build(BuildContext context) {
    final bool isEvento = imovel.tipo == TipoListing.evento;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? corCardEscuro : Colors.white,
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
            Text(
              formatarPreco(imovel.preco),
              style: AppTextStyles.bodyBold.copyWith(color: corPrimaria),
            ),
        ],
      ),
    );
  }
}
