import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models/filtro_state.dart';
import '../models/imovel.dart';
import '../utils/icones_tag.dart';
import '../utils/moeda.dart';

/// Rascunho local: fechar a folha descarta as alterações, aplicar as confirma.
class FiltrosMapaSheet extends StatefulWidget {
  final FiltrosMapa inicial;
  final int Function(FiltrosMapa) contarImoveis;
  final bool Function() proximidadeDisponivel;
  final Listenable atualizacoes;

  const FiltrosMapaSheet({
    super.key,
    required this.inicial,
    required this.contarImoveis,
    required this.proximidadeDisponivel,
    required this.atualizacoes,
  });

  @override
  State<FiltrosMapaSheet> createState() => _FiltrosMapaSheetState();
}

class _FiltrosMapaSheetState extends State<FiltrosMapaSheet> {
  late final _minimo = TextEditingController(
    text: _textoPreco(widget.inicial.precoMinimo),
  );
  late final _maximo = TextEditingController(
    text: _textoPreco(widget.inicial.precoMaximo),
  );
  late final _tipos = {...widget.inicial.tipos};
  late final _tags = {...widget.inicial.tags};
  late final _contas = {...widget.inicial.contas};
  late final _localidades = {...widget.inicial.localidades};
  late final _ocultas = {...widget.inicial.categoriasOcultas};
  int _aba = 0;

  static String _textoPreco(double? valor) => valor?.toInt().toString() ?? '';
  double? _lerPreco(TextEditingController campo) {
    final valor = double.tryParse(campo.text);
    return valor == null || valor <= 0 ? null : valor;
  }

  FiltrosMapa get _rascunho => FiltrosMapa(
    precoMinimo: _lerPreco(_minimo),
    precoMaximo: _lerPreco(_maximo),
    tipos: _tipos,
    tags: _tags,
    contas: _contas,
    localidades: _localidades,
    categoriasOcultas: _ocultas,
  );

  @override
  void dispose() {
    _minimo.dispose();
    _maximo.dispose();
    super.dispose();
  }

  void _alternar(Set<String> grupo, String valor) => setState(() {
    if (!grupo.remove(valor)) grupo.add(valor);
  });

  void _limpar() => setState(() {
    _minimo.clear();
    _maximo.clear();
    _tipos.clear();
    _tags.clear();
    _contas.clear();
    _localidades.clear();
    _ocultas.clear();
  });

  bool get _escuro => Theme.of(context).brightness == Brightness.dark;
  Color get _destaque => _escuro ? const Color(0xFF65B0FF) : corPrimaria;
  Color get _secundaria =>
      _escuro ? const Color(0xFFA5B6C8) : const Color(0xFF59697A);

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.atualizacoes,
    builder: (context, _) {
      final filtro = _rascunho;
      final encontrados = widget.contarImoveis(filtro);
      return LayoutBuilder(
        builder: (context, constraints) {
          final teclado = MediaQuery.viewInsetsOf(context).bottom;
          return Padding(
            padding: EdgeInsets.only(bottom: teclado),
            child: SizedBox(
              height: (constraints.maxHeight - teclado) * .94,
              child: Material(
                color: _escuro ? corFundoEscuro : const Color(0xFFF4F7FB),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                clipBehavior: Clip.antiAlias,
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
                        child: Column(
                          children: [
                            Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: _secundaria.withAlpha(80),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(Icons.tune_rounded, color: _destaque),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Filtrar busca',
                                    style: TextStyle(
                                      fontSize: 21,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: filtro.quantidadeAtiva > 0
                                      ? _limpar
                                      : null,
                                  child: const Text('Limpar'),
                                ),
                                IconButton(
                                  tooltip: 'Fechar filtros',
                                  onPressed: () => Navigator.pop(context),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: SegmentedButton<int>(
                                segments: [
                                  ButtonSegment(
                                    value: 0,
                                    icon: const Icon(Icons.home_outlined),
                                    label: Text(
                                      'Imóveis${filtro.quantidadeImovel > 0 ? ' · ${filtro.quantidadeImovel}' : ''}',
                                    ),
                                  ),
                                  const ButtonSegment(
                                    value: 1,
                                    icon: Icon(Icons.layers_outlined),
                                    label: Text('No mapa'),
                                  ),
                                ],
                                selected: {_aba},
                                showSelectedIcon: false,
                                onSelectionChanged: (valor) {
                                  FocusScope.of(context).unfocus();
                                  setState(() => _aba = valor.first);
                                },
                                style: SegmentedButton.styleFrom(
                                  selectedBackgroundColor: corPrimaria,
                                  selectedForegroundColor: Colors.white,
                                  foregroundColor: _secundaria,
                                  side: BorderSide(
                                    color: _secundaria.withAlpha(55),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: IndexedStack(
                          index: _aba,
                          children: [
                            _conteudoImoveis(filtro),
                            _conteudoMapa(filtro),
                          ],
                        ),
                      ),
                      _rodape(filtro, encontrados),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );

  Widget _conteudoImoveis(FiltrosMapa filtro) => ListView(
    key: const PageStorageKey('filtros-imoveis'),
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
    children: [
      _descricao('Encontre uma moradia do seu jeito.'),
      if (!filtro.mostraCategoria(categoriaMoradia))
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextButton.icon(
            icon: const Icon(Icons.visibility_off_outlined),
            label: const Text('Imóveis ocultos. Mostrar no mapa'),
            onPressed: () => setState(() => _ocultas.remove(categoriaMoradia)),
          ),
        ),
      _secao(
        titulo: 'Valor do aluguel',
        icone: Icons.payments_outlined,
        resumo: _resumoPreco(filtro),
        aberta: true,
        manterEstado: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _campoPreco(_minimo, 'Mínimo', 'preco-minimo')),
                const SizedBox(width: 12),
                Expanded(child: _campoPreco(_maximo, 'Máximo', 'preco-maximo')),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final faixa in const <(double?, double?, String)>[
                  (null, 600, 'Até R\$ 600'),
                  (600, 1000, 'R\$ 600-1.000'),
                  (1000, 1500, 'R\$ 1.000-1.500'),
                  (1500, null, 'R\$ 1.500 ou mais'),
                ])
                  ChoiceChip(
                    label: Text(faixa.$3),
                    selected:
                        filtro.precoMinimo == faixa.$1 &&
                        filtro.precoMaximo == faixa.$2,
                    onSelected: (ativo) => setState(() {
                      _minimo.text = ativo ? _textoPreco(faixa.$1) : '';
                      _maximo.text = ativo ? _textoPreco(faixa.$2) : '';
                    }),
                  ),
              ],
            ),
            if (_lerPreco(_minimo) != null &&
                _lerPreco(_maximo) != null &&
                _lerPreco(_minimo)! > _lerPreco(_maximo)!)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Usaremos a faixa em ordem: ${_resumoPreco(filtro)}.',
                  style: TextStyle(color: _secundaria, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
      _secao(
        titulo: 'Tipo de imóvel',
        icone: Icons.home_work_outlined,
        resumo: _tipos.isEmpty
            ? 'Casa, apartamento, república…'
            : _tipos.join(' · '),
        quantidade: _tipos.length,
        child: _opcoes(tiposImovelDisponiveis, _tipos, iconeDaTag),
      ),
      _secao(
        titulo: 'Características',
        icone: Icons.chair_outlined,
        resumo: _tags.where(tagsComodidade.contains).isEmpty
            ? 'Mobiliado, garagem, suíte e elevador'
            : _tags.where(tagsComodidade.contains).join(' · '),
        quantidade: _tags.where(tagsComodidade.contains).length,
        child: _opcoes(tagsComodidade, _tags, iconeDaTag),
      ),
      _secao(
        titulo: 'Contas inclusas',
        icone: Icons.receipt_long_outlined,
        resumo: _contas.isEmpty
            ? 'O que já vem no valor do aluguel'
            : _contas.join(' · '),
        quantidade: _contas.length,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _descricao('O imóvel deve incluir todas as contas selecionadas.'),
            _opcoes(opcoesContasInclusas, _contas, iconeDaConta),
          ],
        ),
      ),
      _secao(
        titulo: 'Perto do imóvel',
        icone: Icons.near_me_outlined,
        resumo: _localidades.isEmpty
            ? 'Faculdade, mercado, farmácia e mais'
            : opcoesLocalidade
                  .where((o) => _localidades.contains(o.id))
                  .map((o) => o.rotulo)
                  .join(' · '),
        quantidade: _localidades.length,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _descricao(
              'Encontre imóveis perto de todos os locais escolhidos. Distâncias em linha reta.',
            ),
            for (final opcao in opcoesLocalidade)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(opcao.rotulo, style: const TextStyle(fontSize: 14)),
                subtitle: Text('Até ${_distancia(opcao.raio)}'),
                secondary: Icon(opcao.icone, color: _secundaria, size: 21),
                value: _localidades.contains(opcao.id),
                onChanged:
                    opcao.id == localidadeFaculdade ||
                        widget.proximidadeDisponivel() ||
                        _localidades.contains(opcao.id)
                    ? (_) => _alternar(_localidades, opcao.id)
                    : null,
                activeColor: corPrimaria,
                dense: true,
              ),
            if (!widget.proximidadeDisponivel())
              _descricao(
                'Ainda não há dados de estabelecimentos próximos aos imóveis. A opção Faculdade continua disponível.',
              ),
          ],
        ),
      ),
      _secao(
        titulo: 'Perfil da moradia',
        icone: Icons.people_outline_rounded,
        resumo: _tags.where(tagsPreferenciaGenero.contains).isEmpty
            ? 'Sem preferência'
            : _tags.where(tagsPreferenciaGenero.contains).join(' · '),
        quantidade: _tags.where(tagsPreferenciaGenero.contains).length,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _descricao(
              'Ao selecionar os dois, aceitamos qualquer um dos perfis.',
            ),
            _opcoes(tagsPreferenciaGenero, _tags, iconeDaTag),
          ],
        ),
      ),
    ],
  );

  Widget _conteudoMapa(FiltrosMapa filtro) => ListView(
    key: const PageStorageKey('filtros-camadas'),
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
    children: [
      _descricao(
        'Escolha o que aparece no mapa. Isso não muda as características dos imóveis.',
      ),
      Row(
        children: [
          const Expanded(
            child: Text(
              'Exibir no mapa',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          TextButton(
            onPressed: () => setState(_ocultas.clear),
            child: const Text('Mostrar tudo'),
          ),
        ],
      ),
      Container(
        decoration: _decoracaoCard,
        child: Column(
          children: [
            for (final opcao in opcoesCategoria)
              SwitchListTile(
                key: ValueKey('categoria-${opcao.id}'),
                title: Text(
                  opcao.rotulo,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: opcao.id == categoriaMoradia
                    ? const Text('Usa os filtros da aba Imóveis')
                    : null,
                secondary: Icon(
                  opcao.icone,
                  color: filtro.mostraCategoria(opcao.id)
                      ? _destaque
                      : _secundaria,
                  size: 22,
                ),
                value: filtro.mostraCategoria(opcao.id),
                onChanged: (_) => _alternar(_ocultas, opcao.id),
                activeThumbColor: Colors.white,
                activeTrackColor: corPrimaria,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 2,
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _descricao(
        'Quer morar perto de um mercado ou farmácia? Use “Perto do imóvel” na aba Imóveis.',
      ),
    ],
  );

  BoxDecoration get _decoracaoCard => BoxDecoration(
    color: _escuro ? corCardEscuro : Colors.white,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: _secundaria.withAlpha(28)),
  );

  Widget _secao({
    required String titulo,
    required IconData icone,
    required String resumo,
    required Widget child,
    bool aberta = false,
    int quantidade = 0,
    bool manterEstado = false,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    decoration: _decoracaoCard,
    child: ExpansionTile(
      key: PageStorageKey(titulo),
      initiallyExpanded: aberta || quantidade > 0,
      maintainState: manterEstado,
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      leading: Icon(icone, color: _destaque, size: 22),
      title: Text(
        '$titulo${quantidade > 0 ? ' · $quantidade' : ''}',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        resumo,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: _secundaria),
      ),
      children: [Align(alignment: Alignment.centerLeft, child: child)],
    ),
  );

  Widget _descricao(String texto) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      texto,
      style: TextStyle(color: _secundaria, fontSize: 13, height: 1.4),
    ),
  );

  Widget _opcoes(
    List<String> opcoes,
    Set<String> selecionadas,
    IconData Function(String) icone,
  ) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      for (final opcao in opcoes)
        FilterChip(
          label: Text(opcao),
          avatar: Icon(icone(opcao), size: 17),
          selected: selecionadas.contains(opcao),
          onSelected: (_) => _alternar(selecionadas, opcao),
          selectedColor: corPrimaria.withAlpha(_escuro ? 150 : 30),
          checkmarkColor: _destaque,
        ),
    ],
  );

  Widget _campoPreco(
    TextEditingController controller,
    String rotulo,
    String chave,
  ) => TextField(
    key: ValueKey(chave),
    controller: controller,
    keyboardType: TextInputType.number,
    textInputAction: TextInputAction.done,
    inputFormatters: [
      FilteringTextInputFormatter.digitsOnly,
      LengthLimitingTextInputFormatter(8),
    ],
    onChanged: (_) => setState(() {}),
    onSubmitted: (_) => FocusScope.of(context).unfocus(),
    decoration: InputDecoration(
      labelText: rotulo,
      hintText: 'Sem limite',
      prefixText: 'R\$ ',
      filled: true,
      fillColor: _escuro ? corFundoEscuro : const Color(0xFFF4F7FB),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    ),
  );

  String _resumoPreco(FiltrosMapa filtro) {
    final min = filtro.precoMinimo;
    final max = filtro.precoMaximo;
    String valor(double v) => formatarPreco(v).replaceFirst(',00', '');
    if (min != null && max != null) return '${valor(min)} a ${valor(max)}';
    if (min != null) return 'A partir de ${valor(min)}';
    if (max != null) return 'Até ${valor(max)}';
    return 'Sem limite de valor';
  }

  String _distancia(int metros) => metros < 1000
      ? '$metros m'
      : '${(metros / 1000).toString().replaceFirst('.0', '').replaceFirst('.', ',')} km';

  Widget _rodape(FiltrosMapa filtro, int encontrados) {
    final visiveis = opcoesCategoria
        .where((o) => filtro.mostraCategoria(o.id))
        .length;
    final resumo = _aba == 1
        ? '$visiveis de ${opcoesCategoria.length} categorias visíveis'
        : !filtro.mostraCategoria(categoriaMoradia)
        ? 'Imóveis ocultos no mapa'
        : encontrados == 0
        ? 'Nenhum imóvel com esses filtros'
        : '$encontrados ${encontrados == 1 ? 'imóvel encontrado' : 'imóveis encontrados'}';
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      decoration: BoxDecoration(
        color: _escuro ? corCardEscuro : Colors.white,
        border: Border(top: BorderSide(color: _secundaria.withAlpha(30))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            resumo,
            textAlign: TextAlign.center,
            style: TextStyle(color: _secundaria, fontSize: 13),
          ),
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: gradientePrincipal,
              borderRadius: BorderRadius.circular(14),
            ),
            child: FilledButton.icon(
              key: const ValueKey('aplicar-filtros'),
              onPressed: () => Navigator.pop(context, filtro),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.map_outlined, size: 20),
              label: Text(
                'Aplicar filtros${filtro.quantidadeAtiva > 0 ? ' (${filtro.quantidadeAtiva})' : ''}',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
