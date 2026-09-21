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
