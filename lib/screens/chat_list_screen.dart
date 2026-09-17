import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/texto.dart';
import '../main.dart';
import '../models/imovel.dart';
import '../services/busca_global_service.dart';
import '../widgets/avatar_widget.dart';
import 'chat_detail_screen.dart';
import 'perfil_publico_screen.dart';

class TelaListaChats extends StatefulWidget {
  const TelaListaChats({super.key});

  @override
  State<TelaListaChats> createState() => _TelaListaChatsState();
}

class _TelaListaChatsState extends State<TelaListaChats> {
  final TextEditingController _buscaController = TextEditingController();
  final FocusNode _buscaFocusNode = FocusNode();
  Timer? _debounce;
  List<ResultadoBuscaGlobal> _resultados = [];
  bool _buscando = false;

  @override
  void initState() {
    super.initState();
    _buscaController.addListener(_aoDigitar);
    _buscaFocusNode.addListener(() => setState(() {}));
  }

  void _aoDigitar() {
    setState(() {}); // atualiza o botao de limpar e troca lista/resultados

    _debounce?.cancel();
    final termo = _buscaController.text.trim();
    if (termo.isEmpty) {
      setState(() => _resultados = []);
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() => _buscando = true);
      final resultados = await BuscaGlobalService.instance.buscar(termo);
      if (mounted) {
        setState(() {
          _resultados = resultados;
          _buscando = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _buscaController.dispose();
    _buscaFocusNode.dispose();
    super.dispose();
  }

  void _abrirResultado(ResultadoBuscaGlobal resultado) {
    _buscaFocusNode.unfocus();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PerfilPublicoScreen(pessoa: resultado.pessoa, imobiliaria: resultado.imobiliaria),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final double topPadding = MediaQuery.of(context).padding.top;
    final bool pesquisando = _buscaController.text.trim().isNotEmpty;

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
          child: Column(
            children: [
              const Row(
                children: [
                  Text('Caixa de Entrada', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _buscaController,
                focusNode: _buscaFocusNode,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  hintText: 'Buscar alunos, corretores, imobiliárias...',
                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                  prefixIcon: const Icon(Icons.search_rounded, color: corPrimaria),
                  suffixIcon: pesquisando
                      ? IconButton(
                          icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 20),
                          onPressed: () => _buscaController.clear(),
                        )
                      : null,
                  filled: true,
                  fillColor: isDark ? Colors.white.withAlpha(10) : Colors.grey.withAlpha(15),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: pesquisando ? _buildResultadosBusca(isDark) : _buildListaDeChats(isDark),
        ),
      ],
    );
  }

  Widget _buildResultadosBusca(bool isDark) {
    if (_buscando) {
      return const Center(child: CircularProgressIndicator(color: corPrimaria));
    }
    if (_resultados.isEmpty) {
      return Center(
        child: Text('Nenhum resultado encontrado.', style: TextStyle(color: isDark ? Colors.white38 : Colors.grey)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _resultados.length,
      separatorBuilder: (_, _) => Divider(height: 1, indent: 76, color: isDark ? Colors.white.withAlpha(10) : Colors.grey.withAlpha(20)),
      itemBuilder: (context, index) {
        final resultado = _resultados[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          leading: AvatarWidget(nome: resultado.nome, fotoUrl: resultado.fotoUrl, size: 48),
          title: Text(
            resultado.nome,
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: isDark ? Colors.white : Colors.black87),
          ),
          subtitle: Text(resultado.rotulo, style: TextStyle(fontSize: 13, color: isDark ? Colors.white38 : Colors.grey)),
          onTap: () => _abrirResultado(resultado),
        );
      },
    );
  }

  Widget _buildListaDeChats(bool isDark) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('imoveis').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: corPrimaria));
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat_bubble_outline, size: 56, color: isDark ? Colors.white24 : Colors.grey.shade300),
                const SizedBox(height: 12),
                Text('Nenhuma conversa encontrada.', style: TextStyle(color: isDark ? Colors.white38 : Colors.grey)),
              ],
            ),
          );
        }

        final imoveis = snapshot.data!.docs
            .map((doc) => Imovel.fromMap(doc.data() as Map<String, dynamic>, doc.id))
            .toList();

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: imoveis.length,
          separatorBuilder: (context, index) => Divider(
            height: 1,
            indent: 76,
            color: isDark ? Colors.white.withAlpha(10) : Colors.grey.withAlpha(20),
          ),
          itemBuilder: (context, index) {
            final imovel = imoveis[index];
            return _ItemConversaStream(imovel: imovel, isDark: isDark);
          },
        );
      },
    );
  }
}

class _ItemConversaStream extends StatelessWidget {
  final Imovel imovel;
  final bool isDark;

  const _ItemConversaStream({required this.imovel, required this.isDark});

  @override
  Widget build(BuildContext context) {
    // escuta a ultima mensagem da subcolecao em tempo real
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .doc(imovel.id)
          .collection('mensagens')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        String ultimaMensagem = 'Toque para iniciar a conversa.';
        String horario = '';
        bool temMensagem = false;

        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          final doc = snapshot.data!.docs.first;
          final data = doc.data() as Map<String, dynamic>;
          ultimaMensagem = normalizarTracosOuVazio(data['texto']);
          temMensagem = true;

          if (data['timestamp'] != null) {
            final dt = (data['timestamp'] as Timestamp).toDate();
            horario = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
          }
        }

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          leading: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              image: imovel.fotos.isNotEmpty
                  ? DecorationImage(image: NetworkImage(imovel.fotos.first), fit: BoxFit.cover)
                  : null,
              gradient: imovel.fotos.isEmpty
                  ? const LinearGradient(colors: [corPrimaria, corPrimaria2], begin: Alignment.topLeft, end: Alignment.bottomRight)
                  : null,
            ),
            child: imovel.fotos.isEmpty
                ? const Icon(Icons.home_rounded, color: Colors.white, size: 22)
                : null,
          ),
          title: Text(
            imovel.titulo,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            ultimaMensagem,
            style: TextStyle(
              fontSize: 13,
              color: temMensagem ? (isDark ? Colors.white70 : Colors.black87) : (isDark ? Colors.white38 : Colors.grey),
              fontWeight: temMensagem ? FontWeight.w500 : FontWeight.normal,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (horario.isNotEmpty)
                Text(
                  horario,
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.grey),
                ),
            ],
          ),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatDetailScreen(
                  imovelTitulo: imovel.titulo,
                  imovelId: imovel.id,
                  donoUid: imovel.donoUid,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
