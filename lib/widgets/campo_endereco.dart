import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import '../main.dart';
import '../models/endereco.dart';
import '../models/imovel.dart' show estadosBrasileiros;
import '../services/cep_service.dart';

// controllers + mascara de UM bloco de endereco -- cada endereco (pessoal,
// do responsavel, da empresa...) usa a sua propria instancia, descartada
// junto com a tela via dispose()
class EnderecoControllers {
  final cep = TextEditingController();
  final logradouro = TextEditingController();
  final numero = TextEditingController();
  final complemento = TextEditingController();
  final bairro = TextEditingController();
  final cidade = TextEditingController();
  String? estado;

  final mascaraCep = MaskTextInputFormatter(mask: '#####-###', filter: {'#': RegExp(r'[0-9]')});

  void preencher(Endereco endereco) {
    cep.text = endereco.cep;
    logradouro.text = endereco.logradouro;
    numero.text = endereco.numero;
    complemento.text = endereco.complemento;
    bairro.text = endereco.bairro;
    cidade.text = endereco.cidade;
    estado = endereco.estado.isNotEmpty ? endereco.estado : null;
  }

  Endereco get valor => Endereco(
        cep: cep.text.trim(),
        logradouro: logradouro.text.trim(),
        numero: numero.text.trim(),
        complemento: complemento.text.trim(),
        bairro: bairro.text.trim(),
        cidade: cidade.text.trim(),
        estado: estado ?? '',
      );

  void dispose() {
    cep.dispose();
    logradouro.dispose();
    numero.dispose();
    complemento.dispose();
    bairro.dispose();
    cidade.dispose();
  }
}

// bloco de campos de endereco estruturado (CEP, logradouro, numero,
// complemento, bairro, cidade, estado) -- reaproveitado em qualquer fluxo
// que precise de endereco completo, pra nao duplicar essa UI em cada tela
class CampoEndereco extends StatefulWidget {
  final EnderecoControllers controllers;
  final bool isDark;

  const CampoEndereco({super.key, required this.controllers, required this.isDark});

  @override
  State<CampoEndereco> createState() => _CampoEnderecoState();
}

class _CampoEnderecoState extends State<CampoEndereco> {
  final _numeroFocus = FocusNode();
  bool _buscandoCep = false;
  String? _erroCep;
  // ultimo CEP consultado -- evita repetir a busca quando o campo e redesenhado
  // ou o usuario apaga e redigita o mesmo numero
  String _ultimoCepBuscado = '';

  @override
  void dispose() {
    _numeroFocus.dispose();
    super.dispose();
  }

  // dispara sozinho quando o CEP fica com 8 digitos. So sobrescreve o que a
  // API devolveu preenchido: CEP geral de cidade pequena vem sem rua/bairro,
  // e ai o que o usuario ja tinha digitado nesses campos fica
  Future<void> _aoMudarCep(String valor) async {
    final digitos = valor.replaceAll(RegExp(r'\D'), '');
    if (digitos.length != 8) {
      _ultimoCepBuscado = '';
      if (_erroCep != null) setState(() => _erroCep = null);
      return;
    }
    if (digitos == _ultimoCepBuscado) return;
    _ultimoCepBuscado = digitos;

    setState(() {
      _buscandoCep = true;
      _erroCep = null;
    });
    try {
      final endereco = await CepService.instance.buscar(digitos);
      // o usuario pode ter mudado o CEP enquanto a resposta nao chegava
      if (!mounted || digitos != _ultimoCepBuscado) return;
      if (endereco == null) {
        setState(() => _erroCep = 'CEP não encontrado');
        return;
      }
      final c = widget.controllers;
      setState(() {
        if (endereco.logradouro.isNotEmpty) c.logradouro.text = endereco.logradouro;
        if (endereco.bairro.isNotEmpty) c.bairro.text = endereco.bairro;
        if (endereco.cidade.isNotEmpty) c.cidade.text = endereco.cidade;
        if (estadosBrasileiros.contains(endereco.estado)) c.estado = endereco.estado;
      });
      _numeroFocus.requestFocus();
    } catch (_) {
      // sem internet ou ViaCEP fora do ar: o usuario preenche na mao
      if (mounted && digitos == _ultimoCepBuscado) {
        _ultimoCepBuscado = '';
        setState(() => _erroCep = 'Não foi possível buscar o CEP. Preencha o endereço manualmente.');
      }
    } finally {
      if (mounted) setState(() => _buscandoCep = false);
    }
  }

  Widget _campo({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    FocusNode? focusNode,
    TextInputType? keyboardType,
    List<TextInputFormatter>? formatters,
    String? Function(String?)? validator,
    ValueChanged<String>? onChanged,
    Widget? suffixIcon,
    String? errorText,
  }) {
    final isDark = widget.isDark;
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      validator: validator,
      onChanged: onChanged,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: isDark ? Colors.white54 : Colors.grey.shade600),
        prefixIcon: Icon(icon, color: isDark ? Colors.white54 : corPrimaria),
        suffixIcon: suffixIcon,
        errorText: errorText,
        filled: true,
        fillColor: isDark ? Colors.white.withAlpha(8) : Colors.grey.withAlpha(15),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controllers;
    final isDark = widget.isDark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _campo(
          controller: c.cep,
          label: 'CEP',
          icon: Icons.markunread_mailbox_outlined,
          keyboardType: TextInputType.number,
          formatters: [c.mascaraCep],
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o CEP' : null,
          onChanged: _aoMudarCep,
          errorText: _erroCep,
          suffixIcon: _buscandoCep
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: corPrimaria),
                  ),
                )
              : null,
        ),
        const SizedBox(height: 14),
        _campo(
          controller: c.logradouro,
          label: 'Logradouro (rua/avenida)',
          icon: Icons.signpost_outlined,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o logradouro' : null,
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _campo(
                controller: c.numero,
                focusNode: _numeroFocus,
                label: 'Número',
                icon: Icons.pin_outlined,
                keyboardType: TextInputType.number,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o número' : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _campo(
                controller: c.complemento,
                label: 'Complemento (opcional)',
                icon: Icons.apartment_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _campo(
          controller: c.bairro,
          label: 'Bairro',
          icon: Icons.holiday_village_outlined,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o bairro' : null,
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: _campo(
                controller: c.cidade,
                label: 'Cidade',
                icon: Icons.location_city_rounded,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe a cidade' : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<String>(
                // initialValue so e lido na criacao do campo -- a chave recria
                // o dropdown quando o CEP preenche a UF sozinho
                key: ValueKey(c.estado),
                initialValue: c.estado,
                isExpanded: true,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                dropdownColor: isDark ? superficieEscura : superficieClara,
                decoration: InputDecoration(
                  labelText: 'UF',
                  labelStyle: TextStyle(color: isDark ? Colors.white54 : Colors.grey.shade600),
                  filled: true,
                  fillColor: isDark ? Colors.white.withAlpha(8) : Colors.grey.withAlpha(15),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
                items: estadosBrasileiros.map((uf) => DropdownMenuItem(value: uf, child: Text(uf))).toList(),
                onChanged: (val) => setState(() => c.estado = val),
                validator: (v) => v == null ? 'UF' : null,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
