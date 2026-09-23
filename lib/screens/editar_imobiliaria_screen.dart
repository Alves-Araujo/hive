import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show TextInputFormatter;
import 'package:image_picker/image_picker.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../main.dart';
import '../models/imobiliaria.dart';
import '../services/imgbb_service.dart';
import '../services/imobiliaria_service.dart';
import '../utils/moderacao.dart';
import '../widgets/animated_gradient_button.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/campo_formulario.dart';

// Cadastro da propria imobiliaria, editavel pela conta que entra com o e-mail
// dela -- a mesma que aprova os corretores (ver FolhaVinculosPendentes).
//
// Antes nao existia tela nenhuma pra isso: a imobiliaria nascia no cadastro de
// um corretor e ficava congelada com o nome que ELE digitou. Corrigir exigia
// abrir outra conta, e os corretores ja vinculados continuavam apontando pro
// cadastro velho.
//
// O que NAO se edita aqui: CNPJ e e-mail. O CNPJ e a chave que "encontrarOuCriar"
// usa pra nao duplicar imobiliaria, e o e-mail e o que decide quem responde por
// ela -- trocar o e-mail seria entregar a empresa, e os corretores dela, pra
// outra conta. As regras do Firestore recusam os dois; aqui e so a tela
class EditarImobiliariaScreen extends StatefulWidget {
  final Imobiliaria imobiliaria;

  const EditarImobiliariaScreen({super.key, required this.imobiliaria});

  @override
  State<EditarImobiliariaScreen> createState() => _EditarImobiliariaScreenState();
}

class _EditarImobiliariaScreenState extends State<EditarImobiliariaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _picker = ImagePicker();

  late final TextEditingController _nomeController;
  late final TextEditingController _descricaoController;
  late final TextEditingController _telefoneController;
  late final TextEditingController _enderecoController;

  final _mascaraTelefone = MaskTextInputFormatter(
    mask: '(##) #####-####',
    filter: {'#': RegExp(r'[0-9]')},
  );

  late String _fotoUrl;
  bool _enviandoFoto = false;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    final i = widget.imobiliaria;
    _nomeController = TextEditingController(text: i.nome);
    _descricaoController = TextEditingController(text: i.descricao);
    // cadastro antigo pode ter telefone gravado sem mascara -- a mascara so
    // vale pro que for digitado daqui pra frente, entao o texto vai como esta
    _telefoneController = TextEditingController(text: i.telefone);
    _enderecoController = TextEditingController(text: i.endereco);
    _fotoUrl = i.fotoUrl;
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _descricaoController.dispose();
    _telefoneController.dispose();
    _enderecoController.dispose();
    super.dispose();
  }

  void _mostrarErro(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: corErro),
    );
  }

  Future<void> _trocarFoto() async {
    // mesmo tamanho da foto de perfil: aparece sempre em circulo pequeno
    final imagem = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
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

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    final nome = _nomeController.text.trim();
    // nome de empresa aceita numero e "&" (o validador de nome de PESSOA nao
    // serve aqui) -- o que continua barrado e palavrao, igual no resto do app
    if (contemPalavraImpropria(nome)) {
      _mostrarErro('Esse nome contém palavras não permitidas.');
      return;
    }

    setState(() => _salvando = true);
    try {
      final atualizada = await ImobiliariaService.instance.atualizarPerfil(
        atual: widget.imobiliaria,
        nome: nome,
        descricao: _descricaoController.text.trim(),
        telefone: _telefoneController.text.trim(),
        endereco: _enderecoController.text.trim(),
        fotoUrl: _fotoUrl,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dados da imobiliária atualizados.'),
          backgroundColor: corSucesso,
        ),
      );
      Navigator.pop(context, atualizada);
    } on FirebaseException catch (e) {
      // O Firestore recusa a gravacao com "permission-denied" nos dois casos em
      // que ela nao deveria ter chegado ate aqui: a conta nao e a dona do
      // e-mail da imobiliaria, ou as regras que liberam essa edicao ainda nao
      // foram publicadas no projeto. Jogar o codigo cru na barra vermelha nao
      // diz nada a quem esta com o celular na mao
      if (!mounted) return;
      _mostrarErro(
        e.code == 'permission-denied'
            ? 'Esta conta não tem permissão para editar o cadastro da '
                'imobiliária. Entre com o e-mail dela (confirmado) e tente de novo.'
            : 'Erro ao salvar: ${e.message ?? e.code}',
      );
    } catch (e) {
      if (mounted) _mostrarErro('Erro ao salvar: $e');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? corFundoEscuro : superficieClara,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black87),
        title: Text(
          'Dados da Imobiliária',
          style: AppTextStyles.heading3.copyWith(
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        centerTitle: true,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.sm,
            AppSpacing.xl,
            AppSpacing.xxxl + AppSpacing.sm,
          ),
          children: [
            Center(
              child: Stack(
                children: [
                  AvatarWidget(
                    nome: _nomeController.text,
                    fotoUrl: _fotoUrl,
                    size: 96,
                    showOnlineIndicator: false,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: _enviandoFoto ? null : _trocarFoto,
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          gradient: gradientePrincipal,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? corFundoEscuro : Colors.white,
                            width: 3,
                          ),
                        ),
                        child: _enviandoFoto
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.camera_alt_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxl + AppSpacing.xs),

            _secao(
              isDark: isDark,
              titulo: 'Identificação',
              icone: Icons.apartment_rounded,
              filhos: [
                _campo(
                  controller: _nomeController,
                  label: 'Nome da imobiliária',
                  icon: Icons.store_outlined,
                  isDark: isDark,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Informe o nome da imobiliária'
                      : null,
                  // o nome alimenta o avatar logo acima
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.md + 2),
                _campo(
                  controller: _descricaoController,
                  label: 'Descrição (opcional)',
                  dica: 'Conte em uma linha o que a imobiliária faz.',
                  icon: Icons.notes_rounded,
                  isDark: isDark,
                  linhas: 3,
                ),
                const SizedBox(height: AppSpacing.md + 2),
                _campo(
                  controller: _telefoneController,
                  label: 'Telefone (opcional)',
                  icon: Icons.phone_outlined,
                  isDark: isDark,
                  keyboardType: TextInputType.phone,
                  formatters: [_mascaraTelefone],
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            _secao(
              isDark: isDark,
              titulo: 'Endereço do escritório',
              icone: Icons.location_on_outlined,
              filhos: [
                _campo(
                  controller: _enderecoController,
                  label: 'Endereço completo',
                  dica: 'Rua, número, bairro, cidade - UF',
                  icon: Icons.map_outlined,
                  isDark: isDark,
                  linhas: 2,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'É esse endereço que vira o pin da imobiliária no mapa. '
                  'Mudou de escritório? Salvando, o pin muda junto; se o '
                  'endereço não for reconhecido, ela sai do mapa até ser corrigido.',
                  style: AppTextStyles.caption.copyWith(
                    color: isDark ? Colors.white38 : Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            _secao(
              isDark: isDark,
              titulo: 'Dados fixos',
              icone: Icons.lock_outline_rounded,
              filhos: [
                _campoTravado(
                  isDark: isDark,
                  label: 'CNPJ',
                  icon: Icons.badge_outlined,
                  valor: widget.imobiliaria.cnpj.isNotEmpty
                      ? widget.imobiliaria.cnpj
                      : 'Não informado',
                ),
                const SizedBox(height: AppSpacing.md + 2),
                _campoTravado(
                  isDark: isDark,
                  label: 'E-mail da imobiliária',
                  icon: Icons.email_outlined,
                  valor: widget.imobiliaria.email,
                ),
                const SizedBox(height: AppSpacing.sm),
                _avisoBloqueado(
                  isDark,
                  'CNPJ e e-mail não mudam por aqui: é o e-mail que identifica '
                  'quem responde pela imobiliária e aprova os corretores dela. '
                  'Se algum dos dois estiver errado, fale com o suporte.',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxl),

            AnimatedGradientButton(
              label: 'Salvar alterações',
              icon: Icons.check_circle_outline_rounded,
              isLoading: _salvando,
              onTap: _salvar,
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
      padding: const EdgeInsets.all(AppSpacing.lg + 2),
      decoration: BoxDecoration(
        color: isDark ? superficieEscura : superficieClara,
        borderRadius: BorderRadius.circular(AppRadius.lg + 2),
        boxShadow: AppShadows.nivel1(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  gradient: gradientePrincipal,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Icon(icone, color: Colors.white, size: 18),
              ),
              const SizedBox(width: AppSpacing.sm + 2),
              Text(
                titulo,
                style: AppTextStyles.bodyBold.copyWith(
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          ...filhos,
        ],
      ),
    );
  }

  Widget _campo({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isDark,
    String? dica,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
    int linhas = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: linhas > 1 ? TextInputType.multiline : keyboardType,
      maxLines: linhas,
      inputFormatters: formatters,
      validator: validator,
      onChanged: onChanged,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      decoration: decoracaoCampo(
        isDark: isDark,
        rotulo: label,
        dica: dica,
        icone: icon,
        // pilula so fica boa em campo de uma linha -- ver decoracaoCampo
        raio: linhas > 1 ? AppRadius.md : AppRadius.md + 6,
      ),
    );
  }

  // campo somente leitura, com cadeado. readOnly em vez de enabled:false pra
  // continuar dando pra selecionar e copiar o texto (mesma escolha da tela de
  // perfil)
  Widget _campoTravado({
    required bool isDark,
    required String label,
    required IconData icon,
    required String valor,
  }) {
    return TextFormField(
      initialValue: valor,
      readOnly: true,
      style: TextStyle(color: isDark ? Colors.white54 : Colors.black54),
      decoration: decoracaoCampo(
        isDark: isDark,
        rotulo: label,
        icone: icon,
        sufixo: Icon(
          Icons.lock_outline_rounded,
          size: 19,
          color: isDark ? Colors.white38 : Colors.grey,
        ),
      ),
    );
  }

  Widget _avisoBloqueado(bool isDark, String texto) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.lock_outline_rounded,
          size: 14,
          color: isDark ? Colors.white38 : Colors.grey,
        ),
        const SizedBox(width: AppSpacing.xs + 2),
        Expanded(
          child: Text(
            texto,
            style: AppTextStyles.caption.copyWith(
              color: isDark ? Colors.white38 : Colors.grey,
            ),
          ),
        ),
      ],
    );
  }
}
