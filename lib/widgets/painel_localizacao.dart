import 'package:flutter/material.dart';

import '../main.dart';
import '../services/localizacao_service.dart';
import 'pressionavel.dart';

// pedido de localizacao com o motivo na frente.
//
// Aparece quando a pessoa toca em algo que depende de onde ela esta -- nunca
// na abertura do app. Dois motivos: o dialogo do Android nao diz PRA QUE o
// app quer a localizacao, e quem recusa duas vezes nao ve mais o dialogo
// nenhuma vez (vira negadaParaSempre), entao gastar a primeira pergunta antes
// de a pessoa entender o que ganha e desperdicar a unica chance.
//
// Devolve true quando a permissao ficou valendo.
Future<bool> pedirLocalizacaoComExplicacao(BuildContext context) async {
  final servico = LocalizacaoService.instance;

  // ja pode? nao incomoda ninguem
  if (servico.permitida) return true;

  final bool isDark = Theme.of(context).brightness == Brightness.dark;
  final resultado = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: isDark ? superficieEscura : superficieClara,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => const _PainelPermissao(),
  );
  return resultado ?? false;
}

class _PainelPermissao extends StatefulWidget {
  const _PainelPermissao();

  @override
  State<_PainelPermissao> createState() => _PainelPermissaoState();
}

class _PainelPermissaoState extends State<_PainelPermissao> {
  bool _pedindo = false;

  Future<void> _permitir() async {
    final servico = LocalizacaoService.instance;
    setState(() => _pedindo = true);

    // recusa definitiva nao abre mais o dialogo do sistema: o unico caminho
    // de volta sao os ajustes do aparelho
    if (!servico.podeTentarDeNovo ||
        servico.estado.value == EstadoLocalizacao.servicoDesligado) {
      await servico.abrirAjustes();
      if (!mounted) return;
      setState(() => _pedindo = false);
      // o estado real so da pra saber quando a pessoa voltar dos ajustes
      Navigator.pop(context, false);
      return;
    }

    final novo = await servico.pedir();
    if (!mounted) return;
    setState(() => _pedindo = false);
    Navigator.pop(context, novo == EstadoLocalizacao.permitida);
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final servico = LocalizacaoService.instance;
    final estado = servico.estado.value;

    final bool paraAjustes = estado == EstadoLocalizacao.negadaParaSempre ||
        estado == EstadoLocalizacao.servicoDesligado;

    final String titulo = estado == EstadoLocalizacao.servicoDesligado
        ? 'Ligue a localização do aparelho'
        : 'Usar sua localização?';

    final String explicacao = estado == EstadoLocalizacao.servicoDesligado
        ? 'A permissão está concedida, mas a localização do aparelho está desligada. Ligue para usar o mapa a partir de onde você está.'
        : 'Com a localização ligada o app mostra onde você está no mapa e calcula rotas a partir daí, em tempo real.';

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.xl),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
            ),

            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    gradient: gradientePrincipal,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    boxShadow: AppShadows.marca(forca: 0.4),
                  ),
                  child: const Icon(Icons.my_location_rounded,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    titulo,
                    style: AppTextStyles.heading3.copyWith(
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            Text(
              explicacao,
              style: AppTextStyles.body.copyWith(
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            _Item(
                isDark: isDark,
                icone: Icons.person_pin_circle_rounded,
                texto: 'Ver sua posição no mapa'),
            _Item(
                isDark: isDark,
                icone: Icons.alt_route_rounded,
                texto: 'Traçar rotas até moradias e eventos'),
            _Item(
                isDark: isDark,
                icone: Icons.navigation_rounded,
                texto: 'Usar o modo "Ir", com a seta acompanhando você'),

            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withAlpha(10) : Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withAlpha(16)
                      : corPrimaria.withAlpha(20),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_outline_rounded,
                      size: 18, color: isDark ? Colors.white38 : Colors.black38),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      // dito sem rodeio: o app continua inteiro sem isso
                      'Sem permissão você continua usando o app normalmente: só não dá para partir da sua posição.',
                      style: AppTextStyles.caption.copyWith(
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            Pressionavel(
              onTap: _pedindo ? null : _permitir,
              child: Container(
                height: 54,
                decoration: BoxDecoration(
                  gradient: gradientePrincipal,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: AppShadows.marca(forca: 0.6),
                ),
                child: Center(
                  child: _pedindo
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          paraAjustes ? 'Abrir configurações' : 'Permitir',
                          style: AppTextStyles.bodyBold
                              .copyWith(color: Colors.white, fontSize: 16),
                        ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Center(
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'Agora não',
                  style: AppTextStyles.bodyBold.copyWith(
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Item extends StatelessWidget {
  final bool isDark;
  final IconData icone;
  final String texto;

  const _Item({required this.isDark, required this.icone, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm + 2),
      child: Row(
        children: [
          Icon(icone, size: 19, color: isDark ? Colors.white54 : corPrimaria),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              texto,
              style: AppTextStyles.caption.copyWith(
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
