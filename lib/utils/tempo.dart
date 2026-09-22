// texto tipo "Ativo há 2 dias" ou a data certinha se ja faz muito tempo
String formatarUltimoAcesso(DateTime? data) {
  if (data == null) return 'Sem registro de acesso';

  final diferenca = DateTime.now().difference(data);

  if (diferenca.inMinutes < 1) return 'Ativo agora';
  if (diferenca.inHours < 1) return 'Ativo há ${diferenca.inMinutes} min';
  if (diferenca.inDays < 1) return 'Ativo há ${diferenca.inHours}h';
  if (diferenca.inDays < 7) return 'Ativo há ${diferenca.inDays} dia(s)';

  return 'Último acesso em ${data.day.toString().padLeft(2, '0')}/'
      '${data.month.toString().padLeft(2, '0')}/${data.year}';
}

// "agora", "há 5 min", "há 3 dias"... usado na lista de notificacoes
String formatarTempoRelativo(DateTime? data) {
  if (data == null) return 'agora';

  final diferenca = DateTime.now().difference(data);

  if (diferenca.inMinutes < 1) return 'agora';
  if (diferenca.inHours < 1) return 'há ${diferenca.inMinutes} min';
  if (diferenca.inDays < 1) return 'há ${diferenca.inHours}h';
  if (diferenca.inDays == 1) return 'ontem';
  if (diferenca.inDays < 7) return 'há ${diferenca.inDays} dias';

  return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}';
}

// "14:32" -- a hora que vai no rodape do balao de mensagem
String formatarHora(DateTime? data) {
  if (data == null) return '';
  return '${data.hour.toString().padLeft(2, '0')}:${data.minute.toString().padLeft(2, '0')}';
}

bool mesmoDia(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

const List<String> _meses = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];

// etiqueta da faixa que separa os dias dentro de uma conversa. Sem ela, uma
// mensagem de semana passada e a de hoje aparecem coladas como se fossem da
// mesma conversa de agora
String rotuloDiaConversa(DateTime data) {
  final hoje = DateTime.now();
  if (mesmoDia(data, hoje)) return 'Hoje';
  if (mesmoDia(data, hoje.subtract(const Duration(days: 1)))) return 'Ontem';

  final dia = data.day.toString().padLeft(2, '0');
  if (data.year == hoje.year) return '$dia de ${_meses[data.month - 1]}';
  return '$dia de ${_meses[data.month - 1]} de ${data.year}';
}
