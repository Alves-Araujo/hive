import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';
import '../models/avaliacao.dart';
import '../models/imobiliaria.dart';
import '../models/imovel.dart';
import '../models/perfil_publico.dart';
import '../services/avaliacao_service.dart';
import '../services/imobiliaria_service.dart';
import '../services/usuario_service.dart';
import '../utils/chamada.dart';
import '../widgets/animated_gradient_button.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/card_imovel_vertical.dart';
import 'chat_detail_screen.dart';

// perfil publico de uma pessoa (aluno/corretor/proprietario) OU de uma
// imobiliaria -- exatamente um dos dois deve ser passado
class PerfilPublicoScreen extends StatefulWidget {
  final PerfilPublico? pessoa;
  final Imobiliaria? imobiliaria;

  const PerfilPublicoScreen({super.key, this.pessoa, this.imobiliaria})
      : assert(pessoa != null || imobiliaria != null, 'informe pessoa ou imobiliaria');

  @override
  State<PerfilPublicoScreen> createState() => _PerfilPublicoScreenState();
}

class _PerfilPublicoScreenState extends State<PerfilPublicoScreen> {
  int _notaSelecionada = 0;
  final _comentarioController = TextEditingController();
  bool _enviandoAvaliacao = false;

  bool get _ehImobiliaria => widget.imobiliaria != null;
  String get _id => widget.pessoa?.uid ?? widget.imobiliaria!.id;
  String get _colecaoPai => _ehImobiliaria ? 'imobiliarias' : 'usuarios';
  String get _nome => widget.pessoa?.nome ?? widget.imobiliaria!.nome;
  String get _fotoUrl => widget.pessoa?.fotoUrl ?? widget.imobiliaria!.fotoUrl;
  bool get _souEu => _id == FirebaseAuth.instance.currentUser?.uid;

  String get _rotulo {
    if (_ehImobiliaria) return 'Imobiliária';
    switch (widget.pessoa!.tipoUsuario) {
      case 'corretor':
        return widget.pessoa!.subtipoCorretor == 'empresa' ? 'Corretor (Empresa)' : 'Corretor Autônomo';
      case 'proprietario':
        return 'Proprietário';
      case 'estudante':
        return 'Estudante';
      default:
        return 'Usuário';
    }
  }

  bool get _mostraVitrine => _ehImobiliaria || widget.pessoa?.tipoUsuario == 'corretor';

  @override
  void dispose() {
    _comentarioController.dispose();
    super.dispose();
  }

  void _abrirPerfil(PerfilPublico pessoa) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => PerfilPublicoScreen(pessoa: pessoa)));
  }

  void _enviarMensagem() {
    final meuUid = FirebaseAuth.instance.currentUser?.uid;
    if (meuUid == null || widget.pessoa == null) return;
    final chatId = gerarIdParUsuarios('direto', meuUid, widget.pessoa!.uid);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(imovelId: chatId, imovelTitulo: '', donoUid: widget.pessoa!.uid),
      ),
    );
  }

  Future<void> _ligar() async {
    final meuUid = FirebaseAuth.instance.currentUser?.uid;
    if (meuUid == null || widget.pessoa == null || !mounted) return;
    final meuPerfil = await UsuarioService.instance.buscarPorUid(meuUid);
    if (!mounted) return;
    iniciarChamadaDeVoz(
      context,
      meuUid: meuUid,
      meuNome: (meuPerfil?.nome.isNotEmpty ?? false) ? meuPerfil!.nome : 'Usuário Hive',
      outroUid: widget.pessoa!.uid,
    );
  }

  Future<void> _enviarAvaliacao() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _notaSelecionada == 0) return;

    setState(() => _enviandoAvaliacao = true);
    try {
      final meuPerfil = await UsuarioService.instance.buscarPorUid(user.uid);
      await AvaliacaoService.instance.enviarAvaliacao(
        colecaoPai: _colecaoPai,
        avaliadoId: _id,
        avaliacao: Avaliacao(
          id: '',
          avaliadorUid: user.uid,
          avaliadorNome: (meuPerfil?.nome.isNotEmpty ?? false) ? meuPerfil!.nome : 'Usuário Hive',
          avaliadorFotoUrl: meuPerfil?.fotoUrl ?? '',
          nota: _notaSelecionada,
          comentario: _comentarioController.text.trim(),
        ),
      );
      if (mounted) {
        _comentarioController.clear();
        setState(() => _notaSelecionada = 0);
      }
    } finally {
      if (mounted) setState(() => _enviandoAvaliacao = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? corSuperficieEscura : superficieClara,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          Center(
            child: Column(
              children: [
                AvatarWidget(nome: _nome.isNotEmpty ? _nome : '?', fotoUrl: _fotoUrl, size: 96),
                const SizedBox(height: 12),
                Text(_nome, style: AppTextStyles.heading2.copyWith(color: isDark ? Colors.white : Colors.black87)),
                const SizedBox(height: 4),
                Text(_rotulo, style: AppTextStyles.captionBold.copyWith(color: corPrimaria)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          if (!_ehImobiliaria && !_souEu)
            Row(
              children: [
                Expanded(
                  child: AnimatedGradientButton(
                    label: 'Enviar Mensagem',
                    icon: Icons.chat_bubble_outline_rounded,
                    onTap: _enviarMensagem,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  height: 56,
                  width: 56,
                  decoration: BoxDecoration(gradient: gradientePrincipal, borderRadius: BorderRadius.circular(99.0)),
                  child: IconButton(
                    icon: const Icon(Icons.call_rounded, color: Colors.white),
                    onPressed: _ligar,
                  ),
                ),
              ],
            ),

          if (_ehImobiliaria) ...[
            const SizedBox(height: 24),
            _tituloSecao(isDark, 'Corretores vinculados'),
            const SizedBox(height: 12),
            _buildCorretoresVinculados(isDark),
          ],

          if (_mostraVitrine) ...[
            const SizedBox(height: 24),
            _tituloSecao(isDark, 'Anúncios'),
            const SizedBox(height: 12),
            _buildVitrine(isDark),
          ],

          const SizedBox(height: 24),
          _tituloSecao(isDark, 'Avaliações'),
          const SizedBox(height: 12),
          _buildAvaliacoes(isDark),
        ],
      ),
    );
  }

  Widget _tituloSecao(bool isDark, String texto) {
    return Text(texto, style: AppTextStyles.heading3.copyWith(color: isDark ? Colors.white : Colors.black87));
  }

  Widget _buildCorretoresVinculados(bool isDark) {
    return StreamBuilder<List<PerfilPublico>>(
      stream: ImobiliariaService.instance.streamCorretoresVinculados(widget.imobiliaria!.id),
      builder: (context, snapshot) {
        final corretores = snapshot.data ?? [];
        if (corretores.isEmpty) {
          return Text(
            'Nenhum corretor vinculado ainda.',
            style: AppTextStyles.caption.copyWith(color: isDark ? Colors.white38 : Colors.grey),
          );
        }
        return Column(
          children: corretores.map((corretor) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: isDark ? superficieEscura : superficieClara,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                leading: AvatarWidget(nome: corretor.nome, fotoUrl: corretor.fotoUrl, size: 40),
                title: Text(corretor.nome, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                trailing: Icon(Icons.chevron_right_rounded, color: isDark ? Colors.white38 : Colors.grey),
                onTap: () => _abrirPerfil(corretor),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildVitrine(bool isDark) {
    if (!_ehImobiliaria) {
      return _buildGradeDeImoveis(
        FirebaseFirestore.instance.collection('imoveis').where('donoUid', isEqualTo: widget.pessoa!.uid).snapshots(),
        isDark,
      );
    }

    // imobiliaria: pega os uids dos corretores confirmados primeiro, depois
    // busca os imoveis deles
    return StreamBuilder<List<PerfilPublico>>(
      stream: ImobiliariaService.instance.streamCorretoresVinculados(widget.imobiliaria!.id),
      builder: (context, snapshot) {
        final uids = (snapshot.data ?? []).map((p) => p.uid).toList();
        if (uids.isEmpty) {
          return Text(
            'Nenhum anúncio ainda.',
            style: AppTextStyles.caption.copyWith(color: isDark ? Colors.white38 : Colors.grey),
          );
        }
        return _buildGradeDeImoveis(
          FirebaseFirestore.instance.collection('imoveis').where('donoUid', whereIn: uids.take(30).toList()).snapshots(),
          isDark,
        );
      },
    );
  }

  Widget _buildGradeDeImoveis(Stream<QuerySnapshot> stream, bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: corPrimaria));
        }
        final imoveis = snapshot.data?.docs
                .map((doc) => Imovel.fromMap(doc.data() as Map<String, dynamic>, doc.id))
                .toList() ??
            [];
        if (imoveis.isEmpty) {
          return Text(
            'Nenhum anúncio ainda.',
            style: AppTextStyles.caption.copyWith(color: isDark ? Colors.white38 : Colors.grey),
          );
        }
        return Column(
          children: imoveis.map((imovel) => CardImovelVertical(imovel: imovel, isDark: isDark)).toList(),
        );
      },
    );
  }

  Widget _buildAvaliacoes(bool isDark) {
    return StreamBuilder<List<Avaliacao>>(
      stream: AvaliacaoService.instance.streamAvaliacoes(_colecaoPai, _id),
      builder: (context, snapshot) {
        final avaliacoes = snapshot.data ?? [];
        final media = avaliacoes.isEmpty ? 0.0 : avaliacoes.map((a) => a.nota).reduce((a, b) => a + b) / avaliacoes.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (avaliacoes.isNotEmpty)
              Row(
                children: [
                  const Icon(Icons.star_rounded, color: corAtencao, size: 20),
                  const SizedBox(width: 4),
                  Text(
                    '${media.toStringAsFixed(1)} · ${avaliacoes.length} avaliação(ões)',
                    style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            const SizedBox(height: 12),

            if (!_souEu) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? superficieEscura : superficieClara,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: List.generate(5, (i) {
                        final preenchida = i < _notaSelecionada;
                        return IconButton(
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            preenchida ? Icons.star_rounded : Icons.star_border_rounded,
                            color: corAtencao,
                          ),
                          onPressed: () => setState(() => _notaSelecionada = i + 1),
                        );
                      }),
                    ),
                    TextField(
                      controller: _comentarioController,
                      maxLines: 2,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                      decoration: InputDecoration(
                        hintText: 'Escreva um comentário...',
                        hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
                        border: InputBorder.none,
                      ),
                    ),
                    const SizedBox(height: 8),
                    AnimatedGradientButton(
                      label: 'Enviar avaliação',
                      height: 44,
                      isLoading: _enviandoAvaliacao,
                      onTap: _notaSelecionada == 0 ? null : _enviarAvaliacao,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            if (avaliacoes.isEmpty)
              Text(
                'Ainda não tem avaliações.',
                style: AppTextStyles.caption.copyWith(color: isDark ? Colors.white38 : Colors.grey),
              )
            else
              ...avaliacoes.map((avaliacao) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? superficieEscura : superficieClara,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            AvatarWidget(nome: avaliacao.avaliadorNome, fotoUrl: avaliacao.avaliadorFotoUrl, size: 28),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                avaliacao.avaliadorNome,
                                style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w600),
                              ),
                            ),
                            Row(
                              children: List.generate(
                                5,
                                (i) => Icon(
                                  i < avaliacao.nota ? Icons.star_rounded : Icons.star_border_rounded,
                                  color: corAtencao,
                                  size: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (avaliacao.comentario.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            avaliacao.comentario,
                            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                          ),
                        ],
                      ],
                    ),
                  )),
          ],
        );
      },
    );
  }
}
