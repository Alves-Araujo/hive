import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geocoding/geocoding.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../models/imovel.dart';
import '../services/imgbb_service.dart';
import '../services/notificacao_service.dart';
import '../widgets/animated_gradient_button.dart';
import '../main.dart';
import '../widgets/campo_formulario.dart';

const int _limiteTamanhoImagemBytes = 32 * 1024 * 1024; // 32MB por foto

class NovoAnuncioScreen extends StatefulWidget {
  const NovoAnuncioScreen({super.key});

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
  final TextEditingController _cepController = TextEditingController();
  final TextEditingController _logradouroController = TextEditingController();
  final TextEditingController _numeroController = TextEditingController();
  final TextEditingController _complementoController = TextEditingController();
  final TextEditingController _bairroController = TextEditingController();
  final TextEditingController _cidadeController = TextEditingController();
  String? _estadoSelecionado;
  final _mascaraCep = MaskTextInputFormatter(mask: '#####-###', filter: {'#': RegExp(r'[0-9]')});

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

  bool get _ehApartamento => _tipoImovelSelecionado == 'Apartamento';

  // monta a string de endereco completa a partir dos campos estruturados --
  // usada tanto pra geocodificar quanto pra exibir nas telas que so mostram
  // o "endereco" como texto corrido
  String get _enderecoCompleto {
    final numero = _numeroController.text.trim();
    final complemento = _complementoController.text.trim();
    final partes = <String>[
      '${_logradouroController.text.trim()}${numero.isNotEmpty ? ', $numero' : ''}',
      if (complemento.isNotEmpty) complemento,
      _bairroController.text.trim(),
      '${_cidadeController.text.trim()} - ${_estadoSelecionado ?? ''}',
      'CEP ${_cepController.text.trim()}',
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
    _cepController.dispose();
    _logradouroController.dispose();
    _numeroController.dispose();
    _complementoController.dispose();
    _bairroController.dispose();
    _cidadeController.dispose();
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
    if (_imagensSelecionadas.isEmpty) {
      _mostrarErro('Adicione pelo menos uma foto!');
      return;
    }

    if (_cepController.text.trim().isEmpty ||
        _logradouroController.text.trim().isEmpty ||
        _numeroController.text.trim().isEmpty ||
        _bairroController.text.trim().isEmpty ||
        _cidadeController.text.trim().isEmpty ||
        _estadoSelecionado == null) {
      _mostrarErro('Preencha todos os campos do endereço (CEP, logradouro, número, bairro, cidade e estado).');
      return;
    }
    if (_generoOutroSelecionado && _generoOutroController.text.trim().isEmpty) {
      _mostrarErro('Especifique a preferência de gênero em "Outro", ou desmarque a opção.');
      return;
    }

    final ehMoradia = _tipoSelecionado == TipoListing.moradia;
    if (ehMoradia) {
      if (_tipoImovelSelecionado.isEmpty) {
        _mostrarErro('Selecione o tipo do imóvel.');
        return;
      }
      if (_ehApartamento && _andarController.text.trim().isEmpty) {
        _mostrarErro('Informe o andar do apartamento.');
        return;
      }
      if (_comprovanteResidencia == null) {
        _mostrarErro('Anexe o comprovante de residência.');
        return;
      }
      if (_iptuEhUpload && _comprovanteIptu == null) {
        _mostrarErro('Anexe o comprovante de IPTU.');
        return;
      }
      if (!_iptuEhUpload && _iptuValorController.text.trim().isEmpty) {
        _mostrarErro('Informe o valor do IPTU.');
        return;
      }
    }

    setState(() => _salvando = true);

    try {
      final enderecoFormatado = _enderecoCompleto;
      double lat = posicaoInatel.latitude;
      double lng = posicaoInatel.longitude;

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

      final docRef = FirebaseFirestore.instance.collection('imoveis').doc();

      final urlsImagens = await ImgbbService.instance.enviarImagens(_imagensSelecionadas);

      String comprovanteResidenciaUrl = '';
      String comprovanteIptuUrl = '';
      if (ehMoradia) {
        comprovanteResidenciaUrl = await ImgbbService.instance.enviarImagem(_comprovanteResidencia!);
        if (_iptuEhUpload) {
          comprovanteIptuUrl = await ImgbbService.instance.enviarImagem(_comprovanteIptu!);
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
        preco: double.tryParse(_precoController.text.replaceAll(',', '.')) ?? 0.0,
        posicao: LatLng(lat, lng),
        tipo: _tipoSelecionado,
        tags: tagsFinal,
        endereco: enderecoFormatado,
        fotos: urlsImagens,
        donoUid: FirebaseAuth.instance.currentUser?.uid ?? '',
        cep: _cepController.text.trim(),
        logradouro: _logradouroController.text.trim(),
        numero: _numeroController.text.trim(),
        complemento: _complementoController.text.trim(),
        bairro: _bairroController.text.trim(),
        cidade: _cidadeController.text.trim(),
        estado: _estadoSelecionado ?? '',
        tipoImovel: ehMoradia ? _tipoImovelSelecionado : '',
        andar: (ehMoradia && _ehApartamento) ? _andarController.text.trim() : '',
        comprovanteResidenciaUrl: comprovanteResidenciaUrl,
        iptuValor: (ehMoradia && !_iptuEhUpload) ? (double.tryParse(_iptuValorController.text.replaceAll(',', '.')) ?? 0.0) : 0.0,
        iptuComprovanteUrl: comprovanteIptuUrl,
        incluiLuz: _incluiLuz,
        incluiAgua: _incluiAgua,
        incluiWifi: _incluiWifi,
      );

      await docRef.set(novoImovel.toMap());
      // sem await: o anuncio ja foi publicado, o aviso nao segura a tela
      NotificacaoService.instance.avisarNovoAnuncio(novoImovel);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Anúncio publicado com sucesso!'), backgroundColor: corSucesso),
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
          'Novo Anúncio',
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
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<TipoListing>(
                        title: const Text('Evento'),
                        value: TipoListing.evento,
                        activeColor: corAtencao,
                      ),
                    ),
                  ],
                ),
              ),
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
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildTextField(
                      controller: _cepController,
                      label: 'CEP',
                      icon: Icons.markunread_mailbox_outlined,
                      isDark: isDark,
                      keyboardType: TextInputType.number,
                      formatters: [_mascaraCep],
                      validator: (val) => val!.isEmpty ? 'Informe o CEP' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _logradouroController,
                label: 'Logradouro (rua/avenida)',
                icon: Icons.signpost_outlined,
                isDark: isDark,
                validator: (val) => val!.isEmpty ? 'Informe o logradouro' : null,
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _numeroController,
                      label: 'Número',
                      icon: Icons.pin_outlined,
                      isDark: isDark,
                      keyboardType: TextInputType.number,
                      validator: (val) => val!.isEmpty ? 'Informe o número' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTextField(
                      controller: _complementoController,
                      label: 'Complemento (opcional)',
                      icon: Icons.apartment_outlined,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildTextField(
                controller: _bairroController,
                label: 'Bairro',
                icon: Icons.holiday_village_outlined,
                isDark: isDark,
                validator: (val) => val!.isEmpty ? 'Informe o bairro' : null,
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildTextField(
                      controller: _cidadeController,
                      label: 'Cidade',
                      icon: Icons.location_city_rounded,
                      isDark: isDark,
                      validator: (val) => val!.isEmpty ? 'Informe a cidade' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _estadoSelecionado,
                      isExpanded: true,
                      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                      dropdownColor: isDark ? superficieEscura : superficieClara,
                      decoration: decoracaoCampo(isDark: isDark, rotulo: 'UF'),
                      items: estadosBrasileiros
                          .map((uf) => DropdownMenuItem(value: uf, child: Text(uf)))
                          .toList(),
                      onChanged: (val) => setState(() => _estadoSelecionado = val),
                      validator: (val) => val == null ? 'UF' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _buildTextField(
                controller: _precoController,
                label: 'Preço (R\$)',
                icon: Icons.attach_money_rounded,
                isDark: isDark,
                keyboardType: TextInputType.number,
                validator: (val) => val!.isEmpty ? 'Informe o preço' : null,
              ),

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
                  arquivo: _comprovanteResidencia,
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
                    arquivo: _comprovanteIptu,
                    onTap: _escolherComprovanteIptu,
                    rotulo: 'Toque para anexar o comprovante de IPTU',
                  )
                else
                  _buildTextField(
                    controller: _iptuValorController,
                    label: 'Valor anual do IPTU (R\$)',
                    icon: Icons.receipt_long_outlined,
                    isDark: isDark,
                    keyboardType: TextInputType.number,
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
                      label: 'Publicar Anúncio',
                      icon: Icons.cloud_upload_rounded,
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

  Widget _buildUploadUnico({
    required bool isDark,
    required XFile? arquivo,
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
              arquivo != null ? Icons.check_circle_rounded : Icons.upload_file_rounded,
              color: arquivo != null ? corSucesso : corPrimaria,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                arquivo != null ? 'Arquivo selecionado' : rotulo,
                style: TextStyle(color: isDark ? Colors.white54 : Colors.grey.shade700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeletorDeFotos(bool isDark) {
    if (_imagensSelecionadas.isEmpty) {
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

    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _imagensSelecionadas.length + 1,
        itemBuilder: (context, index) {
          if (index == _imagensSelecionadas.length) {
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
          return Stack(
            children: [
              Container(
                width: 100,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  image: DecorationImage(
                    image: FileImage(File(_imagensSelecionadas[index].path)),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned(
                top: 4,
                right: 16,
                child: GestureDetector(
                  onTap: () => _removerImagem(index),
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
    String? Function(String?)? validator,
    List<TextInputFormatter>? formatters,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      validator: validator,
      // campo de varias linhas nao usa pilula: em caixa alta o raio de
      // pilula deforma e o texto encosta nas laterais
      decoration: decoracaoCampo(
        isDark: isDark,
        rotulo: label,
        icone: icon,
        raio: maxLines > 1 ? AppRadius.lg : AppRadius.md + 6,
      ),
    );
  }
}
