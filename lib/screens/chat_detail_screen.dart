import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import '../utils/texto.dart';
import '../main.dart';
import '../models/perfil_publico.dart';
import '../models/usuario.dart';
import '../services/perfil_publico_service.dart';
import '../services/storage_service.dart';
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

  Usuario? _meuPerfil;
  PerfilPublico? _contato;

  bool _gravandoAudio = false;
  bool _enviandoMidia = false;
  String? _audioTocandoId;

  @override
  void initState() {
    super.initState();
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
  }

  void _enviarMensagemTexto() async {
    final texto = _mensagemController.text.trim();
    if (texto.isEmpty) return;
    _mensagemController.clear();
    await _enviarDocumentoMensagem({'tipo': 'texto', 'texto': normalizarTracos(texto)});
  }

  Future<void> _escolherEEnviarFoto(ImageSource source) async {
    Navigator.pop(context); // fecha a folha de opcoes de anexo
    final imagem = await _picker.pickImage(source: source, imageQuality: 70);
    if (imagem == null) return;

    setState(() => _enviandoMidia = true);
    try {
      final caminho = 'chats/${widget.imovelId}/midia/${DateTime.now().microsecondsSinceEpoch}.jpg';
      final url = await StorageService.instance.enviarArquivo(File(imagem.path), caminho);
      await _enviarDocumentoMensagem({'tipo': 'imagem', 'midiaUrl': url});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao enviar foto: $e'), backgroundColor: corErro),
        );
      }
    } finally {
      if (mounted) setState(() => _enviandoMidia = false);
    }
  }

  void _mostrarOpcoesDeAnexo() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? corCardEscuro : Colors.white,
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

  Future<void> _alternarGravacaoAudio() async {
    if (_gravandoAudio) {
      final caminho = await _recorder.stop();
      setState(() => _gravandoAudio = false);
      if (caminho == null) return;

      setState(() => _enviandoMidia = true);
      try {
        final destino = 'chats/${widget.imovelId}/midia/${DateTime.now().microsecondsSinceEpoch}.m4a';
        final url = await StorageService.instance.enviarArquivo(File(caminho), destino);
        await _enviarDocumentoMensagem({'tipo': 'audio', 'midiaUrl': url});
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao enviar áudio: $e'), backgroundColor: corErro),
          );
        }
      } finally {
        if (mounted) setState(() => _enviandoMidia = false);
      }
    } else {
      if (!await _recorder.hasPermission()) return;
      final diretorio = Directory.systemTemp;
      final caminho = '${diretorio.path}/audio_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(), path: caminho);
      setState(() => _gravandoAudio = true);
    }
  }

  Future<void> _alternarReproducaoAudio(String mensagemId, String url) async {
    if (_audioTocandoId == mensagemId) {
      await _player.pause();
      setState(() => _audioTocandoId = null);
    } else {
      await _player.play(UrlSource(url));
      setState(() => _audioTocandoId = mensagemId);
    }
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
      backgroundColor: isDark ? corSuperficieEscura : const Color(0xFFF8F7FF),
      appBar: AppBar(
        backgroundColor: isDark ? corCardEscuro : Colors.white,
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
            child: StreamBuilder<QuerySnapshot>(
              stream: _mensagensRef.orderBy('timestamp', descending: true).snapshots(),
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

                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: mensagens.length,
                  itemBuilder: (context, index) {
                    final doc = mensagens[index];
                    final msg = doc.data() as Map<String, dynamic>;
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
    final decoracaoBalao = BoxDecoration(
      color: isMinha ? corPrimaria : (isDark ? Colors.white.withAlpha(15) : Colors.white),
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(16),
        topRight: const Radius.circular(16),
        bottomLeft: Radius.circular(isMinha ? 16 : 4),
        bottomRight: Radius.circular(isMinha ? 4 : 16),
      ),
      boxShadow: [
        if (!isMinha) BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 4, offset: const Offset(0, 2)),
      ],
    );

    if (tipo == 'imagem') {
      final url = msg['midiaUrl'] as String? ?? '';
      return Container(
        decoration: decoracaoBalao,
        padding: const EdgeInsets.all(4),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: url.isEmpty
              ? const SizedBox(width: 160, height: 160)
              : Image.network(url, width: 200, fit: BoxFit.cover),
        ),
      );
    }

    if (tipo == 'audio') {
      final url = msg['midiaUrl'] as String? ?? '';
      final tocando = _audioTocandoId == mensagemId;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: decoracaoBalao,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: url.isEmpty ? null : () => _alternarReproducaoAudio(mensagemId, url),
              child: Icon(
                tocando ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                color: isMinha ? Colors.white : corPrimaria,
                size: 32,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Mensagem de voz',
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
        color: isDark ? corCardEscuro : Colors.white,
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
                              Text('Gravando áudio...', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
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
                                borderRadius: BorderRadius.circular(24),
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
