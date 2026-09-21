import 'package:flutter/material.dart';

import '../main.dart';

// cabecalho padrao das telas de aba (Resumo, Chat, Painel...).
//
// Existe pra o padrao ficar definido em UM lugar. Antes cada tela repetia o
// proprio Container com cor, sombra e espacamento escritos na mao, e foi
// assim que elas foram divergindo: umas com branco puro, outras com
// corSuperficieEscura, sombras de blur diferente e paddings de 12/16/20
// misturados. Mudanca de identidade agora e feita aqui e vale em todas.
//
// O gradiente e o mesmo do cabecalho do Resumo: superficie do app com um fio
// do azul da marca no pe -- nao branco puro, que destoa do conteudo.
class CabecalhoTela extends StatelessWidget {
  final String titulo;

  // linha de apoio abaixo do titulo (ex: contagem, boas-vindas)
  final String? subtitulo;

  // acao a direita do titulo -- normalmente um icone em pilula
  final Widget? acao;

  // conteudo extra abaixo do titulo, como um campo de busca
  final Widget? rodape;

  const CabecalhoTela({
    super.key,
    required this.titulo,
    this.subtitulo,
    this.acao,
    this.rodape,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final double recuoTopo = MediaQuery.of(context).padding.top;

    return Container(
      padding: EdgeInsets.only(
        // em tela cheia padding.top e 0; o minimo evita colar na borda
        top: (recuoTopo > 0 ? recuoTopo : 8) + AppSpacing.md,
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        bottom: AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.55, 1],
          colors: isDark
              ? [
                  Color.alphaBlend(Colors.white.withAlpha(15), superficieEscura),
                  superficieEscura.withAlpha(250),
                  Color.alphaBlend(corPrimaria.withAlpha(20), superficieEscura),
                ]
              : [
                  superficieClara,
                  superficieClara,
                  Color.alphaBlend(corPrimaria.withAlpha(8), superficieClara),
                ],
        ),
        boxShadow: AppShadows.nivel2(isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: AppTextStyles.heading2.copyWith(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (subtitulo != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        subtitulo!,
                        style: AppTextStyles.caption.copyWith(
                          color: isDark ? Colors.white38 : Colors.grey,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ?acao,
            ],
          ),
          if (rodape != null) ...[
            const SizedBox(height: AppSpacing.lg),
            rodape!,
          ],
        ],
      ),
    );
  }
}

// campo de busca no padrao do app -- mesma pilula usada no mapa, pra busca
// ter a mesma cara em qualquer tela
class CampoBuscaPadrao extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String dica;
  final VoidCallback? aoLimpar;

  const CampoBuscaPadrao({
    super.key,
    required this.controller,
    required this.dica,
    this.focusNode,
    this.aoLimpar,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool temTexto = controller.text.trim().isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(14) : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md + 6),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(18) : corPrimaria.withAlpha(22),
        ),
        boxShadow: AppShadows.nivel1(isDark),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        // sem isso o InputDecoration alinha pela baseline e o texto sobe
        // alguns pixels quando ha prefixIcon e nenhum suffixIcon
        textAlignVertical: TextAlignVertical.center,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15),
        decoration: InputDecoration(
          hintText: dica,
          hintStyle: TextStyle(
            color: isDark ? Colors.white38 : Colors.black38,
            fontWeight: FontWeight.w500,
          ),
          border: InputBorder.none,
          prefixIcon: Icon(
            Icons.search_rounded,
            color: isDark ? Colors.white54 : Colors.black38,
            size: 20,
          ),
          suffixIcon: temTexto
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 20),
                  onPressed: aoLimpar ?? controller.clear,
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md - 1,
          ),
        ),
      ),
    );
  }
}
