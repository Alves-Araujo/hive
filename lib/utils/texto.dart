// o app padronizou o hifen simples "-" em todo texto. Mas travessao (—),
// meia-risca (–) e parentes chegam de fora do nosso controle: anuncios
// antigos ja gravados no Firestore, texto colado pelo usuario e teclados de
// celular que trocam "-" por "—" sozinhos. Normaliza na fronteira (ao ler do
// banco e ao salvar) pra esses tracos nunca aparecerem na interface.
final RegExp _tracosLongos = RegExp(r'[–—―−]');

String normalizarTracos(String texto) => texto.replaceAll(_tracosLongos, '-');

// versao pra campo que pode vir nulo do Firestore -- devolve '' igual o
// padrao que os fromMap ja usavam
String normalizarTracosOuVazio(Object? valor) =>
    valor == null ? '' : normalizarTracos(valor.toString());
