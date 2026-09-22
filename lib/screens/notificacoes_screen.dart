import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart';
import '../models/imovel.dart';
import '../models/notificacao.dart';
import '../services/imobiliaria_service.dart';
import '../services/notificacao_service.dart';
import '../services/perfil_publico_service.dart';
import '../utils/tempo.dart';
import 'chat_detail_screen.dart';
import 'detalhes_imovel_screen.dart';
import 'perfil_publico_screen.dart';

// icone e cor de cada tipo -- evento usa o roxo do pin de evento, igual o
// resto do app (ver gradienteEvento no main.dart)
IconData iconeNotificacao(TipoNotificacao tipo) {
  switch (tipo) {
    case TipoNotificacao.novaMoradia:
      return Icons.home_rounded;
    case TipoNotificacao.novoEvento:
      return Icons.celebration_rounded;
    case TipoNotificacao.novaImobiliaria:
      return Icons.business_rounded;
    case TipoNotificacao.novaMensagem:
      return Icons.chat_bubble_rounded;
    case TipoNotificacao.novaAvaliacao:
      return Icons.star_rounded;
  }
}

Gradient _gradienteNotificacao(TipoNotificacao tipo) {
  switch (tipo) {
    case TipoNotificacao.novoEvento:
      return gradienteEvento;
    case TipoNotificacao.novaAvaliacao:
      return const LinearGradient(
        colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    default:
      return gradientePrincipal;
  }
}

// leva pra tela do que a notificacao fala. O anuncio/imobiliaria e buscado
// na hora porque pode ter sido apagado depois do aviso
Future<void> abrirNotificacao(BuildContext context, Notificacao n) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  void indisponivel(String msg) => messenger.showSnackBar(SnackBar(content: Text(msg)));

  switch (n.tipo) {
    case TipoNotificacao.novaMoradia:
    case TipoNotificacao.novoEvento:
      final doc = await FirebaseFirestore.instance.collection('imoveis').doc(n.alvoId).get();
      if (!doc.exists) return indisponivel('Esse anúncio não está mais disponível.');
      navigator.push(MaterialPageRoute(
        builder: (_) => DetalhesImovelScreen(imovel: Imovel.fromMap(doc.data()!, doc.id)),
      ));
    case TipoNotificacao.novaImobiliaria:
      final imobiliaria = await ImobiliariaService.instance.buscarPorId(n.alvoId);
      if (imobiliaria == null) return indisponivel('Essa imobiliária não está mais disponível.');
      navigator.push(MaterialPageRoute(builder: (_) => PerfilPublicoScreen(imobiliaria: imobiliaria)));
    case TipoNotificacao.novaMensagem:
      navigator.push(MaterialPageRoute(
        // alvoId e o chatId, e contatoUid e quem mandou a mensagem
        builder: (_) => ChatDetailScreen(
          chatId: n.alvoId,
          contatoUid: n.contatoUid,
          imovelTitulo: n.imovelTitulo,
        ),
      ));
    case TipoNotificacao.novaAvaliacao:
      final perfil = await PerfilPublicoService.instance.buscarPorUid(n.alvoId);
      if (perfil == null) return;
      navigator.push(MaterialPageRoute(builder: (_) => PerfilPublicoScreen(pessoa: perfil)));
  }
}

class NotificacoesScreen extends StatefulWidget {
  const NotificacoesScreen({super.key});

  @override
  State<NotificacoesScreen> createState() => _NotificacoesScreenState();
}

class _NotificacoesScreenState extends State<NotificacoesScreen> {
  // as nao lidas sao congeladas na abertura: abrir a tela ja marca tudo
  // como lido, mas o destaque continua ate a pessoa sair, senao ela nem
  // veria quais eram as novas
  late final Set<String> _novas;

  @override
  void initState() {
    super.initState();
    final servico = NotificacaoService.instance;
    _novas = servico.notificacoes.value.where(servico.naoLida).map((n) => n.id).toSet();
    servico.marcarTodasComoLidas();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? corFundoEscuro : corFundoClaro,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
        title: Text(
          'Notificações',
          style: AppTextStyles.heading3.copyWith(color: isDark ? Colors.white : Colors.black87),
        ),
        centerTitle: true,
      ),
      body: ValueListenableBuilder<List<Notificacao>>(
        valueListenable: NotificacaoService.instance.notificacoes,
        builder: (context, notificacoes, _) {
          if (notificacoes.isEmpty) return _buildVazio(isDark);

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xxl),
            physics: const BouncingScrollPhysics(),
            itemCount: notificacoes.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final n = notificacoes[index];
              return _ItemNotificacao(
                notificacao: n,
                nova: _novas.contains(n.id),
                isDark: isDark,
                onTap: () => abrirNotificacao(context, n),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildVazio(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
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
                Icons.notifications_none_rounded,
                size: 48,
                color: isDark ? Colors.white.withAlpha(51) : Colors.grey.shade300,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Nenhuma notificação por enquanto.',
              style: AppTextStyles.bodyBold.copyWith(color: isDark ? Colors.white70 : Colors.black87),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Avisamos aqui quando aparecer moradia, evento ou imobiliária nova, e quando alguém falar com você.',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(color: isDark ? Colors.white38 : Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemNotificacao extends StatelessWidget {
  final Notificacao notificacao;
  final bool nova;
  final bool isDark;
  final VoidCallback onTap;

  const _ItemNotificacao({
    required this.notificacao,
    required this.nova,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final corFundo = isDark ? corCardEscuro : Colors.white;

    return Material(
      color: nova ? Color.alphaBlend(corPrimaria.withAlpha(isDark ? 40 : 14), corFundo) : corFundo,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: _gradienteNotificacao(notificacao.tipo),
                  shape: BoxShape.circle,
                ),
                child: Icon(iconeNotificacao(notificacao.tipo), color: Colors.white, size: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notificacao.titulo,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.captionBold.copyWith(
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (notificacao.corpo.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        notificacao.corpo,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(color: isDark ? Colors.white60 : Colors.black54),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      formatarTempoRelativo(notificacao.criadoEm),
                      style: AppTextStyles.label.copyWith(color: isDark ? Colors.white38 : Colors.grey),
                    ),
                  ],
                ),
              ),
              if (nova)
                Container(
                  margin: const EdgeInsets.only(left: AppSpacing.sm, top: 6),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(color: corPrimaria2, shape: BoxShape.circle),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
