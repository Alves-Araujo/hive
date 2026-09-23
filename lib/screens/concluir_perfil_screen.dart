import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter;
import 'package:image_picker/image_picker.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../main.dart';
import '../widgets/campo_formulario.dart';
import '../models/endereco.dart';
import '../models/imobiliaria.dart';
import '../models/usuario.dart';
import '../services/imgbb_service.dart';
import '../services/imobiliaria_service.dart';
import '../services/usuario_service.dart';
import '../utils/documento_validator.dart';
import '../utils/moderacao.dart';
import '../widgets/animated_gradient_button.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/campo_endereco.dart';
import '../widgets/seletor_imobiliaria.dart';
import '../widgets/seletor_tipo_usuario.dart';

const List<String> generosDisponiveis = [
  'Masculino cis', 'Feminino cis', 'Masculino trans', 'Feminino trans',
  'Prefiro não dizer', 'Outro',
];

// tela cheia de "concluir perfil" -- onde o usuario escolhe o tipo de conta
// e preenche os documentos exigidos pra liberar o acesso completo ao app
class ConcluirPerfilScreen extends StatefulWidget {
  final Usuario perfil;
  const ConcluirPerfilScreen({super.key, required this.perfil});

  @override
  State<ConcluirPerfilScreen> createState() => _ConcluirPerfilScreenState();
}

class _ConcluirPerfilScreenState extends State<ConcluirPerfilScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  late final TextEditingController _nomeController;
  final _enderecoControllers = EnderecoControllers();
  final _documentoController = TextEditingController();
  final _generoOutroController = TextEditingController();

  final _nomeEmpresaController = TextEditingController();
  final _cnpjEmpresaController = TextEditingController();
  final _enderecoEmpresaControllers = EnderecoControllers();
  final _emailEmpresaController = TextEditingController();

  final _respNomeController = TextEditingController();
  final _respEnderecoControllers = EnderecoControllers();
  final _respCpfController = TextEditingController();
  final _respEmailController = TextEditingController();

  final _mascaraCpf = MaskTextInputFormatter(mask: '###.###.###-##', filter: {'#': RegExp(r'[0-9]')});
  final _mascaraCnpj = MaskTextInputFormatter(mask: '##.###.###/####-##', filter: {'#': RegExp(r'[0-9]')});
  final _mascaraCnpjEmpresa = MaskTextInputFormatter(mask: '##.###.###/####-##', filter: {'#': RegExp(r'[0-9]')});
  final _mascaraCpfResponsavel = MaskTextInputFormatter(mask: '###.###.###-##', filter: {'#': RegExp(r'[0-9]')});

  String? _tipoSelecionado;
  String _subtipoCorretor = '';
  String _generoSelecionado = '';
  bool _documentoEhCnpj = false;
  DateTime? _dataNascimento;
  String _fotoUrl = '';
  bool _enviandoFoto = false;
  bool _salvando = false;
  bool _aceitouTermos = false;

  // vinculo do corretor de empresa: ou ele escolhe uma imobiliaria ja
  // cadastrada, ou pede pra cadastrar uma nova e preenche o formulario da
  // empresa. Um dos dois e obrigatorio pra concluir o cadastro
  Imobiliaria? _imobiliariaSelecionada;
  bool _cadastrandoNovaImobiliaria = false;
  bool _carregandoImobiliaria = false;

  // proprietario e corretor autonomo podem escolher CPF ou CNPJ; corretor de
  // empresa tem o CNPJ na secao da empresa, entao o documento pessoal dele e sempre CPF
  bool get _permiteEscolherCnpj =>
      _tipoSelecionado == 'proprietario' ||
      (_tipoSelecionado == 'corretor' && _subtipoCorretor == 'autonomo');

  // documento e identidade: depois que o cadastro esta finalizado, CPF/CNPJ
  // viram somente leitura. Trocar o numero depois valeria por trocar de
  // pessoa -- e o perfil ja circulou em anuncio, chat e avaliacao com ele.
  // Vale campo a campo: quem completou o perfil como estudante e so agora
  // virou corretor de empresa nunca informou CNPJ da empresa, entao esse
  // ainda esta liberado
  bool get _documentoBloqueado =>
      widget.perfil.perfilCompleto &&
      (widget.perfil.cpf.isNotEmpty || widget.perfil.cnpj.isNotEmpty);

  bool get _cnpjEmpresaBloqueado =>
      widget.perfil.perfilCompleto && widget.perfil.cnpjEmpresa.isNotEmpty;

  bool get _cpfResponsavelBloqueado =>
      widget.perfil.perfilCompleto && widget.perfil.responsavelCpf.isNotEmpty;

  // tipo de conta e escolha de cadastro, nao preferencia: ele decide o que a
  // conta pode fazer (anunciar, vincular imobiliaria) e ja rendeu anuncio,
  // chat e avaliacao com esse papel. Depois de finalizado nao muda mais --
  // aqui e no update do Firestore (ver UsuarioService.completarPerfil)
  bool get _tipoDeContaBloqueado =>
      widget.perfil.perfilCompleto && widget.perfil.tipoUsuario.isNotEmpty;

  // o subtipo anda junto: se desse pra trocar "empresa" por "autonomo", o
  // corretor fugiria da aprovacao da imobiliaria e anunciaria assim mesmo
  bool get _subtipoBloqueado =>
      _tipoDeContaBloqueado && widget.perfil.subtipoCorretor.isNotEmpty;

  int? get _idade => _dataNascimento != null ? calcularIdade(_dataNascimento!) : null;

  bool get _mostraSecaoResponsavel =>
      _tipoSelecionado == 'estudante' && _idade != null && _idade! < 18;

  bool get _mostraSecaoEmpresa => _tipoSelecionado == 'corretor' && _subtipoCorretor == 'empresa';

  // os dados da empresa (nome, CNPJ, endereco, e-mail) so sao pedidos pra
  // quem esta CADASTRANDO uma imobiliaria nova. Escolhendo uma que ja existe,
  // esses dados ja estao no cadastro dela -- pedir de novo so daria chance de
  // divergirem
  bool get _mostraFormularioDeEmpresa => _mostraSecaoEmpresa && _cadastrandoNovaImobiliaria;

  bool get _vinculoJaConfirmado =>
      widget.perfil.vinculoConfirmado &&
      widget.perfil.imobiliariaId.isNotEmpty &&
      widget.perfil.imobiliariaId == _imobiliariaSelecionada?.id;

  @override
  void initState() {
    super.initState();
    final p = widget.perfil;
    _nomeController = TextEditingController(text: p.nome);
    _enderecoControllers.preencher(p.endereco);
    _fotoUrl = p.fotoUrl;
    _tipoSelecionado = p.tipoUsuario.isNotEmpty ? p.tipoUsuario : null;
    _subtipoCorretor = p.subtipoCorretor;
    // genero customizado (nao esta na lista fixa) -> reabre como "Outro" com o texto salvo
    if (p.genero.isNotEmpty && !generosDisponiveis.contains(p.genero)) {
      _generoSelecionado = 'Outro';
      _generoOutroController.text = p.genero;
    } else {
      _generoSelecionado = p.genero;
    }
    _documentoEhCnpj = p.cnpj.isNotEmpty;
    _documentoController.text = _documentoEhCnpj ? p.cnpj : p.cpf;
    if (p.dataNascimento.isNotEmpty) {
      final partes = p.dataNascimento.split('/');
      if (partes.length == 3) {
        _dataNascimento = DateTime.tryParse('${partes[2]}-${partes[1]}-${partes[0]}');
      }
    }
    _nomeEmpresaController.text = p.nomeEmpresa;
    _cnpjEmpresaController.text = p.cnpjEmpresa;
    _enderecoEmpresaControllers.preencher(p.enderecoEmpresa);
    _emailEmpresaController.text = p.emailEmpresa;
    _respNomeController.text = p.responsavelNome;
    _respEnderecoControllers.preencher(p.responsavelEndereco);
    _respCpfController.text = p.responsavelCpf;
    _respEmailController.text = p.responsavelEmail;

    // quem ja tem vinculo reabre a tela com a imobiliaria dele carregada, pra
    // nao parecer que precisa escolher tudo de novo
    if (p.imobiliariaId.isNotEmpty) {
      // o flag vai direto, sem setState: ainda estamos em initState e o
      // primeiro build nem aconteceu
      _carregandoImobiliaria = true;
      _carregarImobiliariaDoPerfil(p.imobiliariaId);
    }
  }

  Future<void> _carregarImobiliariaDoPerfil(String id) async {
    final imobiliaria = await ImobiliariaService.instance.buscarPorId(id);
    if (!mounted) return;
    setState(() {
      _imobiliariaSelecionada = imobiliaria;
      _carregandoImobiliaria = false;
    });
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _enderecoControllers.dispose();
    _documentoController.dispose();
    _generoOutroController.dispose();
    _nomeEmpresaController.dispose();
    _cnpjEmpresaController.dispose();
    _enderecoEmpresaControllers.dispose();
    _emailEmpresaController.dispose();
    _respNomeController.dispose();
    _respEnderecoControllers.dispose();
    _respCpfController.dispose();
    _respEmailController.dispose();
    super.dispose();
  }

  void _mostrarErro(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: corErro),
    );
  }

  void _mostrarTermosDePrivacidade() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? superficieEscura : superficieClara,
        title: const Text('Termos de Privacidade'),
        content: const SingleChildScrollView(
          child: Text(
            'Ao usar o Hive, você concorda que os dados enviados aqui (documentos, endereço, '
            'foto) são usados só pra validar seu cadastro e conectar você com anunciantes/'
            'estudantes dentro do app. Nada é vendido ou repassado pra terceiros. '
            'Dados sensíveis (CPF/CNPJ, endereço) ficam visíveis só pra você; o que aparece pro '
            'resto dos usuários é o perfil público (nome, foto, avaliações).',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Fechar')),
        ],
      ),
    );
  }

  Future<void> _trocarFoto() async {
    // foto de perfil so aparece em circulos pequenos -- 512px sobra e evita
    // subir (e todo mundo baixar depois) a foto na resolucao cheia da camera
    final imagem = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 512, maxHeight: 512, imageQuality: 80);
    if (imagem == null) return;
    setState(() => _enviandoFoto = true);
    try {
      final url = await ImgbbService.instance.enviarImagem(imagem);
      if (mounted) setState(() => _fotoUrl = url);
    } catch (e) {
      if (mounted) _mostrarErro('Erro ao enviar foto: $e');
    } finally {
      if (mounted) setState(() => _enviandoFoto = false);
    }
  }

  Future<void> _escolherDataNascimento() async {
    final hoje = DateTime.now();
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _dataNascimento ?? DateTime(hoje.year - 20, hoje.month, hoje.day),
      firstDate: DateTime(hoje.year - 100),
      lastDate: hoje,
      helpText: 'Data de nascimento',
    );
    if (escolhida != null) setState(() => _dataNascimento = escolhida);
  }

  String _dataFormatada(DateTime data) {
    return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';
  }

  // valida os campos que nao tem TextFormField.validator (documento, data,
  // secoes condicionais) -- retorna a primeira mensagem de erro encontrada
  String? _validarCamposCondicionais() {
    // a foto e obrigatoria: o perfil aparece na conversa, no anuncio e na
    // avaliacao, e a inicial no circulo colorido nao diz com quem se esta
    // falando. Fica antes de tudo porque o avatar e o topo do formulario
    if (_enviandoFoto) return 'Espere a foto terminar de enviar.';
    if (_fotoUrl.trim().isEmpty) return 'Adicione uma foto de perfil.';

    if (_tipoSelecionado == null) return 'Selecione o tipo de conta.';

    if (_generoSelecionado.isEmpty) return 'Selecione seu gênero.';
    if (_generoSelecionado == 'Outro' && _generoOutroController.text.trim().isEmpty) {
      return 'Especifique seu gênero em "Outro".';
    }

    if (_dataNascimento == null) return 'Informe a data de nascimento.';

    final documento = _documentoController.text.trim();
    if (documento.isEmpty) return 'Informe o CPF${_permiteEscolherCnpj ? ' ou CNPJ' : ''}.';
    if (_documentoEhCnpj) {
      if (!validarCNPJ(documento)) return 'CNPJ inválido.';
    } else {
      if (!validarCPF(documento)) return 'CPF inválido.';
    }

    // enderecos (pessoal, empresa, responsavel) ja sao validados campo a
    // campo pelo proprio Form via CampoEndereco -- aqui so o que nao tem
    // TextFormField.validator
    if (_mostraSecaoEmpresa) {
      if (_imobiliariaSelecionada == null && !_cadastrandoNovaImobiliaria) {
        return 'Selecione a imobiliária em que você trabalha.';
      }
      if (_mostraFormularioDeEmpresa) {
        if (_nomeEmpresaController.text.trim().isEmpty) return 'Informe o nome da empresa.';
        if (!validarCNPJ(_cnpjEmpresaController.text.trim())) return 'CNPJ da empresa inválido.';
        if (!_emailEmpresaController.text.trim().contains('@')) return 'Informe um e-mail válido da empresa.';
      }
    }

    if (_tipoSelecionado == 'corretor' && _subtipoCorretor.isEmpty) {
      return 'Selecione se você é corretor autônomo ou de empresa.';
    }

    if (_mostraSecaoResponsavel) {
      if (_respNomeController.text.trim().isEmpty) return 'Informe o nome do responsável.';
      if (!validarCPF(_respCpfController.text.trim())) return 'CPF do responsável inválido.';
      if (!_respEmailController.text.trim().contains('@')) return 'Informe um e-mail válido do responsável.';
    }

    return null;
  }

  Future<void> _salvar() async {
    if (!_aceitouTermos) {
      _mostrarErro('Você precisa concordar com os termos de privacidade.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final nome = _nomeController.text.trim();
    if (!nomeTemCaracteresValidos(nome)) {
      _mostrarErro('Use só letras no nome (acentos são bem-vindos).');
      return;
    }
    if (!temNomeESobrenome(nome)) {
      _mostrarErro('Informe nome e sobrenome.');
      return;
    }
    if (contemPalavraImpropria(nome)) {
      _mostrarErro('Esse nome contém palavras não permitidas.');
      return;
    }

    final erroCondicional = _validarCamposCondicionais();
    if (erroCondicional != null) {
      _mostrarErro(erroCondicional);
      return;
    }

    setState(() => _salvando = true);
    try {
      if (await UsuarioService.instance.nomeJaExiste(nome, ignorarUid: widget.perfil.uid)) {
        _mostrarErro('Já existe uma conta cadastrada com esse nome.');
        return;
      }

      // o que vale pros campos travados e o que ja esta no perfil, nunca o
      // controller -- assim nem um estado de tela fora de sincronia troca o
      // documento de quem ja finalizou o cadastro
      final ehCnpj = _documentoBloqueado ? widget.perfil.cnpj.isNotEmpty : _documentoEhCnpj;
      final documento = _documentoBloqueado
          ? (widget.perfil.cnpj.isNotEmpty ? widget.perfil.cnpj : widget.perfil.cpf)
          : _documentoController.text.trim();
      final cnpjEmpresa = _cnpjEmpresaBloqueado
          ? widget.perfil.cnpjEmpresa
          : _cnpjEmpresaController.text.trim();
      final cpfResponsavel = _cpfResponsavelBloqueado
          ? widget.perfil.responsavelCpf
          : _respCpfController.text.trim();
      final tipoUsuario = _tipoDeContaBloqueado ? widget.perfil.tipoUsuario : _tipoSelecionado!;
      final subtipoCorretor = _subtipoBloqueado
          ? widget.perfil.subtipoCorretor
          : (tipoUsuario == 'corretor' ? _subtipoCorretor : '');

      // corretor de empresa: ou o id da imobiliaria que ele escolheu, ou o da
      // que ele acabou de cadastrar. O vinculo NASCE pendente -- quem aprova e
      // quem entra com o e-mail da imobiliaria (ver map_screen)
      String imobiliariaId = '';
      bool vinculoConfirmado = false;
      bool vinculoRecusado = false;
      if (_mostraSecaoEmpresa) {
        imobiliariaId = _cadastrandoNovaImobiliaria
            ? await ImobiliariaService.instance.encontrarOuCriar(
                nome: _nomeEmpresaController.text.trim(),
                cnpj: cnpjEmpresa,
                email: _emailEmpresaController.text.trim(),
                endereco: _enderecoEmpresaControllers.valor.formatado,
              )
            : _imobiliariaSelecionada!.id;
        // trocar de imobiliaria zera a resposta da anterior: aprovacao vale
        // pra quem aprovou, nao pra qualquer empresa que a pessoa escolher
        final mesmaDeAntes = widget.perfil.imobiliariaId == imobiliariaId;
        vinculoConfirmado = mesmaDeAntes && widget.perfil.vinculoConfirmado;
        vinculoRecusado = mesmaDeAntes && widget.perfil.vinculoRecusado;
      }

      final atualizado = Usuario(
        uid: widget.perfil.uid,
        nome: nome,
        nomeBusca: normalizarNome(nome),
        email: widget.perfil.email,
        tipoUsuario: tipoUsuario,
        subtipoCorretor: subtipoCorretor,
        fotoUrl: _fotoUrl,
        perfilCompleto: true,
        genero: _generoSelecionado == 'Outro' ? _generoOutroController.text.trim() : _generoSelecionado,
        // cidade "de interesse" agora vem direto da cidade do endereco --
        // nao pedimos mais separado (era duplicado, ver "Endereço atual" logo acima)
        cidade: _enderecoControllers.cidade.text.trim(),
        cpf: ehCnpj ? '' : documento,
        cnpj: ehCnpj ? documento : '',
        dataNascimento: _dataFormatada(_dataNascimento!),
        endereco: _enderecoControllers.valor,
        responsavelNome: _mostraSecaoResponsavel ? _respNomeController.text.trim() : '',
        responsavelEndereco: _mostraSecaoResponsavel ? _respEnderecoControllers.valor : const Endereco(),
        responsavelCpf: _mostraSecaoResponsavel ? cpfResponsavel : '',
        responsavelEmail: _mostraSecaoResponsavel ? _respEmailController.text.trim() : '',
        responsavelEmailVerificado: false,
        // os dados da empresa so ficam no perfil de quem CADASTROU a
        // imobiliaria. Escolhendo uma que ja existe, eles moram no cadastro
        // dela e o perfil guarda so o vinculo (imobiliariaId) -- copiar aqui
        // criaria uma segunda versao dos mesmos dados pra divergir depois, e
        // esbarraria na regra que trava o CNPJ da empresa ja gravado
        nomeEmpresa: _mostraFormularioDeEmpresa ? _nomeEmpresaController.text.trim() : '',
        cnpjEmpresa: _mostraFormularioDeEmpresa ? cnpjEmpresa : '',
        enderecoEmpresa:
            _mostraFormularioDeEmpresa ? _enderecoEmpresaControllers.valor : const Endereco(),
        emailEmpresa: _mostraFormularioDeEmpresa ? _emailEmpresaController.text.trim() : '',
        emailEmpresaVerificado: false,
        imobiliariaId: imobiliariaId,
        vinculoConfirmado: vinculoConfirmado,
        vinculoRecusado: vinculoRecusado,
      );

      await UsuarioService.instance.completarPerfil(atualizado);

      if (mounted) Navigator.pop(context, atualizado);
    } catch (e) {
      _mostrarErro('Erro ao salvar perfil: $e');
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
          widget.perfil.perfilCompleto ? 'Editar Perfil' : 'Concluir Perfil',
          style: AppTextStyles.heading3.copyWith(color: isDark ? Colors.white : Colors.black87),
        ),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            Center(
              child: Stack(
                children: [
                  AvatarWidget(nome: _nomeController.text, fotoUrl: _fotoUrl, size: 96, showOnlineIndicator: false),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _enviandoFoto ? null : _trocarFoto,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: gradientePrincipal,
                          shape: BoxShape.circle,
                          border: Border.all(color: isDark ? corFundoEscuro : Colors.white, width: 3),
                        ),
                        child: _enviandoFoto
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.camera_alt_rounded, size: 18, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // avisa antes de o botao recusar: a camerazinha sozinha parecia
            // opcional, e o erro so aparecia depois de preencher tudo
            Center(
              child: Text(
                _fotoUrl.trim().isEmpty
                    ? 'Toque na câmera e escolha sua foto de perfil (obrigatória)'
                    : 'Foto de perfil',
                textAlign: TextAlign.center,
                style: AppTextStyles.caption.copyWith(
                  color: _fotoUrl.trim().isEmpty
                      ? corErro
                      : (isDark ? Colors.white38 : Colors.grey),
                ),
              ),
            ),
            const SizedBox(height: 28),

            _secao(
              isDark: isDark,
              titulo: 'Dados básicos',
              icone: Icons.person_rounded,
              filhos: [
                _campo(controller: _nomeController, label: 'Nome completo', icon: Icons.badge_outlined, isDark: isDark,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe seu nome' : null,
                    onChanged: (_) => setState(() {})),
                const SizedBox(height: 14),
                Text('Endereço atual', style: AppTextStyles.captionBold.copyWith(color: isDark ? Colors.white70 : Colors.black87)),
                const SizedBox(height: 10),
                CampoEndereco(controllers: _enderecoControllers, isDark: isDark),
                const SizedBox(height: 14),
                _campoData(isDark),
              ],
            ),
            const SizedBox(height: 20),

            _secao(
              isDark: isDark,
              titulo: 'Gênero',
              icone: Icons.diversity_1_outlined,
              filhos: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: generosDisponiveis.map((genero) {
                    final selecionado = _generoSelecionado == genero;
                    return GestureDetector(
                      onTap: () => setState(() => _generoSelecionado = genero),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: selecionado ? gradientePrincipal : null,
                          color: selecionado ? null : (isDark ? Colors.white.withAlpha(8) : Colors.grey.withAlpha(15)),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          genero,
                          style: TextStyle(
                            color: selecionado ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (_generoSelecionado == 'Outro') ...[
                  const SizedBox(height: 12),
                  _campo(
                    controller: _generoOutroController,
                    label: 'Especifique seu gênero',
                    icon: Icons.edit_outlined,
                    isDark: isDark,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Especifique seu gênero' : null,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),

            _secao(
              isDark: isDark,
              titulo: 'Tipo de conta',
              icone: Icons.workspace_premium_outlined,
              filhos: [
                SeletorTipoUsuario(
                  valorSelecionado: _tipoSelecionado,
                  isDark: isDark,
                  bloqueado: _tipoDeContaBloqueado,
                  onSelecionar: (valor) => setState(() {
                    _tipoSelecionado = valor;
                    if (valor != 'corretor') _subtipoCorretor = '';
                    // documento ja finalizado nao acompanha a troca de tipo
                    if (!_documentoBloqueado) {
                      _documentoEhCnpj = false;
                      _documentoController.clear();
                    }
                  }),
                ),
                if (_tipoSelecionado == 'corretor') ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _chipEscolha(
                          isDark: isDark,
                          selecionado: _subtipoCorretor == 'autonomo',
                          label: 'Autônomo',
                          bloqueado: _subtipoBloqueado,
                          onTap: () => setState(() => _subtipoCorretor = 'autonomo'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _chipEscolha(
                          isDark: isDark,
                          selecionado: _subtipoCorretor == 'empresa',
                          label: 'Empresa',
                          bloqueado: _subtipoBloqueado,
                          onTap: () => setState(() {
                            _subtipoCorretor = 'empresa';
                            if (!_documentoBloqueado) {
                              _documentoEhCnpj = false;
                              _documentoController.clear();
                            }
                          }),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_tipoDeContaBloqueado) ...[
                  const SizedBox(height: 10),
                  _avisoBloqueado(
                    isDark,
                    'O tipo de conta é definido no cadastro e não muda depois. '
                    'Se escolheu errado, fale com o suporte.',
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),

            if (_tipoSelecionado != null)
              _secao(
                isDark: isDark,
                titulo: 'Documento pessoal',
                icone: Icons.badge_outlined,
                filhos: [
                  if (_permiteEscolherCnpj && !_documentoBloqueado)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: _chipEscolha(
                              isDark: isDark,
                              selecionado: !_documentoEhCnpj,
                              label: 'Pessoa Física (CPF)',
                              onTap: () => setState(() {
                                _documentoEhCnpj = false;
                                _documentoController.clear();
                              }),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _chipEscolha(
                              isDark: isDark,
                              selecionado: _documentoEhCnpj,
                              label: 'Pessoa Jurídica (CNPJ)',
                              onTap: () => setState(() {
                                _documentoEhCnpj = true;
                                _documentoController.clear();
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
                  _campo(
                    controller: _documentoController,
                    label: _documentoEhCnpj ? 'CNPJ' : 'CPF',
                    icon: Icons.badge_outlined,
                    isDark: isDark,
                    keyboardType: TextInputType.number,
                    formatters: [_documentoEhCnpj ? _mascaraCnpj : _mascaraCpf],
                    bloqueado: _documentoBloqueado,
                  ),
                  if (_documentoBloqueado) ...[
                    const SizedBox(height: 8),
                    _avisoBloqueado(
                      isDark,
                      '${_documentoEhCnpj ? 'CNPJ' : 'CPF'} não pode ser alterado depois que o '
                      'cadastro é finalizado. Se o número estiver errado, fale com o suporte.',
                    ),
                  ],
                ],
              ),

            if (_mostraSecaoEmpresa) ...[
              const SizedBox(height: 20),
              _secao(
                isDark: isDark,
                titulo: 'Imobiliária',
                icone: Icons.apartment_rounded,
                filhos: [
                  if (_carregandoImobiliaria)
                    const Center(child: CircularProgressIndicator(color: corPrimaria))
                  else
                    SeletorImobiliaria(
                      selecionada: _imobiliariaSelecionada,
                      isDark: isDark,
                      cadastrandoNova: _cadastrandoNovaImobiliaria,
                      onSelecionar: (imobiliaria) => setState(() {
                        _imobiliariaSelecionada = imobiliaria;
                        _cadastrandoNovaImobiliaria = false;
                      }),
                      onCadastrarNova: () => setState(() {
                        _cadastrandoNovaImobiliaria = true;
                        _imobiliariaSelecionada = null;
                      }),
                      onLimpar: () => setState(() {
                        _imobiliariaSelecionada = null;
                        _cadastrandoNovaImobiliaria = false;
                      }),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    _vinculoJaConfirmado
                        ? 'Seu vínculo com essa imobiliária já foi aprovado.'
                        : 'Seu cadastro fica como "pendente de aprovação" até a imobiliária '
                            'confirmar o vínculo. Até lá você não anuncia imóveis por ela.',
                    style: AppTextStyles.caption.copyWith(
                      color: _vinculoJaConfirmado
                          ? corSucesso
                          : (isDark ? Colors.white38 : Colors.grey),
                    ),
                  ),
                ],
              ),
            ],

            if (_mostraFormularioDeEmpresa) ...[
              const SizedBox(height: 20),
              _secao(
                isDark: isDark,
                titulo: 'Dados da empresa',
                icone: Icons.store_rounded,
                filhos: [
                  _campo(controller: _nomeEmpresaController, label: 'Nome da empresa', icon: Icons.store_outlined, isDark: isDark),
                  const SizedBox(height: 14),
                  _campo(controller: _cnpjEmpresaController, label: 'CNPJ da empresa', icon: Icons.badge_outlined, isDark: isDark,
                      keyboardType: TextInputType.number, formatters: [_mascaraCnpjEmpresa],
                      bloqueado: _cnpjEmpresaBloqueado),
                  if (_cnpjEmpresaBloqueado) ...[
                    const SizedBox(height: 8),
                    _avisoBloqueado(isDark, 'O CNPJ da empresa ficou travado quando o cadastro foi finalizado.'),
                  ],
                  const SizedBox(height: 14),
                  Text('Endereço corporativo', style: AppTextStyles.captionBold.copyWith(color: isDark ? Colors.white70 : Colors.black87)),
                  const SizedBox(height: 10),
                  CampoEndereco(controllers: _enderecoEmpresaControllers, isDark: isDark),
                  const SizedBox(height: 14),
                  _campo(controller: _emailEmpresaController, label: 'E-mail da empresa', icon: Icons.email_outlined, isDark: isDark,
                      keyboardType: TextInputType.emailAddress),
                  const SizedBox(height: 8),
                  Text(
                    'Vamos enviar um e-mail de confirmação pra esse endereço assim que a verificação estiver disponível. Por enquanto ele fica salvo como pendente.',
                    style: AppTextStyles.caption.copyWith(color: isDark ? Colors.white38 : Colors.grey),
                  ),
                ],
              ),
            ],

            if (_mostraSecaoResponsavel) ...[
              const SizedBox(height: 20),
              _secao(
                isDark: isDark,
                titulo: 'Dados do responsável (menor de 18 anos)',
                icone: Icons.family_restroom_rounded,
                filhos: [
                  _campo(controller: _respNomeController, label: 'Nome do responsável', icon: Icons.person_outline, isDark: isDark),
                  const SizedBox(height: 14),
                  Text('Endereço do responsável', style: AppTextStyles.captionBold.copyWith(color: isDark ? Colors.white70 : Colors.black87)),
                  const SizedBox(height: 10),
                  CampoEndereco(controllers: _respEnderecoControllers, isDark: isDark),
                  const SizedBox(height: 14),
                  _campo(controller: _respCpfController, label: 'CPF do responsável', icon: Icons.badge_outlined, isDark: isDark,
                      keyboardType: TextInputType.number, formatters: [_mascaraCpfResponsavel],
                      bloqueado: _cpfResponsavelBloqueado),
                  if (_cpfResponsavelBloqueado) ...[
                    const SizedBox(height: 8),
                    _avisoBloqueado(isDark, 'O CPF do responsável ficou travado quando o cadastro foi finalizado.'),
                  ],
                  const SizedBox(height: 14),
                  _campo(controller: _respEmailController, label: 'E-mail do responsável', icon: Icons.email_outlined, isDark: isDark,
                      keyboardType: TextInputType.emailAddress),
                  const SizedBox(height: 8),
                  Text(
                    'Vamos enviar uma confirmação pro e-mail do responsável assim que a verificação estiver disponível. Por enquanto fica salvo como pendente.',
                    style: AppTextStyles.caption.copyWith(color: isDark ? Colors.white38 : Colors.grey),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),
            GestureDetector(
              onTap: () => setState(() => _aceitouTermos = !_aceitouTermos),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _aceitouTermos,
                    activeColor: corPrimaria,
                    onChanged: (v) => setState(() => _aceitouTermos = v ?? false),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13),
                          children: [
                            const TextSpan(text: 'Concordo com os '),
                            TextSpan(
                              text: 'termos de privacidade',
                              style: const TextStyle(color: corPrimaria, fontWeight: FontWeight.w700),
                              recognizer: TapGestureRecognizer()..onTap = _mostrarTermosDePrivacidade,
                            ),
                            const TextSpan(text: '.'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            AnimatedOpacity(
              opacity: _aceitouTermos ? 1.0 : 0.5,
              duration: const Duration(milliseconds: 200),
              child: AnimatedGradientButton(
                label: 'Finalizar Cadastro',
                icon: Icons.check_circle_outline_rounded,
                isLoading: _salvando,
                onTap: _aceitouTermos ? _salvar : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _campoData(bool isDark) {
    final temData = _dataNascimento != null;
    return InkWell(
      onTap: _escolherDataNascimento,
      borderRadius: BorderRadius.circular(99.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withAlpha(8) : Colors.grey.withAlpha(15),
          borderRadius: BorderRadius.circular(99.0),
        ),
        child: Row(
          children: [
            Icon(Icons.cake_outlined, color: isDark ? Colors.white54 : corPrimaria),
            const SizedBox(width: 12),
            Text(
              temData
                  ? '${_dataFormatada(_dataNascimento!)}  •  $_idade anos'
                  : 'Data de nascimento',
              style: TextStyle(
                color: temData
                    ? (isDark ? Colors.white : Colors.black87)
                    : (isDark ? Colors.white54 : Colors.grey.shade600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _secao({
    required bool isDark,
    required String titulo,
    required IconData icone,
    required List<Widget> filhos,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? superficieEscura : superficieClara,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(isDark ? 40 : 8), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(gradient: gradientePrincipal, borderRadius: BorderRadius.circular(99.0)),
                child: Icon(icone, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              Text(titulo, style: AppTextStyles.bodyBold.copyWith(color: isDark ? Colors.white : Colors.black87)),
            ],
          ),
          const SizedBox(height: 16),
          ...filhos,
        ],
      ),
    );
  }

  Widget _chipEscolha({
    required bool isDark,
    required bool selecionado,
    required String label,
    required VoidCallback onTap,
    bool bloqueado = false,
  }) {
    return GestureDetector(
      onTap: bloqueado ? null : onTap,
      child: Opacity(
        opacity: bloqueado && !selecionado ? 0.45 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: selecionado ? gradientePrincipal : null,
            color: selecionado ? null : (isDark ? Colors.white.withAlpha(8) : Colors.grey.withAlpha(15)),
            borderRadius: BorderRadius.circular(99.0),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selecionado ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _campo({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isDark,
    FocusNode? focusNode,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
    bool bloqueado = false,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      validator: validator,
      onChanged: onChanged,
      // readOnly em vez de enabled:false -- o texto continua selecionavel
      // (da pra copiar o proprio documento) e o campo nao muda de altura
      readOnly: bloqueado,
      style: TextStyle(
        color: bloqueado
            ? (isDark ? Colors.white54 : Colors.black54)
            : (isDark ? Colors.white : Colors.black87),
      ),
      decoration: decoracaoCampo(
        isDark: isDark,
        rotulo: label,
        icone: icon,
        sufixo: bloqueado
            ? Icon(Icons.lock_outline_rounded, size: 19, color: isDark ? Colors.white38 : Colors.grey)
            : null,
      ),
    );
  }

  Widget _avisoBloqueado(bool isDark, String texto) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline_rounded, size: 14, color: isDark ? Colors.white38 : Colors.grey),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            texto,
            style: AppTextStyles.caption.copyWith(color: isDark ? Colors.white38 : Colors.grey),
          ),
        ),
      ],
    );
  }
}
