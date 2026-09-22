import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../main.dart';
import '../models/chat.dart';
import '../models/perfil_publico.dart';
import '../services/busca_global_service.dart';
import '../services/chat_service.dart';
import '../services/notificacao_service.dart';
import '../services/perfil_publico_service.dart';
import '../utils/tempo.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/cabecalho_tela.dart';
import '../widgets/papel_parede_chat.dart';
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

  // O stream fica AQUI, e nao no build. Criado no build, cada setState (uma
  // tecla na busca, um perfil que chegou) devolvia um stream novo pro
  // StreamBuilder: ele cancelava a escuta e recomeçava do zero, voltando a
  // "waiting" -- a lista piscava e mensagem nova so aparecia depois que a
  // leitura refeita voltasse do servidor. Assinando uma vez, o listener fica
  // vivo e as conversas chegam sozinhas
  Stream<List<Chat>>? _conversas;
  String _uidDoStream = '';

  @override
  void initState() {
    super.initState();
    _buscaController.addListener(_aoDigitar);
    _buscaFocusNode.addListener(() => setState(() {}));
  }

  // troca de conta reassina; o mesmo uid reaproveita a escuta que ja esta de pe
  Stream<List<Chat>> _streamDeConversas(String meuUid) {
    if (_conversas == null || _uidDoStream != meuUid) {
      _uidDoStream = meuUid;
      _conversas = ChatService.instance.conversasDe(meuUid).map((lista) {
        // toda vez que a caixa de entrada atualiza, aproveita pra apagar
        // aviso de mensagem de conversa que nao existe mais aqui -- senao
        // ele nunca seria lido e a bolinha da aba Chat ficava presa
        NotificacaoService.instance.sincronizarChatsValidos(lista.map((c) => c.id));
        return lista;
      });
    }
    return _conversas!;
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
          subtitulo: 'Converse com anunciantes, corretores e colegas',
          acao: _buildSeloNaoLidas(),
          rodape: CampoBuscaPadrao(
            controller: _buscaController,
            focusNode: _buscaFocusNode,
            dica: 'Buscar alunos, corretores, imobiliárias...',
          ),
        ),
        // textura fina, nao a arte da conversa: aqui os cards cobrem quase
        // tudo e o fundo so aparece nas frestas entre eles
        Expanded(
          child: PapelDeParedeMiudo(
            child: pesquisando ? _buildResultadosBusca(isDark) : _buildListaDeChats(isDark),
          ),
        ),
      ],
    );
  }

  // total de mensagens esperando resposta, no canto do cabecalho. O numero ja
  // existia espalhado nos itens da lista; no topo ele responde "tenho algo
  // pra ver aqui?" sem precisar varrer a lista
  Widget _buildSeloNaoLidas() {
    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: NotificacaoService.instance.mensagensNaoLidasPorChat,
      builder: (context, porChat, _) {
        final total = porChat.values.fold<int>(0, (soma, n) => soma + n);
        if (total == 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
          decoration: BoxDecoration(
            gradient: gradientePrincipal,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: AppShadows.marca(forca: 0.6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.mark_chat_unread_rounded, color: Colors.white, size: 14),
              const SizedBox(width: 6),
              Text(
                '$total nova${total > 1 ? 's' : ''}',
                style: AppTextStyles.label.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
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
    return ListView.builder(
      padding: _recuoDaLista(context),
      itemCount: _resultados.length,
      itemBuilder: (context, index) {
        final resultado = _resultados[index];
        return _CartaoLista(
          isDark: isDark,
          destacado: false,
          onTap: () => _abrirResultado(resultado),
          child: Row(
            children: [
              AvatarWidget(nome: resultado.nome, fotoUrl: resultado.fotoUrl, size: 48),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resultado.nome,
                      style: AppTextStyles.bodyBold.copyWith(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      resultado.rotulo,
                      style: AppTextStyles.caption.copyWith(
                        color: isDark ? Colors.white38 : Colors.grey,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: isDark ? Colors.white24 : Colors.black26),
            ],
          ),
        );
      },
    );
  }

  // a barra de navegacao flutua POR CIMA da lista (extendBody no Scaffold do
  // app): sem esse recuo, a ultima conversa fica presa atras dela
  EdgeInsets _recuoDaLista(BuildContext context) => EdgeInsets.only(
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).padding.bottom + 96,
      );

  // So as MINHAS conversas. Antes esta lista era a colecao "imoveis" inteira,
  // com um stream da ultima mensagem de cada anuncio -- ou seja, todo usuario
  // via a previa da conversa de todo mundo e entrava em qualquer uma delas
  Widget _buildListaDeChats(bool isDark) {
    final meuUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (meuUid.isEmpty) return _vazio(isDark, 'Entre na sua conta para ver suas conversas.');

    return StreamBuilder<List<Chat>>(
      stream: _streamDeConversas(meuUid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _vazio(isDark, 'Não deu pra carregar suas conversas agora.');
        }
        // so roda na primeira carga: depois que a lista chegou uma vez, ela
        // continua na tela enquanto o firestore manda as atualizacoes
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: corPrimaria));
        }

        final conversas = snapshot.data ?? const <Chat>[];
        if (conversas.isEmpty) {
          return _vazio(isDark, 'Nenhuma conversa ainda.\nFale com um anunciante para começar.');
        }

        return ListView.builder(
          padding: _recuoDaLista(context),
          itemCount: conversas.length,
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
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // o icone chapado no meio do nada era metade do "sem
            // personalidade": aqui ele vira uma peca com a cor da marca
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark ? Colors.white.withAlpha(12) : Colors.white,
                border: Border.all(color: corPrimaria.withAlpha(isDark ? 50 : 30)),
                boxShadow: AppShadows.nivel1(isDark),
              ),
              child: Icon(
                Icons.forum_outlined,
                size: 42,
                color: corPrimaria.withAlpha(isDark ? 200 : 160),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              mensagem,
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// a moldura de um item de lista desta tela -- o card com sombra que
// substituiu o ListTile sobre fundo chapado. Fica em um lugar so pra busca e
// conversas nao voltarem a divergir em padding, raio e sombra
class _CartaoLista extends StatelessWidget {
  final Widget child;
  final bool isDark;

  // conversa com mensagem nao lida: ganha a borda e o fundo tingidos
  final bool destacado;
  final VoidCallback onTap;

  const _CartaoLista({
    required this.child,
    required this.isDark,
    required this.destacado,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs + 1),
      // a cor e a sombra ficam no DecoratedBox e o Material vai transparente
      // por cima: e o que deixa o toque pintar a ondinha SOBRE o card, sem
      // que o ClipRRect do Material coma a sombra
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: destacado
              ? (isDark
                  ? Color.alphaBlend(corPrimaria.withAlpha(36), corCardEscuro)
                  : Color.alphaBlend(corPrimaria.withAlpha(12), Colors.white))
              : (isDark ? corCardEscuro : Colors.white),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: destacado
                ? corPrimaria.withAlpha(isDark ? 110 : 60)
                : (isDark ? Colors.white.withAlpha(16) : Colors.black.withAlpha(12)),
          ),
          boxShadow: AppShadows.nivel1(isDark),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
              child: child,
            ),
          ),
        ),
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

    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: NotificacaoService.instance.mensagensNaoLidasPorChat,
      builder: (context, porChat, _) {
        final naoLidas = porChat[chat.id] ?? 0;

        return _CartaoLista(
          isDark: isDark,
          destacado: naoLidas > 0,
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // anel em volta do avatar quando ha mensagem esperando: da pra
              // achar a conversa nova correndo o olho pela coluna da esquerda,
              // sem ler nome nenhum
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: naoLidas > 0 ? gradientePrincipal : null,
                ),
                child: AvatarWidget(nome: nome, fotoUrl: contato?.fotoUrl, size: 48),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            nome,
                            style: AppTextStyles.bodyBold.copyWith(
                              color: isDark ? Colors.white : Colors.black87,
                              fontWeight: naoLidas > 0 ? FontWeight.w800 : FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          // conversa velha, sem horario gravado, nao mente
                          // "agora" -- so fica sem etiqueta, que e onde ela
                          // esta na ordem tambem (no fim)
                          chat.atualizadoEm == null && !chat.pendente
                              ? ''
                              : formatarTempoRelativo(chat.atualizadoEm),
                          style: AppTextStyles.label.copyWith(
                            color: naoLidas > 0 ? corPrimaria : (isDark ? Colors.white38 : Colors.grey),
                            fontWeight: naoLidas > 0 ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    // qual anuncio gerou a conversa -- o chat direto nao tem.
                    // Virou pilula: em texto solto ele competia com a previa
                    // da mensagem, que e a informacao que importa na lista
                    if (chat.imovelTitulo.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                        decoration: BoxDecoration(
                          color: corPrimaria.withAlpha(isDark ? 46 : 18),
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.home_work_outlined,
                              size: 11,
                              color: isDark ? corDestaque : corPrimaria,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                chat.imovelTitulo,
                                style: AppTextStyles.label.copyWith(
                                  color: isDark ? corDestaque : corPrimaria,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        if (_iconeDaPrevia != null) ...[
                          Icon(
                            _iconeDaPrevia,
                            size: 14,
                            color: naoLidas > 0
                                ? corPrimaria
                                : (isDark ? Colors.white54 : Colors.black45),
                          ),
                          const SizedBox(width: 4),
                        ],
                        Expanded(
                          child: Text(
                            temMensagem ? chat.ultimaMensagem : 'Toque para abrir a conversa.',
                            style: AppTextStyles.caption.copyWith(
                              color: naoLidas > 0
                                  ? (isDark ? Colors.white : Colors.black87)
                                  : temMensagem
                                      ? (isDark ? Colors.white70 : Colors.black54)
                                      : (isDark ? Colors.white38 : Colors.grey),
                              fontWeight: naoLidas > 0 ? FontWeight.w700 : FontWeight.w400,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (naoLidas > 0) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            constraints: const BoxConstraints(minWidth: 20),
                            decoration: BoxDecoration(
                              gradient: gradientePrincipal,
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                              boxShadow: AppShadows.marca(forca: 0.5),
                            ),
                            child: Text(
                              naoLidas > 9 ? '9+' : '$naoLidas',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.label.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Foto e audio nao tem previa de texto pra mostrar: o que fica gravado no
  // documento e a frase que _enviarDocumentoMensagem monta. Casar com ela aqui
  // e o que permite trocar "Enviou uma foto" por um icone de camera, como em
  // qualquer mensageiro. Se aquelas frases mudarem la, mudam aqui junto
  IconData? get _iconeDaPrevia {
    if (chat.ultimaMensagem == 'Enviou uma foto') return Icons.photo_camera_rounded;
    if (chat.ultimaMensagem == 'Enviou um áudio') return Icons.mic_rounded;
    return null;
  }
}
