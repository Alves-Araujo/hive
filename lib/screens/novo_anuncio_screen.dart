import 'dart:io';
import 'package:flutter/material.dart';
import '../widgets/campo_endereco.dart';
import 'package:flutter/services.dart' show TextInputFormatter;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geocoding/geocoding.dart';
import '../models/imovel.dart';
import '../services/imgbb_service.dart';
import '../services/notificacao_service.dart';
import '../utils/moeda.dart';
import '../utils/texto.dart';
import '../widgets/animated_gradient_button.dart';
import '../main.dart';
import '../widgets/campo_formulario.dart';

const int _limiteTamanhoImagemBytes = 32 * 1024 * 1024; // 32MB por foto

// A MESMA tela publica e edita. Com `imovel` preenchido ela abre com tudo o
// que ja foi salvo e grava por cima do mesmo documento -- uma segunda tela de
// edicao seria uma copia deste formulario inteiro (endereco, IPTU, tags,
// comprovantes) condenada a divergir dele
class NovoAnuncioScreen extends StatefulWidget {
  final Imovel? imovel;

  // imobiliaria de quem esta publicando (so corretor de empresa tem uma). O
  // anuncio ja nasce ligado a ela: na edicao vale a que ficou gravada, senao
  // um corretor que trocou de imobiliaria levaria os anuncios antigos junto
  final String imobiliariaId;

  const NovoAnuncioScreen({super.key, this.imovel, this.imobiliariaId = ''});

  @override
  State<NovoAnuncioScreen> createState() => _NovoAnuncioScreenState();
}

class _NovoAnuncioScreenState extends State<NovoAnuncioScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _tituloController = TextEditingController();
  final TextEditingController _descricaoController = TextEditingController();
  final TextEditingController _precoController = TextEditingController();
  final TextEditingController _andarController = TextEditingController();
  final TextEditingController _iptuValorController = TextEditingController();
  final TextEditingController _tagPersonalizadaController = TextEditingController();

  // endereco estruturado -- exigido por completo (menos o complemento, que
  // nem todo imovel tem) pra nao salvar mais um "endereco" solto sem padrao
  final _endereco = EnderecoControllers();

  final TextEditingController _generoOutroController = TextEditingController();

  TipoListing _tipoSelecionado = TipoListing.moradia;
  String _tipoImovelSelecionado = '';
  final List<String> _tagsSelecionadas = [];
  bool _salvando = false;

  bool _incluiLuz = false;
  bool _incluiAgua = false;
  bool _incluiWifi = false;

  bool _iptuEhUpload = false;
  XFile? _comprovanteResidencia;
  XFile? _comprovanteIptu;

  bool _generoOutroSelecionado = false;

  final List<XFile> _imagensSelecionadas = [];
  final ImagePicker _picker = ImagePicker();

  // fotos que ja estao no anuncio (URLs do ImgBB) -- so existem na edicao.
  // Ficam separadas das escolhidas agora porque nao precisam subir de novo
  final List<String> _fotosJaSalvas = [];

  bool get _editando => widget.imovel != null;
  bool get _ehEvento => _tipoSelecionado == TipoListing.evento;
  bool get _ehApartamento => _tipoImovelSelecionado == 'Apartamento';

  // na edicao, um comprovante ja enviado continua valendo se a pessoa nao
  // escolher outro
  bool get _temComprovanteResidencia =>
      _comprovanteResidencia != null ||
      (widget.imovel?.comprovanteResidenciaUrl.isNotEmpty ?? false);
  bool get _temComprovanteIptu =>
      _comprovanteIptu != null || (widget.imovel?.iptuComprovanteUrl.isNotEmpty ?? false);

  @override
  void initState() {
    super.initState();
    final imovel = widget.imovel;
    if (imovel == null) return;

    _tituloController.text = imovel.titulo;
    _descricaoController.text = imovel.descricao;
    _precoController.text = formatarValorEmCampo(imovel.preco);
    _andarController.text = imovel.andar;
    _iptuValorController.text = formatarValorEmCampo(imovel.iptuValor);

    _endereco.cep.text = imovel.cep;
    _endereco.logradouro.text = imovel.logradouro;
    _endereco.numero.text = imovel.numero;
    _endereco.complemento.text = imovel.complemento;
    _endereco.bairro.text = imovel.bairro;
    _endereco.cidade.text = imovel.cidade;
    _endereco.estado = imovel.estado.isEmpty ? null : imovel.estado;

    _tipoSelecionado = imovel.tipo;
    _tipoImovelSelecionado = imovel.tipoImovel;
    _tagsSelecionadas.addAll(imovel.tags);
    _fotosJaSalvas.addAll(imovel.fotos);

    _incluiLuz = imovel.incluiLuz;
    _incluiAgua = imovel.incluiAgua;
    _incluiWifi = imovel.incluiWifi;
    _iptuEhUpload = imovel.iptuComprovanteUrl.isNotEmpty;
  }

  // monta a string de endereco completa a partir dos campos estruturados --
  // usada tanto pra geocodificar quanto pra exibir nas telas que so mostram
  // o "endereco" como texto corrido
  String get _enderecoCompleto {
    final numero = _endereco.numero.text.trim();
    final complemento = _endereco.complemento.text.trim();
    final partes = <String>[
      '${_endereco.logradouro.text.trim()}${numero.isNotEmpty ? ', $numero' : ''}',
      if (complemento.isNotEmpty) complemento,
      _endereco.bairro.text.trim(),
      '${_endereco.cidade.text.trim()} - ${_endereco.estado ?? ''}',
      'CEP ${_endereco.cep.text.trim()}',
    ];
    return partes.where((p) => p.trim().isNotEmpty).join(', ');
  }

  @override
  void dispose() {
    _tituloController.dispose();
    _descricaoController.dispose();
    _precoController.dispose();
    _andarController.dispose();
    _iptuValorController.dispose();
    _tagPersonalizadaController.dispose();
    _endereco.dispose();
    _generoOutroController.dispose();
    super.dispose();
  }

  void _mostrarErro(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: corErro),
    );
  }

  // abre a galeria pra escolher varias fotos de uma vez, ja checando o limite de tamanho
  Future<void> _escolherImagens() async {
    try {
      final List<XFile> imagens = await _picker.pickMultiImage(imageQuality: 70);
      if (imagens.isEmpty) return;

      final aceitas = <XFile>[];
      var algumaRecusada = false;
      for (final imagem in imagens) {
        if (await imagem.length() > _limiteTamanhoImagemBytes) {
          algumaRecusada = true;
        } else {
          aceitas.add(imagem);
        }
      }

      if (!mounted) return;
      setState(() => _imagensSelecionadas.addAll(aceitas));
      if (algumaRecusada) {
        _mostrarErro('Alguma foto passou de 32MB e foi ignorada.');
      }
    } catch (e) {
      if (!mounted) return;
      _mostrarErro('Erro ao selecionar imagens: $e');
    }
  }

  void _removerImagem(int index) {
    setState(() => _imagensSelecionadas.removeAt(index));
  }

  Future<XFile?> _escolherUmaImagem() async {
    final imagem = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (imagem == null) return null;
    if (await imagem.length() > _limiteTamanhoImagemBytes) {
      if (mounted) _mostrarErro('Esse arquivo passa de 32MB.');
      return null;
    }
    return imagem;
  }

  Future<void> _escolherComprovanteResidencia() async {
    final imagem = await _escolherUmaImagem();
    if (imagem != null) setState(() => _comprovanteResidencia = imagem);
  }

  Future<void> _escolherComprovanteIptu() async {
    final imagem = await _escolherUmaImagem();
    if (imagem != null) setState(() => _comprovanteIptu = imagem);
  }

  void _alternarTag(String tag) {
    setState(() {
      if (_tagsSelecionadas.contains(tag)) {
        _tagsSelecionadas.remove(tag);
      } else {
        _tagsSelecionadas.add(tag);
      }
    });
  }

  void _adicionarTagPersonalizada() {
    final tag = _tagPersonalizadaController.text.trim();
    if (tag.isEmpty || _tagsSelecionadas.contains(tag)) return;
    setState(() {
      _tagsSelecionadas.add(tag);
      _tagPersonalizadaController.clear();
    });
  }

  // valida o form, geocodifica o endereco, sobe as fotos/documentos e salva no firestore
  Future<void> _salvarAnuncio() async {
    if (!_formKey.currentState!.validate()) return;
    if (_imagensSelecionadas.isEmpty && _fotosJaSalvas.isEmpty) {
      _mostrarErro('Adicione pelo menos uma foto!');
      return;
    }

    if (_endereco.cep.text.trim().isEmpty ||
        _endereco.logradouro.text.trim().isEmpty ||
        _endereco.numero.text.trim().isEmpty ||
        _endereco.bairro.text.trim().isEmpty ||
        _endereco.cidade.text.trim().isEmpty ||
        _endereco.estado == null) {
      _mostrarErro('Preencha todos os campos do endereço (CEP, logradouro, número, bairro, cidade e estado).');
      return;
    }
    if (_generoOutroSelecionado && _generoOutroController.text.trim().isEmpty) {
      _mostrarErro('Especifique a preferência de gênero em "Outro", ou desmarque a opção.');
      return;
    }

    // na edicao vale o tipo GRAVADO, nunca o estado da tela: o seletor esta
    // desligado, e isto e a rede de seguranca do lado do app (as regras do
    // firestore recusam a troca do campo `tipo` no update)
    final tipoFinal = widget.imovel?.tipo ?? _tipoSelecionado;
    final ehMoradia = tipoFinal == TipoListing.moradia;
    if (ehMoradia) {
      if (_tipoImovelSelecionado.isEmpty) {
        _mostrarErro('Selecione o tipo do imóvel.');
        return;
      }
      if (_ehApartamento && _andarController.text.trim().isEmpty) {
        _mostrarErro('Informe o andar do apartamento.');
        return;
      }
      if (!_temComprovanteResidencia) {
        _mostrarErro('Anexe o comprovante de residência.');
        return;
      }
      if (_iptuEhUpload && !_temComprovanteIptu) {
        _mostrarErro('Anexe o comprovante de IPTU.');
        return;
      }
      if (!_iptuEhUpload && valorDoCampo(_iptuValorController.text) <= 0) {
        _mostrarErro('Informe o valor do IPTU.');
        return;
      }
    }

    setState(() => _salvando = true);

    try {
      final enderecoFormatado = _enderecoCompleto;
      // na edicao o fallback e a coordenada que o anuncio JA tem: se a
      // geocodificacao falhar agora, um imovel que estava no lugar certo iria
      // parar no Inatel so por ter sido reaberto pra corrigir o preco
      double lat = widget.imovel?.posicao.latitude ?? posicaoInatel.latitude;
      double lng = widget.imovel?.posicao.longitude ?? posicaoInatel.longitude;

      // transforma o endereco digitado em lat/lng
      try {
        final geocoding = Geocoding();
        List<Location> locations = await geocoding.locationFromAddress(enderecoFormatado);
        if (locations.isNotEmpty) {
          lat = locations.first.latitude;
          lng = locations.first.longitude;
        }
      } catch (e) {
        debugPrint("Geocoding falhou, usando coordenada de fallback: $e");
      }

      final colecao = FirebaseFirestore.instance.collection('imoveis');
      final docRef = _editando ? colecao.doc(widget.imovel!.id) : colecao.doc();

      // so as fotos novas sobem: as que ja estavam no anuncio continuam
      // apontando pra mesma URL
      final urlsImagens = [
        ..._fotosJaSalvas,
        ...await ImgbbService.instance.enviarImagens(_imagensSelecionadas),
      ];

      String comprovanteResidenciaUrl = '';
      String comprovanteIptuUrl = '';
      if (ehMoradia) {
        comprovanteResidenciaUrl = _comprovanteResidencia != null
            ? await ImgbbService.instance.enviarImagem(_comprovanteResidencia!)
            : widget.imovel?.comprovanteResidenciaUrl ?? '';
        if (_iptuEhUpload) {
          comprovanteIptuUrl = _comprovanteIptu != null
              ? await ImgbbService.instance.enviarImagem(_comprovanteIptu!)
              : widget.imovel?.iptuComprovanteUrl ?? '';
        }
      }

      final tagsFinal = List<String>.from(_tagsSelecionadas);
      if (_generoOutroSelecionado) {
        final custom = _generoOutroController.text.trim();
        if (custom.isNotEmpty && !tagsFinal.contains(custom)) tagsFinal.add(custom);
      }

      final novoImovel = Imovel(
        id: docRef.id,
        titulo: _tituloController.text.trim(),
        descricao: _descricaoController.text.trim(),
        preco: valorDoCampo(_precoController.text),
        posicao: LatLng(lat, lng),
        tipo: tipoFinal,
        tags: tagsFinal,
        endereco: enderecoFormatado,
        fotos: urlsImagens,
        // na edicao o dono continua sendo quem publicou: as regras do
        // firestore comparam esse campo com quem esta autenticado
        donoUid: widget.imovel?.donoUid ?? FirebaseAuth.instance.currentUser?.uid ?? '',
        imobiliariaId: widget.imovel?.imobiliariaId ?? widget.imobiliariaId,
        cep: _endereco.cep.text.trim(),
        logradouro: _endereco.logradouro.text.trim(),
        numero: _endereco.numero.text.trim(),
        complemento: _endereco.complemento.text.trim(),
        bairro: _endereco.bairro.text.trim(),
        cidade: capitalizarNome(_endereco.cidade.text.trim()),
        estado: _endereco.estado ?? '',
        tipoImovel: ehMoradia ? _tipoImovelSelecionado : '',
        andar: (ehMoradia && _ehApartamento) ? _andarController.text.trim() : '',
        comprovanteResidenciaUrl: comprovanteResidenciaUrl,
        iptuValor: (ehMoradia && !_iptuEhUpload) ? valorDoCampo(_iptuValorController.text) : 0.0,
        iptuComprovanteUrl: comprovanteIptuUrl,
        incluiLuz: _incluiLuz,
        incluiAgua: _incluiAgua,
        incluiWifi: _incluiWifi,
      );

      // merge por causa do prazo de resposta: aguardandoRespostaDesde nao sai
      // em toMap() (ver models/imovel.dart), e um set inteiro apagaria o
      // campo -- reabrir o anuncio pra mexer no preco zeraria o prazo de quem
      // esta esperando resposta ha meses. Todo o resto vai escrito aqui
      // mesmo, entao o merge nao deixa nada velho pra tras
      await docRef.set(novoImovel.toMap(), SetOptions(merge: true));
      // o aviso e de anuncio NOVO: edicao nao notifica ninguem de novo.
      // Sem await -- o anuncio ja foi publicado, o aviso nao segura a tela
      if (!_editando) NotificacaoService.instance.avisarNovoAnuncio(novoImovel);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_editando
                ? 'Anúncio atualizado com sucesso!'
                : 'Anúncio publicado com sucesso!'),
            backgroundColor: corSucesso,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) _mostrarErro('Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? corFundoEscuro : superficieClara,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
        title: Text(
          _editando ? 'Editar Anúncio' : 'Novo Anúncio',
          style: AppTextStyles.heading3.copyWith(color: isDark ? Colors.white : Colors.black87),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Fotos do Local', style: AppTextStyles.captionBold.copyWith(color: isDark ? Colors.white70 : Colors.black87)),
              const SizedBox(height: 12),
              _buildSeletorDeFotos(isDark),
              const SizedBox(height: 24),

              // categoria e imutavel depois de publicado: um anuncio que vira
              // do outro tipo deixa pra tras campos que so o tipo antigo usa
              // (IPTU, comprovante, tipo do imovel) e some da aba onde as
              // pessoas ja o encontravam. Na edicao o seletor fica desligado e
              // _salvarAnuncio grava o tipo que ja esta no banco, nao este estado
              RadioGroup<TipoListing>(
                groupValue: _tipoSelecionado,
                onChanged: (val) => setState(() => _tipoSelecionado = val!),
                child: Row(
                  children: [
                    Expanded(
                      child: RadioListTile<TipoListing>(
                        title: const Text('Moradia'),
                        value: TipoListing.moradia,
                        activeColor: corPrimaria,
                        enabled: !_editando,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<TipoListing>(
                        title: const Text('Evento'),
                        value: TipoListing.evento,
                        activeColor: corAtencao,
                        enabled: !_editando,
                      ),
                    ),
                  ],
                ),
              ),
              if (_editando) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, size: 14, color: isDark ? Colors.white38 : Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'A categoria do anúncio não muda depois de publicado. '
                        'Se errou, apague este e publique de novo.',
                        style: AppTextStyles.caption.copyWith(color: isDark ? Colors.white38 : Colors.grey),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),

              _buildTextField(
                controller: _tituloController,
                label: 'Título do Anúncio',
                icon: Icons.title_rounded,
                isDark: isDark,
                validator: (val) => val!.isEmpty ? 'Informe o título' : null,
              ),
              const SizedBox(height: 16),

              _buildTextField(
                controller: _descricaoController,
                label: 'Descrição',
                icon: Icons.description_outlined,
                isDark: isDark,
                maxLines: 3,
                validator: (val) => val!.isEmpty ? 'Informe a descrição' : null,
              ),
              const SizedBox(height: 16),

              Text('Endereço', style: AppTextStyles.captionBold.copyWith(color: isDark ? Colors.white70 : Colors.black87)),
              const SizedBox(height: 12),
              CampoEndereco(controllers: _endereco, isDark: isDark),
              const SizedBox(height: 16),

              // evento pode ser de graca: campo vazio vale como preco zero e a
              // ficha mostra "Gratuita". Moradia continua exigindo valor --
              // aluguel sem preco nao e anuncio de aluguel
              _buildTextField(
                controller: _precoController,
                label: _ehEvento ? 'Preço (deixe vazio se a entrada for gratuita)' : 'Preço',
                icon: Icons.attach_money_rounded,
                isDark: isDark,
                campoDeDinheiro: true,
                validator: (val) {
                  if (_ehEvento) return null;
                  if (val == null || val.isEmpty) return 'Informe o preço';
                  return valorDoCampo(val) > 0 ? null : 'Informe um valor maior que zero';
                },
              ),
              if (_ehEvento) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.celebration_rounded, size: 14, color: corEvento),
                    const SizedBox(width: 6),
                    Text(
                      'Sem valor, o evento aparece como "Gratuita".',
                      style: AppTextStyles.caption.copyWith(color: isDark ? Colors.white38 : Colors.grey),
                    ),
                  ],
                ),
              ],

              if (_tipoSelecionado == TipoListing.moradia) ...[
                const SizedBox(height: 24),
                Text('Tipo do imóvel', style: AppTextStyles.captionBold.copyWith(color: isDark ? Colors.white70 : Colors.black87)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: tiposImovelDisponiveis.map((tipo) {
                    final selecionado = _tipoImovelSelecionado == tipo;
                    return ChoiceChip(
                      label: Text(tipo),
                      selected: selecionado,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99.0)),
                      selectedColor: corPrimaria,
                      labelStyle: TextStyle(
                        color: selecionado ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                        fontWeight: FontWeight.w600,
                      ),
                      backgroundColor: isDark ? Colors.white.withAlpha(10) : Colors.grey.withAlpha(20),
                      onSelected: (_) => setState(() {
                        _tipoImovelSelecionado = tipo;
                        if (!_ehApartamento) _andarController.clear();
                      }),
                    );
                  }).toList(),
                ),

                if (_ehApartamento) ...[
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _andarController,
                    label: 'Andar',
                    icon: Icons.stairs_outlined,
                    isDark: isDark,
                    keyboardType: TextInputType.number,
                  ),
                ],

                const SizedBox(height: 24),
                Text('Comprovante de residência', style: AppTextStyles.captionBold.copyWith(color: isDark ? Colors.white70 : Colors.black87)),
                const SizedBox(height: 12),
                _buildUploadUnico(
                  isDark: isDark,
                  anexado: _temComprovanteResidencia,
                  onTap: _escolherComprovanteResidencia,
                  rotulo: 'Toque para anexar o comprovante',
                ),

                const SizedBox(height: 24),
                Text('IPTU', style: AppTextStyles.captionBold.copyWith(color: isDark ? Colors.white70 : Colors.black87)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Valor (R\$)'),
                        selected: !_iptuEhUpload,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99.0)),
                        selectedColor: corPrimaria,
                        labelStyle: TextStyle(color: !_iptuEhUpload ? Colors.white : (isDark ? Colors.white70 : Colors.black87)),
                        onSelected: (_) => setState(() => _iptuEhUpload = false),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Anexar comprovante'),
                        selected: _iptuEhUpload,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99.0)),
                        selectedColor: corPrimaria,
                        labelStyle: TextStyle(color: _iptuEhUpload ? Colors.white : (isDark ? Colors.white70 : Colors.black87)),
                        onSelected: (_) => setState(() => _iptuEhUpload = true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_iptuEhUpload)
                  _buildUploadUnico(
                    isDark: isDark,
                    anexado: _temComprovanteIptu,
                    onTap: _escolherComprovanteIptu,
                    rotulo: 'Toque para anexar o comprovante de IPTU',
                  )
                else
                  _buildTextField(
                    controller: _iptuValorController,
                    label: 'Valor anual do IPTU',
                    icon: Icons.receipt_long_outlined,
                    isDark: isDark,
                    campoDeDinheiro: true,
                  ),

                const SizedBox(height: 24),
                Text('O que está incluso', style: AppTextStyles.captionBold.copyWith(color: isDark ? Colors.white70 : Colors.black87)),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Luz'),
                  value: _incluiLuz,
                  activeColor: corPrimaria,
                  onChanged: (v) => setState(() => _incluiLuz = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Água'),
                  value: _incluiAgua,
                  activeColor: corPrimaria,
                  onChanged: (v) => setState(() => _incluiAgua = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Wi-Fi'),
                  value: _incluiWifi,
                  activeColor: corPrimaria,
                  onChanged: (v) => setState(() => _incluiWifi = v),
                ),

                const SizedBox(height: 20),
                _buildGrupoDeTags(isDark, 'Características positivas', tagsPositivas),
                const SizedBox(height: 16),
                _buildGrupoGenero(isDark),
                const SizedBox(height: 16),
                Text('Outra característica', style: AppTextStyles.captionBold.copyWith(color: isDark ? Colors.white70 : Colors.black87)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildTextField(
                        controller: _tagPersonalizadaController,
                        label: 'Ex: Aceita pets',
                        icon: Icons.label_outline_rounded,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _adicionarTagPersonalizada,
                      icon: const Icon(Icons.add_rounded),
                      style: IconButton.styleFrom(backgroundColor: corPrimaria),
                    ),
                  ],
                ),
                if (_tagsSelecionadas.where((t) => !tagsDisponiveis.contains(t)).isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _tagsSelecionadas.where((t) => !tagsDisponiveis.contains(t)).map((tag) {
                      return Chip(
                        label: Text(tag),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99.0)),
                        onDeleted: () => _alternarTag(tag),
                        backgroundColor: corPrimaria.withAlpha(20),
                      );
                    }).toList(),
                  ),
                ],
              ],

              const SizedBox(height: 40),
              _salvando
                  ? const Center(child: CircularProgressIndicator(color: corPrimaria))
                  : AnimatedGradientButton(
                      label: _editando ? 'Salvar Alterações' : 'Publicar Anúncio',
                      icon: _editando ? Icons.save_rounded : Icons.cloud_upload_rounded,
                      onTap: _salvarAnuncio,
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGrupoDeTags(bool isDark, String titulo, List<String> tags) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo, style: AppTextStyles.captionBold.copyWith(color: isDark ? Colors.white70 : Colors.black87)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tags.map((tag) {
            final selecionado = _tagsSelecionadas.contains(tag);
            return FilterChip(
              label: Text(tag),
              selected: selecionado,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99.0)),
              selectedColor: corPrimaria.withAlpha(50),
              checkmarkColor: isDark ? Colors.white : corPrimaria,
              backgroundColor: isDark ? Colors.white.withAlpha(10) : Colors.grey.withAlpha(20),
              labelStyle: TextStyle(
                color: selecionado ? (isDark ? Colors.white : corPrimaria) : (isDark ? Colors.white60 : Colors.black87),
              ),
              onSelected: (_) => _alternarTag(tag),
            );
          }).toList(),
        ),
      ],
    );
  }

  // igual ao _buildGrupoDeTags, mas com um chip "Outro" a mais que revela um
  // campo de texto -- o que for digitado ali vira a tag de verdade na hora de salvar
  Widget _buildGrupoGenero(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Preferência de gênero', style: AppTextStyles.captionBold.copyWith(color: isDark ? Colors.white70 : Colors.black87)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...tagsPreferenciaGenero.map((tag) {
              final selecionado = _tagsSelecionadas.contains(tag);
              return FilterChip(
                label: Text(tag),
                selected: selecionado,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99.0)),
                selectedColor: corPrimaria.withAlpha(50),
                checkmarkColor: isDark ? Colors.white : corPrimaria,
                backgroundColor: isDark ? Colors.white.withAlpha(10) : Colors.grey.withAlpha(20),
                labelStyle: TextStyle(
                  color: selecionado ? (isDark ? Colors.white : corPrimaria) : (isDark ? Colors.white60 : Colors.black87),
                ),
                onSelected: (_) => _alternarTag(tag),
              );
            }),
            FilterChip(
              label: const Text('Outro'),
              selected: _generoOutroSelecionado,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99.0)),
              selectedColor: corPrimaria.withAlpha(50),
              checkmarkColor: isDark ? Colors.white : corPrimaria,
              backgroundColor: isDark ? Colors.white.withAlpha(10) : Colors.grey.withAlpha(20),
              labelStyle: TextStyle(
                color: _generoOutroSelecionado ? (isDark ? Colors.white : corPrimaria) : (isDark ? Colors.white60 : Colors.black87),
              ),
              onSelected: (v) => setState(() {
                _generoOutroSelecionado = v;
                if (!v) _generoOutroController.clear();
              }),
            ),
          ],
        ),
        if (_generoOutroSelecionado) ...[
          const SizedBox(height: 8),
          _buildTextField(
            controller: _generoOutroController,
            label: 'Especifique a preferência',
            icon: Icons.edit_outlined,
            isDark: isDark,
          ),
        ],
      ],
    );
  }

  // `anexado` e nao o XFile: na edicao o comprovante pode ja estar enviado,
  // e nesse caso nao ha arquivo nenhum em maos pra mostrar
  Widget _buildUploadUnico({
    required bool isDark,
    required bool anexado,
    required VoidCallback onTap,
    required String rotulo,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withAlpha(5) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? Colors.white.withAlpha(20) : Colors.grey.withAlpha(50), width: 2),
        ),
        child: Row(
          children: [
            Icon(
              anexado ? Icons.check_circle_rounded : Icons.upload_file_rounded,
              color: anexado ? corSucesso : corPrimaria,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                anexado ? 'Arquivo selecionado' : rotulo,
                style: TextStyle(color: isDark ? Colors.white54 : Colors.grey.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeletorDeFotos(bool isDark) {
    if (_imagensSelecionadas.isEmpty && _fotosJaSalvas.isEmpty) {
      return GestureDetector(
        onTap: _escolherImagens,
        child: Container(
          width: double.infinity,
          height: 120,
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withAlpha(5) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isDark ? Colors.white.withAlpha(20) : Colors.grey.withAlpha(50), width: 2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_photo_alternate_rounded, size: 40, color: corPrimaria.withAlpha(150)),
              const SizedBox(height: 8),
              Text(
                'Toque para adicionar fotos (até 32MB cada)',
                style: TextStyle(color: isDark ? Colors.white54 : Colors.grey, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      );
    }

    // as ja salvas (edicao) vem primeiro, depois as escolhidas agora -- a
    // mesma ordem em que vao ser gravadas, entao a primeira miniatura e
    // sempre a foto de capa do anuncio
    final totalJaSalvas = _fotosJaSalvas.length;
    final total = totalJaSalvas + _imagensSelecionadas.length;

    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: total + 1,
        itemBuilder: (context, index) {
          if (index == total) {
            return GestureDetector(
              onTap: _escolherImagens,
              child: Container(
                width: 100,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withAlpha(10) : Colors.grey.withAlpha(30),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: corPrimaria.withAlpha(100), width: 2, style: BorderStyle.solid),
                ),
                child: const Icon(Icons.add_a_photo_rounded, color: corPrimaria, size: 32),
              ),
            );
          }

          final bool jaSalva = index < totalJaSalvas;
          return Stack(
            children: [
              Container(
                width: 100,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  image: DecorationImage(
                    image: jaSalva
                        ? NetworkImage(_fotosJaSalvas[index])
                        : FileImage(File(_imagensSelecionadas[index - totalJaSalvas].path))
                            as ImageProvider,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 16,
                child: GestureDetector(
                  onTap: () => jaSalva
                      ? setState(() => _fotosJaSalvas.removeAt(index))
                      : _removerImagem(index - totalJaSalvas),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded, color: Colors.white, size: 16),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isDark,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
    List<TextInputFormatter>? formatters,

    // preco e IPTU: teclado numerico + mascara de moeda em reais. Vem como
    // uma chave so pra nao dar pra esquecer metade da combinacao num campo
    // novo de dinheiro -- foi assim que o preco ficava R$ 0,00
    bool campoDeDinheiro = false,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: campoDeDinheiro
          ? const TextInputType.numberWithOptions(decimal: false, signed: false)
          : keyboardType,
      inputFormatters: campoDeDinheiro ? const [MoedaInputFormatter()] : formatters,
      textCapitalization: textCapitalization,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      validator: validator,
      // campo de varias linhas nao usa pilula: em caixa alta o raio de
      // pilula deforma e o texto encosta nas laterais
      decoration: decoracaoCampo(
        isDark: isDark,
        rotulo: label,
        icone: icon,
        prefixoTexto: campoDeDinheiro ? 'R\$ ' : null,
        raio: maxLines > 1 ? AppRadius.lg : AppRadius.md + 6,
      ),
    );
  }
}
