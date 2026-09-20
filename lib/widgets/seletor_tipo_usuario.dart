import 'package:flutter/material.dart';
import '../main.dart';

const tiposUsuarioDisponiveis = [
  {'value': 'estudante', 'label': 'Estudante', 'desc': 'Quero alugar', 'icon': Icons.school_rounded},
  {'value': 'proprietario', 'label': 'Proprietário', 'desc': 'Dono do imóvel', 'icon': Icons.home_work_rounded},
  {'value': 'corretor', 'label': 'Corretor', 'desc': 'Imobiliária', 'icon': Icons.business_center_rounded},
];

// seletor visual de tipo de conta (estudante / proprietario / corretor) -- usado
// no cadastro por senha e no primeiro login via google
class SeletorTipoUsuario extends StatelessWidget {
  final String? valorSelecionado;
  final ValueChanged<String> onSelecionar;
  final bool isDark;

  const SeletorTipoUsuario({
    super.key,
    required this.valorSelecionado,
    required this.onSelecionar,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: tiposUsuarioDisponiveis.map((tipo) {
        final bool selected = valorSelecionado == tipo['value'];
        return Expanded(
          child: GestureDetector(
            onTap: () => onSelecionar(tipo['value'] as String),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              margin: EdgeInsets.only(
                right: tipo != tiposUsuarioDisponiveis.last ? 10 : 0,
              ),
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              decoration: BoxDecoration(
                color: selected
                    ? corPrimaria.withAlpha(isDark ? 30 : 20)
                    : (isDark ? Colors.white.withAlpha(8) : Colors.white.withAlpha(180)),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: selected
                      ? corPrimaria
                      : (isDark ? Colors.white.withAlpha(12) : Colors.grey.withAlpha(30)),
                  width: selected ? 2 : 1,
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: selected
                          ? corPrimaria.withAlpha(30)
                          : (isDark ? Colors.white.withAlpha(8) : Colors.grey.withAlpha(15)),
                      borderRadius: BorderRadius.circular(99.0),
                    ),
                    child: Icon(
                      tipo['icon'] as IconData,
                      color: selected ? corPrimaria : (isDark ? Colors.white54 : Colors.grey),
                      size: 24,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    tipo['label'] as String,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: selected ? corPrimaria : (isDark ? Colors.white70 : Colors.black87),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    tipo['desc'] as String,
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white38 : Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
