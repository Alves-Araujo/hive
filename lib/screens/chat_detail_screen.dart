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
import '../utils/texto.dart';
import '../main.dart';
import '../models/perfil_publico.dart';
import '../models/usuario.dart';
import '../services/notificacao_service.dart';
import '../services/perfil_publico_service.dart';
import '../services/usuario_service.dart';
import '../utils/chamada.dart';
import '../widgets/avatar_widget.dart';
import 'concluir_perfil_screen.dart';
import 'perfil_publico_screen.dart';

class ChatDetailScreen extends StatefulWidget {
  final String imovelTitulo;
  final String imovelId;
  final String donoUid;

  const ChatDetailScreen({
    super.key,
    required this.imovelTitulo,
    required this.imovelId,
    required this.donoUid,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final TextEditingController _mensagemController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();

  // cache de perfis dos remetentes, pra mostrar o avatar ao lado das mensagens
  final Map<String, PerfilPublico> _perfisCache = {};
  final Set<String> _buscandoPerfil = {};

  // todo mundo que ja escreveu aqui (preenchido pelo stream de mensagens)
  final Set<String> _participantes = {};

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

  // criado uma unica vez: se ficasse inline no build(), cada segundo de
  // gravacao (que da setState pra atualizar o cronometro) recriava o stream
  // e o chat piscava voltando pro loading
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _mensagensStream =
      _mensagensRef.orderBy('timestamp', descending: true).snapshots();

  @override
  void initState() {
    super.initState();
    NotificacaoService.instance.chatAberto = widget.imovelId;
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

  Future<void> _carregarContato() async {
    if (widget.donoUid.isEmpty) return;
    final perfil = await PerfilPublicoService.instance.buscarPorUid(widget.donoUid);
    if (perfil != null && mounted) setState(() => _contato = perfil);
  }

  // busca sob demanda o perfil de quem mandou a mensagem (uma vez por uid) --
  // le da colecao publica, ja que "usuarios" so o proprio dono pode ler
  void _carregarPerfilRemetente(String uid) {
    if (uid.isEmpty || _perfisCache.containsKey(uid) || _buscandoPerfil.contains(uid)) return;
    _buscandoPerfil.add(uid);
    PerfilPublicoService.instance.buscarPorUid(uid).then((perfil) {
      if (perfil != null && mounted) {
        setState(() => _perfisCache[uid] = perfil);
      }
    });
  }

  CollectionReference<Map<String, dynamic>> get _mensagensRef => FirebaseFirestore.instance
      .collection('chats')
      .doc(widget.imovelId)
      .collection('mensagens');

  Future<void> _enviarDocumentoMensagem(Map<String, dynamic> dados) async {
    final user = FirebaseAuth.instance.currentUser;
    await _mensagensRef.add({
      ...dados,
      'remetente': user?.email ?? 'anonimo',
      'remetenteUid': user?.uid ?? '',
      'timestamp': FieldValue.serverTimestamp(),
    });
    _avisarDestinatarios(dados, user?.uid ?? '');
  }

  // Quem recebe o aviso depende do tipo de chat:
  // - direto (perfil -> perfil): a outra pessoa, que e o donoUid daqui
  // - de anuncio: se quem escreve e interessado, o dono do anuncio; se e o
  //   dono respondendo, todo mundo que ja escreveu nessa conversa
  void _avisarDestinatarios(Map<String, dynamic> dados, String meuUid) {
    final ehDireto = widget.imovelId.startsWith('direto_');
    final Iterable<String> destinatarios;
    if (ehDireto || meuUid != widget.donoUid) {
      destinatarios = [widget.donoUid];
    } else {
      destinatarios = _participantes;
    }

    final String previa = switch (dados['tipo']) {
      'imagem' => 'Enviou uma foto',
      'audio' => 'Enviou um áudio',
      _ => dados['texto'] as String? ?? '',
    };

    NotificacaoService.instance.avisarNovaMensagem(
      destinatarios: destinatarios,
      remetenteNome: (_meuPerfil?.nome.isNotEmpty ?? false) ? _meuPerfil!.nome : 'Usuário Hive',
      previa: previa.length > 120 ? '${previa.substring(0, 120)}...' : previa,
      chatId: widget.imovelId,
      // quem recebe abre a conversa com: no direto, eu; no de anuncio, o dono
      contatoUid: ehDireto ? meuUid : widget.donoUid,
      imovelTitulo: widget.imovelTitulo,
    );
  }

  void _enviarMensagemTexto() async {
    final texto = _mensagemController.text.trim();
    if (texto.isEmpty) return;
    _mensagemController.clear();
    await _enviarDocumentoMensagem({'tipo': 'texto', 'texto': normalizarTracos(texto)});
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

  void _iniciarChamadaDeVoz() {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anonimo';
    final nome = (_meuPerfil?.nome.isNotEmpty ?? false) ? _meuPerfil!.nome : 'Usuário Hive';
    iniciarChamadaDeVoz(context, meuUid: uid, meuNome: nome, outroUid: widget.donoUid);
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
    if (NotificacaoService.instance.chatAberto == widget.imovelId) {
      NotificacaoService.instance.chatAberto = null;
    }
    _timerGravacao?.cancel();
    _mensagemController.dispose();
    _recorder.dispose();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final emailUsuario = FirebaseAuth.instance.currentUser?.email ?? 'anonimo';
    final double larguraMaxima = MediaQuery.of(context).size.width * 0.7;

    return Scaffold(
      backgroundColor: isDark ? corFundoEscuro : superficieClara,
      appBar: AppBar(
        backgroundColor: isDark ? superficieEscura : superficieClara,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
        titleSpacing: 0,
        title: InkWell(
          onTap: _contato == null ? null : _abrirPerfilDoContato,
          borderRadius: BorderRadius.circular(12),
          child: Row(
            children: [
              AvatarWidget(
                nome: (_contato?.nome.isNotEmpty ?? false) ? _contato!.nome : '?',
                fotoUrl: _contato?.fotoUrl,
                size: 36,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (_contato?.nome.isNotEmpty ?? false) ? _contato!.nome : 'Proprietário',
                      style: AppTextStyles.bodyBold.copyWith(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (widget.imovelTitulo.isNotEmpty)
                      Text(
                        'Ref: ${widget.imovelTitulo}',
                        style: AppTextStyles.caption.copyWith(color: corPrimaria, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_rounded),
            color: corPrimaria,
            onPressed: _iniciarChamadaDeVoz,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _mensagensStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: corPrimaria));
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text(
                      'Envie a primeira mensagem!',
                      style: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                    ),
                  );
                }

                final mensagens = snapshot.data!.docs;
                // guardado pra saber quem avisar quando o dono responder
                for (final doc in mensagens) {
                  final uid = doc.data()['remetenteUid'] as String? ?? '';
                  if (uid.isNotEmpty) _participantes.add(uid);
                }

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: mensagens.length,
                  itemBuilder: (context, index) {
                    final doc = mensagens[index];
                    final msg = doc.data();
                    final bool isMinha = msg['remetente'] == emailUsuario;
                    final remetenteUid = msg['remetenteUid'] as String? ?? '';
                    final tipo = msg['tipo'] as String? ?? 'texto';

                    PerfilPublico? perfilRemetente;
                    if (!isMinha && remetenteUid.isNotEmpty) {
                      _carregarPerfilRemetente(remetenteUid);
                      perfilRemetente = _perfisCache[remetenteUid];
                    }

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Align(
                        alignment: isMinha ? Alignment.centerRight : Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (!isMinha) ...[
                              AvatarWidget(
                                nome: (perfilRemetente?.nome.isNotEmpty ?? false) ? perfilRemetente!.nome : '?',
                                fotoUrl: perfilRemetente?.fotoUrl,
                                size: 28,
                              ),
                              const SizedBox(width: 8),
                            ],
                            ConstrainedBox(
                              constraints: BoxConstraints(maxWidth: larguraMaxima),
                              child: _buildConteudoMensagem(doc.id, tipo, msg, isMinha, isDark),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          _buildAreaEnvio(isDark),
        ],
      ),
    );
  }

  Widget _buildConteudoMensagem(String mensagemId, String tipo, Map<String, dynamic> msg, bool isMinha, bool isDark) {
    // minha mensagem leva o gradiente da marca; a recebida, a superficie do
    // app. A quina "mordida" de 4px do lado de quem enviou e o que da a
    // leitura de origem sem precisar de seta nem rotulo
    final decoracaoBalao = BoxDecoration(
      gradient: isMinha ? gradientePrincipal : null,
      color: isMinha ? null : (isDark ? Colors.white.withAlpha(16) : superficieClara),
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(AppRadius.md),
        topRight: const Radius.circular(AppRadius.md),
        bottomLeft: Radius.circular(isMinha ? AppRadius.md : 4),
        bottomRight: Radius.circular(isMinha ? 4 : AppRadius.md),
      ),
      border: isMinha
          ? null
          : Border.all(color: isDark ? Colors.white.withAlpha(14) : Colors.black.withAlpha(10)),
      boxShadow: AppShadows.nivel1(isDark),
    );

    if (tipo == 'imagem') {
      final base64 = msg['imagemBase64'] as String? ?? '';
      final url = msg['midiaUrl'] as String? ?? '';
      Uint8List? bytes;
      final Widget foto;
      if (base64.isNotEmpty) {
        bytes = _imagensCache.putIfAbsent(mensagemId, () => base64Decode(base64));
        foto = Image.memory(bytes, width: 200, fit: BoxFit.cover, gaplessPlayback: true);
      } else if (url.isNotEmpty) {
        foto = Image.network(url, width: 200, fit: BoxFit.cover);
      } else {
        foto = const SizedBox(width: 160, height: 160);
      }
      return Container(
        decoration: decoracaoBalao,
        padding: const EdgeInsets.all(4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: (bytes == null && url.isEmpty)
              ? foto
              : GestureDetector(
                  onTap: () => _abrirFotoAmpliada(bytes: bytes, url: url.isEmpty ? null : url),
                  child: foto,
                ),
        ),
      );
    }

    if (tipo == 'audio') {
      final temAudio = (msg['audioBase64'] as String? ?? '').isNotEmpty ||
          (msg['midiaUrl'] as String? ?? '').isNotEmpty;
      final duracao = msg['duracao'] as int?;
      final tocando = _audioTocandoId == mensagemId;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: decoracaoBalao,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: temAudio ? () => _alternarReproducaoAudio(mensagemId, msg) : null,
              child: Icon(
                tocando ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                color: isMinha ? Colors.white : corPrimaria,
                size: 32,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              duracao == null ? 'Mensagem de voz' : 'Mensagem de voz · ${_formatarDuracao(duracao)}',
              style: TextStyle(color: isMinha ? Colors.white : (isDark ? Colors.white : Colors.black87)),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: decoracaoBalao,
      child: Text(
        normalizarTracosOuVazio(msg['texto']),
        style: TextStyle(color: isMinha ? Colors.white : (isDark ? Colors.white : Colors.black87)),
      ),
    );
  }

  Widget _buildAreaEnvio(bool isDark) {
    final perfilIncompleto = _meuPerfil != null && !_meuPerfil!.perfilCompleto;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? corSuperficieEscura : Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(10), blurRadius: 10, offset: const Offset(0, -4)),
        ],
      ),
      child: SafeArea(
        child: perfilIncompleto
            ? Row(
                children: [
                  const Icon(Icons.lock_outline_rounded, color: corAtencao, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Complete seu perfil pra poder enviar mensagens.',
                      style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: _abrirConcluirPerfil,
                    child: const Text('Completar', style: TextStyle(color: corPrimaria, fontWeight: FontWeight.w700)),
                  ),
                ],
              )
            : Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.add_photo_alternate_outlined, color: isDark ? Colors.white54 : corPrimaria),
                    onPressed: _enviandoMidia ? null : _mostrarOpcoesDeAnexo,
                  ),
                  Expanded(
                    child: _gravandoAudio
                        ? Row(
                            children: [
                              const Icon(Icons.fiber_manual_record_rounded, color: corErro, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                'Gravando ${_formatarDuracao(_segundosGravando)} / ${_formatarDuracao(_duracaoMaximaAudio)}',
                                style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
                              ),
                            ],
                          )
                        : TextField(
                            controller: _mensagemController,
                            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                            decoration: InputDecoration(
                              hintText: 'Digite sua mensagem...',
                              hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                              filled: true,
                              fillColor: isDark ? Colors.white.withAlpha(10) : Colors.grey.withAlpha(15),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(99.0),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: _gravandoAudio ? corErro : corPrimaria,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: _enviandoMidia
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : Icon(
                              _mensagemController.text.trim().isEmpty
                                  ? (_gravandoAudio ? Icons.stop_rounded : Icons.mic_rounded)
                                  : Icons.send_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                      onPressed: _enviandoMidia
                          ? null
                          : (_mensagemController.text.trim().isEmpty ? _alternarGravacaoAudio : _enviarMensagemTexto),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
