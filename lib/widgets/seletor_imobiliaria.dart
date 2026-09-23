import 'package:flutter/material.dart';
import '../main.dart';
import '../models/imobiliaria.dart';
import '../services/imobiliaria_service.dart';
import '../utils/moderacao.dart';
import 'campo_formulario.dart';

// Escolha da imobiliaria no cadastro do corretor de empresa.
//
// Antes o corretor digitava nome/CNPJ/endereco e o app criava a imobiliaria na
// hora: duas pessoas da MESMA empresa escrevendo o nome de um jeito diferente
// viravam duas imobiliarias, e nenhum vinculo passava por ninguem. Aqui ele
// escolhe uma que ja existe; "Cadastrar nova" continua existindo porque o
// primeiro corretor de cada imobiliaria nao tem o que escolher.
class SeletorImobiliaria extends StatelessWidget {
  final Imobiliaria? selecionada;
  final bool isDark;

  // true quando a pessoa optou por cadastrar uma imobiliaria nova -- o
  // formulario de dados da empresa aparece no lugar da selecao
  final bool cadastrandoNova;

  final ValueChanged<Imobiliaria> onSelecionar;
  final VoidCallback onCadastrarNova;
  final VoidCallback onLimpar;

  const SeletorImobiliaria({
    super.key,
    required this.selecionada,
    required this.isDark,
    required this.cadastrandoNova,
    required this.onSelecionar,
    required this.onCadastrarNova,
    required this.onLimpar,
  });

  Future<void> _abrirBusca(BuildContext context) async {
    final escolhida = await showModalBottomSheet<Imobiliaria>(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? superficieEscura : superficieClara,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _FolhaDeBusca(isDark: isDark, aoCadastrarNova: onCadastrarNova),
    );
    if (escolhida != null) onSelecionar(escolhida);
  }

  @override
  Widget build(BuildContext context) {
    if (cadastrandoNova) {
      return _LinhaEscolhida(
        isDark: isDark,
        icone: Icons.add_business_rounded,
        titulo: 'Cadastrar uma imobiliária nova',
        detalhe: 'Preencha os dados da empresa abaixo.',
        onTrocar: onLimpar,
      );
    }

    final imobiliaria = selecionada;
    if (imobiliaria != null) {
      return _LinhaEscolhida(
        isDark: isDark,
        icone: Icons.apartment_rounded,
        titulo: imobiliaria.nome,
        detalhe: imobiliaria.endereco.isNotEmpty
            ? imobiliaria.endereco
            : 'CNPJ ${imobiliaria.cnpj}',
        onTrocar: onLimpar,
      );
    }

    return GestureDetector(
      onTap: () => _abrirBusca(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withAlpha(8) : Colors.grey.withAlpha(15),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: corAtencao.withAlpha(90)),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: isDark ? Colors.white54 : corPrimaria),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Selecione a imobiliária',
                style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: isDark ? Colors.white38 : Colors.grey),
          ],
        ),
      ),
    );
  }
}

class _LinhaEscolhida extends StatelessWidget {
  final bool isDark;
  final IconData icone;
  final String titulo;
  final String detalhe;
  final VoidCallback onTrocar;

  const _LinhaEscolhida({
    required this.isDark,
    required this.icone,
    required this.titulo,
    required this.detalhe,
    required this.onTrocar,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(8) : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: corPrimaria.withAlpha(60)),
      ),
      child: Row(
        children: [
          Icon(icone, color: corPrimaria),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titulo,
                  style: AppTextStyles.bodyBold.copyWith(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detalhe,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: isDark ? Colors.white38 : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onTrocar, child: const Text('Trocar')),
        ],
      ),
    );
  }
}

// lista as imobiliarias cadastradas com filtro por nome/CNPJ. O filtro roda na
// memoria: sao poucas, e o Firestore so sabe filtrar por prefixo
class _FolhaDeBusca extends StatefulWidget {
  final bool isDark;
  final VoidCallback aoCadastrarNova;

  const _FolhaDeBusca({required this.isDark, required this.aoCadastrarNova});

  @override
  State<_FolhaDeBusca> createState() => _FolhaDeBuscaState();
}

class _FolhaDeBuscaState extends State<_FolhaDeBusca> {
  final _buscaController = TextEditingController();
  late final Future<List<Imobiliaria>> _todas;

  @override
  void initState() {
    super.initState();
    _todas = ImobiliariaService.instance.listarTodas();
    _buscaController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  List<Imobiliaria> _filtrar(List<Imobiliaria> todas) {
    final termo = normalizarNome(_buscaController.text);
    if (termo.isEmpty) return todas;
    final digitos = termo.replaceAll(RegExp(r'\D'), '');
    return todas.where((i) {
      final porNome = i.nomeBusca.isNotEmpty ? i.nomeBusca : normalizarNome(i.nome);
      return porNome.contains(termo) ||
          (digitos.isNotEmpty && i.cnpjBusca.contains(digitos));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    // a folha ocupa no maximo 80% da tela e o teclado empurra o conteudo
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: TextField(
                controller: _buscaController,
                autofocus: true,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: decoracaoCampo(
                  isDark: isDark,
                  rotulo: 'Buscar por nome ou CNPJ',
                  icone: Icons.search_rounded,
                ),
              ),
            ),
            Flexible(
              child: FutureBuilder<List<Imobiliaria>>(
                future: _todas,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator(color: corPrimaria)),
                    );
                  }
                  final lista = _filtrar(snap.data ?? const []);
                  if (lista.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        snap.hasError
                            ? 'Não foi possível carregar as imobiliárias agora.'
                            : 'Nenhuma imobiliária encontrada com esse nome.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: lista.length,
                    itemBuilder: (context, i) => _itemImobiliaria(lista[i], isDark),
                  );
                },
              ),
            ),
            const Divider(height: 1),
            // saida pro primeiro corretor de uma imobiliaria que ainda nao
            // esta no app -- sem isso ele nao teria como concluir o cadastro
            ListTile(
              leading: const Icon(Icons.add_business_rounded, color: corPrimaria),
              title: Text(
                'Não encontrei. Cadastrar nova',
                style: AppTextStyles.bodyBold.copyWith(
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              subtitle: Text(
                'Você preenche os dados da empresa',
                style: AppTextStyles.caption.copyWith(
                  color: isDark ? Colors.white38 : Colors.grey,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                widget.aoCadastrarNova();
              },
            ),
            SizedBox(height: MediaQuery.viewPaddingOf(context).bottom + 8),
          ],
        ),
      ),
    );
  }

  Widget _itemImobiliaria(Imobiliaria imobiliaria, bool isDark) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: corPrimaria.withAlpha(30),
        child: const Icon(Icons.apartment_rounded, color: corPrimaria, size: 20),
      ),
      title: Text(
        imobiliaria.nome,
        style: AppTextStyles.bodyBold.copyWith(
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      subtitle: Text(
        imobiliaria.endereco.isNotEmpty ? imobiliaria.endereco : 'CNPJ ${imobiliaria.cnpj}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTextStyles.caption.copyWith(
          color: isDark ? Colors.white38 : Colors.grey,
        ),
      ),
      onTap: () => Navigator.pop(context, imobiliaria),
    );
  }
}
