import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import '../utils/tempo.dart';
import '../utils/texto.dart';
import '../main.dart';
import '../models/chat.dart';
import '../models/perfil_publico.dart';
import '../models/usuario.dart';
import '../services/chat_service.dart';
import '../services/imovel_service.dart';
import '../services/notificacao_service.dart';
import '../services/perfil_publico_service.dart';
import '../services/usuario_service.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/papel_parede_chat.dart';
import 'concluir_perfil_screen.dart';
import 'perfil_publico_screen.dart';

// Uma conversa e sempre entre duas pessoas: eu e o contato. O chatId ja vem
// pronto de quem abriu a tela (montado por gerarIdChat), porque os dois lados
// precisam chegar ao mesmo id sozinhos
class ChatDetailScreen extends StatefulWidget {
  final String chatId;

  // o outro lado da conversa: o dono do anuncio, quando o interessado abre;
  // o interessado, quando o dono responde pela caixa de entrada
  final String contatoUid;

  // vazios no chat direto (perfil -> perfil)
  final String imovelId;
  final String imovelTitulo;

  const ChatDetailScreen({
    super.key,
    required this.chatId,
    required this.contatoUid,
    this.imovelId = '',
    this.imovelTitulo = '',
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final TextEditingController _mensagemController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  Usuario? _meuPerfil;
  PerfilPublico? _contato;

  // foto e audio vao em base64 dentro da propria mensagem: o firebase storage
  // nao esta ativo no projeto e a chave do imgbb foi bloqueada. Documento do
  // firestore tem teto de 1MB: a 32kbps, 2 minutos de audio dao ~650KB ja em
  // base64; a foto sai reduzida pra 1280px, o que fica bem abaixo disso
  static const int _duracaoMaximaAudio = 120;
  static const int _tamanhoMaximoMidia = 900 * 1024;

  // bytes das fotos ja decodificados, pra nao refazer o base64 a cada rebuild
  final Map<String, Uint8List> _imagensCache = {};

  bool _gravandoAudio = false;
  bool _enviandoMidia = false;
  String? _audioTocandoId;
  int _segundosGravando = 0;
  Timer? _timerGravacao;

  // Nao e criado inline no build(): cada segundo de gravacao (que da setState
  // pra atualizar o cronometro) recriaria o stream, e o chat piscava voltando
  // pro loading. So troca de verdade quando _reabrirEscuta() manda
  late Stream<QuerySnapshot<Map<String, dynamic>>> _mensagensStream;

  // A regra das mensagens olha o documento pai da conversa (chats/{id}), e
  // conversa nova -- aberta pelo anuncio, antes de qualquer mensagem -- ainda
  // nao tem esse pai: o firestore NEGA a escuta, e escuta negada nao se
  // reconecta sozinha. Era dai que vinha "mandei e nao foi": a mensagem
  // chegava ao servidor, mas a tela tinha perdido a escuta antes mesmo da
  // primeira letra digitada, entao nada aparecia e a pessoa mandava de novo
  bool _escutaCaiu = false;
  Timer? _timerReabrirEscuta;

  @override
  void initState() {
    super.initState();
    _mensagensStream = ChatService.instance.mensagensRecentes(widget.chatId);
    NotificacaoService.instance.entrarNoChat(widget.chatId);
    _carregarMeuPerfil();
    _carregarContato();

    // reconstroi o botao de enviar/microfone conforme digita
    _mensagemController.addListener(() => setState(() {}));

    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _audioTocandoId = null);
    });
  }

  Future<void> _carregarMeuPerfil() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final perfil = await UsuarioService.instance.buscarPorUid(uid);
    if (perfil != null && mounted) setState(() => _meuPerfil = perfil);
  }

  // le da colecao publica, ja que "usuarios" so o proprio dono pode ler. Como
  // a conversa e entre duas pessoas, esse mesmo perfil serve pro cabecalho e
  // pro avatar de toda mensagem recebida
  Future<void> _carregarContato() async {
    if (widget.contatoUid.isEmpty) return;
    final perfil = await PerfilPublicoService.instance.buscarPorUid(widget.contatoUid);
    if (perfil != null && mounted) setState(() => _contato = perfil);
  }

  // abre de novo a escuta das mensagens. So faz sentido depois que o
  // documento pai passa a existir -- ate la o firestore nega toda tentativa
  void _reabrirEscuta() {
    _timerReabrirEscuta?.cancel();
    _timerReabrirEscuta = null;
    if (!mounted) return;
    setState(() {
      _escutaCaiu = false;
      _mensagensStream = ChatService.instance.mensagensRecentes(widget.chatId);
    });
  }

  // chamado de dentro do build, quando a escuta cai: agenda a proxima
  // tentativa em vez de reabrir na hora, porque trocar o stream no meio da
  // construcao do StreamBuilder seria mexer na arvore que esta sendo montada.
  //
  // A tentativa periodica cobre o caso em que quem abriu a conversa nao
  // escreve nada e o OUTRO lado manda a primeira mensagem: o pai nasce longe
  // daqui, e sem isso a tela ficaria parada no "Diga um oi" pra sempre
  void _agendarReaberturaDaEscuta() {
    _escutaCaiu = true;
    _timerReabrirEscuta ??= Timer(const Duration(seconds: 4), _reabrirEscuta);
  }

  Future<void> _enviarDocumentoMensagem(Map<String, dynamic> dados) async {
    final meuUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    // antes esses dois casos saiam calados, e a mensagem simplesmente sumia
    if (meuUid.isEmpty) {
      throw Exception('sua sessão expirou, entre de novo');
    }
    if (widget.contatoUid.isEmpty) {
      throw Exception('não deu pra identificar com quem é essa conversa');
    }

    final String previa = switch (dados['tipo']) {
      'imagem' => 'Enviou uma foto',
      'audio' => 'Enviou um áudio',
      _ => dados['texto'] as String? ?? '',
    };
    final resumo = previa.length > 120 ? '${previa.substring(0, 120)}...' : previa;

    await ChatService.instance.enviarMensagem(
      chatId: widget.chatId,
      dados: dados,
      meuUid: meuUid,
      contatoUid: widget.contatoUid,
      previa: resumo,
      imovelId: widget.imovelId,
      imovelTitulo: widget.imovelTitulo,
    );

    // o documento pai acabou de nascer com esta mensagem: a escuta que o
    // firestore tinha negado agora vale, e e ela que traz a conversa pra tela
    if (_escutaCaiu) _reabrirEscuta();

    // Conversa de anuncio: e esta mensagem que liga (interessado escrevendo)
    // ou desliga (dono respondendo) o prazo que tira do mapa anuncio
    // abandonado -- ver utils/inatividade.dart.
    //
    // O anuncio sai do chatId quando quem abriu a conversa nao o informou: e
    // o caso de quem chega pelo aviso de mensagem nova, que so tem o id da
    // conversa em maos.
    //
    // Sem await: o relogio e consequencia da mensagem, e a mensagem ja saiu.
    // O proprio servico engole a falha, entao nao ha erro solto pra tratar
    final String imovelDaConversa = widget.imovelId.isNotEmpty
        ? widget.imovelId
        : imovelIdDoChat(widget.chatId);
    if (imovelDaConversa.isNotEmpty) {
      unawaited(ImovelService.instance.registrarMensagem(
        imovelId: imovelDaConversa,
        remetenteUid: meuUid,
      ));
    }

    // o aviso vai sempre pro outro lado, e quem recebe abre a conversa comigo
    NotificacaoService.instance.avisarNovaMensagem(
      destinatarios: [widget.contatoUid],
      remetenteNome: (_meuPerfil?.nome.isNotEmpty ?? false) ? _meuPerfil!.nome : 'Usuário Hive',
      previa: resumo,
      chatId: widget.chatId,
      contatoUid: meuUid,
      imovelTitulo: widget.imovelTitulo,
    );
  }

  // O campo e limpo na hora (a mensagem tem que parecer que saiu), mas se o
  // envio falhar o texto VOLTA pro campo e o erro aparece. Antes ele era
  // limpo e pronto: falha nenhuma era mostrada, o que a pessoa escreveu se
  // perdia junto, e so restava digitar tudo de novo e tentar mais uma vez
  void _enviarMensagemTexto() async {
    final texto = _mensagemController.text.trim();
    if (texto.isEmpty) return;
    _mensagemController.clear();
    try {
      await _enviarDocumentoMensagem({'tipo': 'texto', 'texto': normalizarTracos(texto)});
    } catch (e) {
      if (!mounted) return;
      // devolve com o cursor no fim, pronto pra continuar de onde parou
      _mensagemController.value = TextEditingValue(
        text: texto,
        selection: TextSelection.collapsed(offset: texto.length),
      );
      _mostrarErro('Não deu pra enviar a mensagem: $e');
    }
  }

  Future<void> _escolherEEnviarFoto(ImageSource source) async {
    Navigator.pop(context); // fecha a folha de opcoes de anexo
    final XFile? imagem;
    try {
      imagem = await _picker.pickImage(source: source, maxWidth: 1280, maxHeight: 1280, imageQuality: 60);
    } catch (e) {
      _mostrarErro(source == ImageSource.camera
          ? 'Libere o acesso à câmera nas configurações do celular pra tirar foto.'
          : 'Não deu pra abrir a galeria: $e');
      return;
    }
    if (imagem == null) return;

    setState(() => _enviandoMidia = true);
    try {
      final base64 = base64Encode(await imagem.readAsBytes());
      if (base64.length > _tamanhoMaximoMidia) {
        throw Exception('foto grande demais');
      }
      await _enviarDocumentoMensagem({'tipo': 'imagem', 'imagemBase64': base64});
    } catch (e) {
      _mostrarErro('Erro ao enviar foto: $e');
    } finally {
      if (mounted) setState(() => _enviandoMidia = false);
    }
  }

  void _mostrarOpcoesDeAnexo() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? superficieEscura : superficieClara,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _opcaoAnexo(
                  isDark: isDark,
                  icone: Icons.photo_camera_rounded,
                  rotulo: 'Câmera',
                  onTap: () => _escolherEEnviarFoto(ImageSource.camera),
                ),
                _opcaoAnexo(
                  isDark: isDark,
                  icone: Icons.photo_library_rounded,
                  rotulo: 'Galeria',
                  onTap: () => _escolherEEnviarFoto(ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _opcaoAnexo({
    required bool isDark,
    required IconData icone,
    required String rotulo,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(gradient: gradientePrincipal, shape: BoxShape.circle),
            child: Icon(icone, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 8),
          Text(rotulo, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13)),
        ],
      ),
    );
  }

  void _mostrarErro(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), backgroundColor: corErro),
    );
  }

  Future<void> _alternarGravacaoAudio() async {
    if (_gravandoAudio) {
      await _pararEEnviarAudio();
    } else {
      await _comecarGravacao();
    }
  }

  Future<void> _comecarGravacao() async {
    if (!await _recorder.hasPermission()) {
      _mostrarErro('Libere o acesso ao microfone nas configurações do celular pra gravar áudio.');
      return;
    }
    try {
      final pasta = await getTemporaryDirectory();
      final caminho = '${pasta.path}/audio_${DateTime.now().microsecondsSinceEpoch}.m4a';
      // qualidade de voz, mono -- mantem o arquivo pequeno o bastante pro firestore
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 32000, sampleRate: 22050, numChannels: 1),
        path: caminho,
      );
    } catch (e) {
      _mostrarErro('Não deu pra começar a gravação: $e');
      return;
    }
    setState(() {
      _gravandoAudio = true;
      _segundosGravando = 0;
    });
    _timerGravacao = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _segundosGravando++);
      if (_segundosGravando >= _duracaoMaximaAudio) _pararEEnviarAudio();
    });
  }

  Future<void> _pararEEnviarAudio() async {
    _timerGravacao?.cancel();
    _timerGravacao = null;
    final caminho = await _recorder.stop();
    setState(() {
      _gravandoAudio = false;
      _enviandoMidia = true;
    });
    try {
      if (caminho == null) throw Exception('a gravação não gerou arquivo');
      final arquivo = File(caminho);
      final bytes = await arquivo.readAsBytes();
      arquivo.delete().ignore();
      if (bytes.isEmpty) return;
      final base64 = base64Encode(bytes);
      if (base64.length > _tamanhoMaximoMidia) {
        throw Exception('áudio grande demais, grave um mais curto');
      }
      await _enviarDocumentoMensagem({
        'tipo': 'audio',
        'audioBase64': base64,
        'duracao': _segundosGravando,
      });
    } catch (e) {
      _mostrarErro('Erro ao enviar áudio: $e');
    } finally {
      if (mounted) setState(() => _enviandoMidia = false);
    }
  }

  Future<void> _alternarReproducaoAudio(String mensagemId, Map<String, dynamic> msg) async {
    if (_audioTocandoId == mensagemId) {
      await _player.pause();
      setState(() => _audioTocandoId = null);
      return;
    }
    try {
      final base64 = msg['audioBase64'] as String?;
      if (base64 != null && base64.isNotEmpty) {
        // tocar direto de bytes nao funciona em todo aparelho, entao passa por
        // um arquivo temporario
        final pasta = await getTemporaryDirectory();
        final arquivo = File('${pasta.path}/chat_$mensagemId.m4a');
        if (!await arquivo.exists()) await arquivo.writeAsBytes(base64Decode(base64));
        await _player.play(DeviceFileSource(arquivo.path));
      } else {
        await _player.play(UrlSource(msg['midiaUrl'] as String));
      }
      setState(() => _audioTocandoId = mensagemId);
    } catch (e) {
      _mostrarErro('Não deu pra tocar o áudio: $e');
    }
  }

  String _formatarDuracao(int segundos) =>
      '${segundos ~/ 60}:${(segundos % 60).toString().padLeft(2, '0')}';

  void _abrirFotoAmpliada({Uint8List? bytes, String? url}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              maxScale: 4,
              child: bytes != null
                  ? Image.memory(bytes, fit: BoxFit.contain)
                  : Image.network(url!, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  void _abrirPerfilDoContato() {
    if (_contato == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PerfilPublicoScreen(pessoa: _contato)),
    );
  }

  Future<void> _abrirConcluirPerfil() async {
    if (_meuPerfil == null) return;
    final atualizado = await Navigator.push<Usuario>(
      context,
      MaterialPageRoute(builder: (_) => ConcluirPerfilScreen(perfil: _meuPerfil!)),
    );
    if (atualizado != null && mounted) {
      setState(() => _meuPerfil = atualizado);
    }
  }

  @override
  void dispose() {
    NotificacaoService.instance.sairDoChat(widget.chatId);
    _timerGravacao?.cancel();
    _timerReabrirEscuta?.cancel();
    _mensagemController.dispose();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final meuUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final double larguraMaxima = MediaQuery.of(context).size.width * 0.7;

    return Scaffold(
      backgroundColor: isDark ? corFundoEscuro : corFundoClaro,
      appBar: _buildCabecalho(isDark),
      body: PapelDeParedeConversa(
        child: Column(
          children: [
            if (widget.imovelTitulo.isNotEmpty) _buildFaixaImovel(isDark),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _mensagensStream,
                builder: (context, snapshot) {
                  // escuta negada: e o que acontece na conversa que ainda nao
                  // existe no servidor. Nao e erro pra mostrar -- a tela e a
                  // mesma de conversa vazia, e a escuta volta sozinha assim
                  // que a primeira mensagem criar o documento pai
                  if (snapshot.hasError) {
                    _agendarReaberturaDaEscuta();
                    return _buildConversaVazia(isDark);
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: corPrimaria));
                  }

                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return _buildConversaVazia(isDark);
                  }

                  final mensagens = snapshot.data!.docs;

                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    itemCount: mensagens.length,
                    itemBuilder: (context, index) {
                      final doc = mensagens[index];
                      final msg = doc.data();
                      // pelo uid, nao pelo e-mail: o e-mail da conta pode mudar,
                      // e as mensagens antigas ficariam do lado errado da tela
                      final bool isMinha = (msg['remetenteUid'] as String? ?? '') == meuUid;
                      final tipo = msg['tipo'] as String? ?? 'texto';
                      final DateTime? quando = (msg['timestamp'] as Timestamp?)?.toDate();

                      // A lista e invertida: o indice 0 fica EMBAIXO. Entao
                      // "a mensagem acima desta" e index + 1, e "a de baixo"
                      // e index - 1 -- e o que decide onde entra a faixa de
                      // dia e em qual mensagem do bloco vai o avatar
                      final anterior = index + 1 < mensagens.length ? mensagens[index + 1].data() : null;
                      final seguinte = index > 0 ? mensagens[index - 1].data() : null;

                      final bool abreDia = _abreNovoDia(quando, anterior);
                      // o avatar so na ULTIMA mensagem seguida do contato:
                      // repetido em todas, uma resposta de tres linhas virava
                      // uma coluna de carinhas identicas ao lado dos baloes
                      final bool fechaBloco =
                          seguinte == null || (seguinte['remetenteUid'] as String? ?? '') != (msg['remetenteUid'] as String? ?? '');

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (abreDia) _buildFaixaDia(quando, isDark),
                          Padding(
                            // mensagens do mesmo bloco ficam quase coladas;
                            // a troca de quem fala e que abre o respiro
                            padding: EdgeInsets.only(bottom: fechaBloco ? AppSpacing.md : 3),
                            child: Align(
                              alignment: isMinha ? Alignment.centerRight : Alignment.centerLeft,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (!isMinha) ...[
                                    // so o contato escreve do outro lado, entao
                                    // o perfil do cabecalho serve pra toda
                                    // mensagem recebida
                                    SizedBox(
                                      width: 28,
                                      child: fechaBloco
                                          ? AvatarWidget(
                                              nome: (_contato?.nome.isNotEmpty ?? false) ? _contato!.nome : '?',
                                              fotoUrl: _contato?.fotoUrl,
                                              size: 28,
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                  ],
                                  ConstrainedBox(
                                    constraints: BoxConstraints(maxWidth: larguraMaxima),
                                    child: _buildConteudoMensagem(
                                      doc.id,
                                      tipo,
                                      msg,
                                      isMinha,
                                      isDark,
                                      quando,
                                      fechaBloco,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            _buildAreaEnvio(isDark),
          ],
        ),
      ),
    );
  }

  // mesma receita de gradiente do CabecalhoTela das abas, pra conversa e
  // resto do app lerem como a mesma interface
  PreferredSizeWidget _buildCabecalho(bool isDark) {
    final String nome = (_contato?.nome.isNotEmpty ?? false) ? _contato!.nome : 'Proprietário';

    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
      titleSpacing: 0,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0, 0.55, 1],
            colors: isDark
                ? [
                    Color.alphaBlend(Colors.white.withAlpha(15), superficieEscura),
                    superficieEscura,
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
      ),
      title: InkWell(
        onTap: _contato == null ? null : _abrirPerfilDoContato,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs, horizontal: AppSpacing.xs),
          child: Row(
            children: [
              AvatarWidget(
                nome: (_contato?.nome.isNotEmpty ?? false) ? _contato!.nome : '?',
                fotoUrl: _contato?.fotoUrl,
                size: 38,
                showOnlineIndicator: _contatoOnline,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nome,
                      style: AppTextStyles.bodyBold.copyWith(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // presenca, como em qualquer mensageiro -- o "Ref: anuncio"
                    // saiu daqui pra faixa logo abaixo, onde cabe inteiro
                    if (_contato != null)
                      Text(
                        _contatoOnline ? 'Online agora' : formatarUltimoAcesso(_contato!.ultimoAcesso),
                        style: AppTextStyles.label.copyWith(
                          color: _contatoOnline
                              ? corSucesso
                              : (isDark ? Colors.white38 : Colors.black45),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              if (_contato != null)
                Icon(
                  Icons.chevron_right_rounded,
                  color: isDark ? Colors.white30 : Colors.black26,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }

  // "online" aqui e simplesmente acesso nos ultimos 5 minutos: o app nao tem
  // canal de presenca de verdade, e inventar um so pra bolinha verde nao
  // pagaria o custo de manter
  bool get _contatoOnline {
    final acesso = _contato?.ultimoAcesso;
    if (acesso == null) return false;
    return DateTime.now().difference(acesso).inMinutes < 5;
  }

  // de qual anuncio e essa conversa. Vale uma faixa propria: quem anuncia
  // costuma ter varias conversas abertas ao mesmo tempo e precisa saber de
  // cara sobre qual imovel esta falando
  Widget _buildFaixaImovel(bool isDark) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isDark ? corPrimaria.withAlpha(38) : corPrimaria.withAlpha(16),
        border: Border(
          bottom: BorderSide(color: corPrimaria.withAlpha(isDark ? 60 : 30)),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.home_work_outlined, size: 16, color: isDark ? corDestaque : corPrimaria),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              widget.imovelTitulo,
              style: AppTextStyles.label.copyWith(
                color: isDark ? corDestaque : corPrimaria,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // true quando esta mensagem e a primeira do dia dela -- `anterior` e a de
  // cima na tela, que numa lista invertida e a mais VELHA
  bool _abreNovoDia(DateTime? quando, Map<String, dynamic>? anterior) {
    if (quando == null) return false;
    if (anterior == null) return true;
    final antes = (anterior['timestamp'] as Timestamp?)?.toDate();
    if (antes == null) return false;
    return !mesmoDia(antes, quando);
  }

  Widget _buildFaixaDia(DateTime? quando, bool isDark) {
    if (quando == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 5),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withAlpha(20) : Colors.white.withAlpha(220),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: isDark ? Colors.white.withAlpha(20) : corPrimaria.withAlpha(24),
            ),
            boxShadow: AppShadows.nivel1(isDark),
          ),
          child: Text(
            rotuloDiaConversa(quando),
            style: AppTextStyles.label.copyWith(
              color: isDark ? Colors.white70 : corPrimaria,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConversaVazia(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                gradient: gradientePrincipal,
                shape: BoxShape.circle,
                boxShadow: AppShadows.marca(),
              ),
              child: const Icon(Icons.waving_hand_rounded, color: Colors.white, size: 34),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Diga um oi',
              style: AppTextStyles.heading3.copyWith(
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              widget.imovelTitulo.isNotEmpty
                  ? 'Pergunte sobre o imóvel, combine uma visita ou tire suas dúvidas.'
                  : 'Comece a conversa mandando a primeira mensagem.',
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(
                color: isDark ? Colors.white38 : Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConteudoMensagem(
    String mensagemId,
    String tipo,
    Map<String, dynamic> msg,
    bool isMinha,
    bool isDark,
    DateTime? quando,
    bool fechaBloco,
  ) {
    // minha mensagem leva o gradiente da marca; a recebida, a superficie do
    // app. A quina "mordida" de 5px do lado de quem enviou e o que da a
    // leitura de origem sem precisar de seta nem rotulo -- e ela so aparece
    // na ULTIMA mensagem seguida de cada um, como em qualquer mensageiro:
    // repetida em todas, o bloco vira uma escada de quinas
    final Radius quina = Radius.circular(fechaBloco ? 5 : AppRadius.md);
    final decoracaoBalao = BoxDecoration(
      gradient: isMinha ? gradientePrincipal : null,
      color: isMinha
          ? null
          : (isDark ? const Color(0xFF1F303F) : Colors.white),
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(AppRadius.md),
        topRight: const Radius.circular(AppRadius.md),
        bottomLeft: isMinha ? const Radius.circular(AppRadius.md) : quina,
        bottomRight: isMinha ? quina : const Radius.circular(AppRadius.md),
      ),
      border: isMinha
          ? null
          : Border.all(color: isDark ? Colors.white.withAlpha(14) : Colors.black.withAlpha(10)),
      // sobre papel de parede a sombra deixa de ser enfeite: e ela que
      // descola o balao do padrao e mantem o texto facil de ler
      boxShadow: isMinha ? AppShadows.marca(forca: 0.5) : AppShadows.nivel1(isDark),
    );

    if (tipo == 'imagem') {
      final base64 = msg['imagemBase64'] as String? ?? '';
      final url = msg['midiaUrl'] as String? ?? '';
      Uint8List? bytes;
      final Widget foto;
      if (base64.isNotEmpty) {
        bytes = _imagensCache.putIfAbsent(mensagemId, () => base64Decode(base64));
        foto = Image.memory(bytes, width: 220, fit: BoxFit.cover, gaplessPlayback: true);
      } else if (url.isNotEmpty) {
        foto = Image.network(url, width: 220, fit: BoxFit.cover);
      } else {
        foto = const SizedBox(width: 160, height: 160);
      }
      return Container(
        decoration: decoracaoBalao,
        padding: const EdgeInsets.all(4),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: (bytes == null && url.isEmpty)
                  ? foto
                  : GestureDetector(
                      onTap: () => _abrirFotoAmpliada(bytes: bytes, url: url.isEmpty ? null : url),
                      child: foto,
                    ),
            ),
            // sobre a foto a hora precisa de fundo proprio: em imagem clara
            // ela sumia, em escura ficava dura
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(110),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: _buildRodapeHora(quando, isMinha, isDark, sobreMidia: true),
              ),
            ),
          ],
        ),
      );
    }

    if (tipo == 'audio') {
      final temAudio = (msg['audioBase64'] as String? ?? '').isNotEmpty ||
          (msg['midiaUrl'] as String? ?? '').isNotEmpty;
      final duracao = msg['duracao'] as int?;
      final tocando = _audioTocandoId == mensagemId;
      final Color corConteudo = isMinha ? Colors.white : (isDark ? Colors.white : Colors.black87);
      return Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, 6),
        decoration: decoracaoBalao,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: temAudio ? () => _alternarReproducaoAudio(mensagemId, msg) : null,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isMinha ? Colors.white.withAlpha(36) : corPrimaria.withAlpha(18),
                    ),
                    child: Icon(
                      tocando ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: isMinha ? Colors.white : corPrimaria,
                      size: 26,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                // a "onda" e decorativa (nao ha analise do audio gravado),
                // mas e o que faz a mensagem de voz ler como voz e nao como
                // uma linha de texto com um botao do lado
                _OndaAudio(cor: corConteudo, ativa: tocando),
                const SizedBox(width: AppSpacing.md),
                Text(
                  _formatarDuracao(duracao ?? 0),
                  style: AppTextStyles.caption.copyWith(
                    color: corConteudo.withAlpha(200),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            _buildRodapeHora(quando, isMinha, isDark),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg - 2, AppSpacing.sm + 2, AppSpacing.md, 6),
      decoration: decoracaoBalao,
      // Wrap, e nao Column: assim a hora senta na MESMA linha quando sobra
      // espaco (mensagem curta) e cai pra linha de baixo, encostada a
      // direita, quando nao sobra. Com Column o balao esticava ate os 70% da
      // tela mesmo pra um "ok", porque o alinhamento do texto obriga o filho
      // a ocupar toda a largura disponivel
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          Text(
            normalizarTracosOuVazio(msg['texto']),
            style: AppTextStyles.body.copyWith(
              color: isMinha ? Colors.white : (isDark ? Colors.white : Colors.black87),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.sm, top: 2),
            child: _buildRodapeHora(quando, isMinha, isDark),
          ),
        ],
      ),
    );
  }

  // hora e, nas minhas mensagens, o estado do envio. O relogio vira um tique
  // quando o horario do servidor volta: enquanto e nulo, a mensagem ainda
  // esta saindo do aparelho. Nao existe confirmacao de LEITURA aqui, entao
  // nao ha dois tiques -- prometer algo que o app nao sabe seria pior que
  // nao mostrar nada
  Widget _buildRodapeHora(DateTime? quando, bool isMinha, bool isDark, {bool sobreMidia = false}) {
    final Color cor = sobreMidia
        ? Colors.white.withAlpha(230)
        : isMinha
            ? Colors.white.withAlpha(180)
            : (isDark ? Colors.white38 : Colors.black38);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          quando == null ? 'enviando' : formatarHora(quando),
          style: AppTextStyles.label.copyWith(color: cor, fontSize: 10.5),
        ),
        if (isMinha) ...[
          const SizedBox(width: AppSpacing.xs),
          Icon(
            quando == null ? Icons.schedule_rounded : Icons.done_rounded,
            size: 13,
            color: cor,
          ),
        ],
      ],
    );
  }

  Widget _buildAreaEnvio(bool isDark) {
    final perfilIncompleto = _meuPerfil != null && !_meuPerfil!.perfilCompleto;
    final bool temTexto = _mensagemController.text.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isDark ? superficieEscura : Colors.white,
        border: Border(
          top: BorderSide(color: isDark ? Colors.white.withAlpha(16) : Colors.black.withAlpha(12)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(isDark ? 60 : 16),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: perfilIncompleto
            ? Row(
                children: [
                  const Icon(Icons.lock_outline_rounded, color: corAtencao, size: 20),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'Complete seu perfil pra poder enviar mensagens.',
                      style: AppTextStyles.caption.copyWith(
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _abrirConcluirPerfil,
                    child: const Text('Completar', style: TextStyle(color: corPrimaria, fontWeight: FontWeight.w700)),
                  ),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // o campo e o anexo vivem na MESMA pilula: antes o clipe
                  // ficava solto a esquerda e o campo era outra peca, o que
                  // dava tres elementos soltos na barra
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: _gravandoAudio
                            ? corErro.withAlpha(isDark ? 40 : 20)
                            : (isDark ? Colors.white.withAlpha(14) : superficieClara),
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        border: Border.all(
                          color: _gravandoAudio
                              ? corErro.withAlpha(90)
                              : (isDark ? Colors.white.withAlpha(18) : corPrimaria.withAlpha(22)),
                        ),
                      ),
                      child: _gravandoAudio
                          ? _buildLinhaGravacao(isDark)
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.attach_file_rounded,
                                    color: isDark ? Colors.white54 : corPrimaria,
                                    size: 21,
                                  ),
                                  onPressed: _enviandoMidia ? null : _mostrarOpcoesDeAnexo,
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _mensagemController,
                                    // ate 5 linhas antes de rolar: mensagem
                                    // longa rolando dentro de uma linha unica
                                    // e o jeito mais rapido de errar o que se
                                    // escreveu
                                    minLines: 1,
                                    maxLines: 5,
                                    textCapitalization: TextCapitalization.sentences,
                                    keyboardType: TextInputType.multiline,
                                    style: AppTextStyles.body.copyWith(
                                      color: isDark ? Colors.white : Colors.black87,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'Mensagem',
                                      hintStyle: AppTextStyles.body.copyWith(
                                        color: isDark ? Colors.white38 : Colors.black38,
                                      ),
                                      border: InputBorder.none,
                                      isDense: true,
                                      contentPadding: const EdgeInsets.symmetric(
                                        vertical: AppSpacing.md + 1,
                                        horizontal: 2,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _buildBotaoEnviar(temTexto, isDark),
                ],
              ),
      ),
    );
  }

  Widget _buildLinhaGravacao(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md + 2),
      child: Row(
        children: [
          // o ponto pisca junto com a onda: gravacao parada e gravacao
          // rodando pareciam iguais, so mudava o numero
          const _PontoGravando(),
          const SizedBox(width: AppSpacing.md),
          Text(
            _formatarDuracao(_segundosGravando),
            style: AppTextStyles.bodyBold.copyWith(
              color: isDark ? Colors.white : Colors.black87,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Toque em parar para enviar · máx ${_formatarDuracao(_duracaoMaximaAudio)}',
              style: AppTextStyles.label.copyWith(
                color: isDark ? Colors.white54 : Colors.black45,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBotaoEnviar(bool temTexto, bool isDark) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: _gravandoAudio ? null : gradientePrincipal,
        color: _gravandoAudio ? corErro : null,
        shape: BoxShape.circle,
        boxShadow: _gravandoAudio
            ? [BoxShadow(color: corErro.withAlpha(80), blurRadius: 16, offset: const Offset(0, 6))]
            : AppShadows.marca(forca: temTexto ? 1 : 0.6),
      ),
      child: IconButton(
        icon: _enviandoMidia
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Icon(
                temTexto
                    ? Icons.send_rounded
                    : (_gravandoAudio ? Icons.stop_rounded : Icons.mic_rounded),
                color: Colors.white,
                size: 21,
              ),
        onPressed: _enviandoMidia ? null : (temTexto ? _enviarMensagemTexto : _alternarGravacaoAudio),
      ),
    );
  }
}

// Barrinhas de uma mensagem de voz. Nao e a forma de onda real do audio
// gravado (o app nao analisa o arquivo): e um padrao fixo, derivado da
// posicao da barra, que so existe pra mensagem de voz nao parecer um botao
// de play perdido dentro do balao. As barras acendem enquanto toca
class _OndaAudio extends StatefulWidget {
  final Color cor;
  final bool ativa;

  const _OndaAudio({required this.cor, required this.ativa});

  @override
  State<_OndaAudio> createState() => _OndaAudioState();
}

class _OndaAudioState extends State<_OndaAudio> with SingleTickerProviderStateMixin {
  static const int _barras = 18;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.ativa) _controller.repeat();
  }

  @override
  void didUpdateWidget(_OndaAudio anterior) {
    super.didUpdateWidget(anterior);
    // parar em vez de deixar girando: animacao rodando em balao que nao esta
    // tocando gasta frame a toa numa lista que ja rola
    if (widget.ativa && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.ativa && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // alturas sempre iguais pra mesma barra: sorteio de verdade faria a onda
  // mudar a cada rebuild da lista
  double _altura(int i) => 6 + ((i * 37) % 13).toDouble();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // a "cabeca" da reproducao anda da esquerda pra direita; o que ja
        // passou fica aceso
        final double progresso = widget.ativa ? _controller.value * _barras : -1;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < _barras; i++)
              Container(
                width: 2.5,
                height: _altura(i),
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: widget.cor.withAlpha(i <= progresso ? 230 : 90),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ponto vermelho pulsando enquanto grava
class _PontoGravando extends StatefulWidget {
  const _PontoGravando();

  @override
  State<_PontoGravando> createState() => _PontoGravandoState();
}

class _PontoGravandoState extends State<_PontoGravando> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1).animate(_controller),
      child: const Icon(Icons.fiber_manual_record_rounded, color: corErro, size: 14),
    );
  }
}
