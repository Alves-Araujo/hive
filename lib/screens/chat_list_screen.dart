import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';
import '../models/chat.dart';
import '../models/perfil_publico.dart';
import '../services/busca_global_service.dart';
import '../services/chat_service.dart';
import '../services/perfil_publico_service.dart';
import '../utils/tempo.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/cabecalho_tela.dart';
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

  // nome e foto de quem esta do outro lado de cada conversa. Fica em cache
  // porque a lista se redesenha a cada mensagem nova, e sem isso cada
  // redesenho refaria uma leitura no firestore por conversa
  final Map<String, PerfilPublico> _contatos = {};
  final Set<String> _buscandoContato = {};

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
    final bool pesquisando = _buscaController.text.trim().isNotEmpty;

    return Column(
      children: [
        CabecalhoTela(
          titulo: 'Caixa de Entrada',
          rodape: CampoBuscaPadrao(
            controller: _buscaController,
            focusNode: _buscaFocusNode,
            dica: 'Buscar alunos, corretores, imobiliárias...',
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

  // So as MINHAS conversas. Antes esta lista era a colecao "imoveis" inteira,
  // com um stream da ultima mensagem de cada anuncio -- ou seja, todo usuario
  // via a previa da conversa de todo mundo e entrava em qualquer uma delas
  Widget _buildListaDeChats(bool isDark) {
    final meuUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (meuUid.isEmpty) return _vazio(isDark, 'Entre na sua conta para ver suas conversas.');

    return StreamBuilder<List<Chat>>(
      stream: ChatService.instance.conversasDe(meuUid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: corPrimaria));
        }

        final conversas = snapshot.data ?? const <Chat>[];
        if (conversas.isEmpty) {
          return _vazio(isDark, 'Nenhuma conversa ainda.\nFale com um anunciante para começar.');
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: conversas.length,
          separatorBuilder: (context, index) => Divider(
            height: 1,
            indent: 76,
            color: isDark ? Colors.white.withAlpha(10) : Colors.grey.withAlpha(20),
          ),
          itemBuilder: (context, index) {
            final chat = conversas[index];
            final contatoUid = chat.contatoUid(meuUid);
            _carregarContato(contatoUid);
            return _ItemConversa(
              chat: chat,
              contatoUid: contatoUid,
              contato: _contatos[contatoUid],
              isDark: isDark,
            );
          },
        );
      },
    );
  }

  // uma busca por pessoa, guardada pro resto da sessao da tela
  void _carregarContato(String uid) {
    if (uid.isEmpty || _contatos.containsKey(uid) || _buscandoContato.contains(uid)) return;
    _buscandoContato.add(uid);
    PerfilPublicoService.instance.buscarPorUid(uid).then((perfil) {
      if (perfil != null && mounted) setState(() => _contatos[uid] = perfil);
    });
  }

  Widget _vazio(bool isDark, String mensagem) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline, size: 56, color: isDark ? Colors.white24 : Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            mensagem,
            textAlign: TextAlign.center,
            style: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
          ),
        ],
      ),
    );
  }
}

// Um item da caixa de entrada. A previa e o horario saem do proprio
// documento da conversa: antes cada item abria um stream da subcolecao de
// mensagens, o que so funcionava porque a leitura era liberada pra todos
class _ItemConversa extends StatelessWidget {
  final Chat chat;
  final String contatoUid;

  // nulo enquanto o perfil ainda esta sendo buscado
  final PerfilPublico? contato;
  final bool isDark;

  const _ItemConversa({
    required this.chat,
    required this.contatoUid,
    required this.contato,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final temMensagem = chat.ultimaMensagem.isNotEmpty;
    // o nome e a foto sao do outro lado da conversa, nao do anuncio
    final nome = (contato?.nome.isNotEmpty ?? false) ? contato!.nome : 'Usuário Hive';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      leading: AvatarWidget(nome: nome, fotoUrl: contato?.fotoUrl, size: 48),
      title: Text(
        nome,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: isDark ? Colors.white : Colors.black87,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // qual anuncio gerou a conversa -- o chat direto nao tem
          if (chat.imovelTitulo.isNotEmpty)
            Text(
              'Ref: ${chat.imovelTitulo}',
              style: const TextStyle(fontSize: 11, color: corPrimaria),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          Text(
            temMensagem ? chat.ultimaMensagem : 'Toque para abrir a conversa.',
            style: TextStyle(
              fontSize: 13,
              color: temMensagem
                  ? (isDark ? Colors.white70 : Colors.black87)
                  : (isDark ? Colors.white38 : Colors.grey),
              fontWeight: temMensagem ? FontWeight.w500 : FontWeight.normal,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      trailing: Text(
        formatarTempoRelativo(chat.atualizadoEm),
        style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.grey),
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatDetailScreen(
              chatId: chat.id,
              contatoUid: contatoUid,
              imovelId: chat.imovelId,
              imovelTitulo: chat.imovelTitulo,
            ),
          ),
        );
      },
    );
  }
}
