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

// palavras que ficam em minuscula no meio de um nome proprio em portugues
const Set<String> _palavrasMenores = {
  'de', 'da', 'do', 'das', 'dos', 'e', 'em', 'no', 'na', 'nos', 'nas', 'a', 'o',
};

// arruma a caixa de um nome que veio todo em minusculo.
//
// Nome de lugar chega em formatos variados: o usuario digita "centro", o
// OpenStreetMap devolve "vila adélia" em alguns cadastros. Mostrar isso do
// jeito que veio deixa a lista de sugestoes com cara de dado cru. So mexe
// quando NAO ha nenhuma maiuscula: nomes ja escritos direito ("Inatel",
// "UNIFEI", "Rua Dr. Delfino") passam intactos -- capitalizar de novo
// estragaria siglas
String capitalizarNome(String texto) {
  final limpo = texto.trim();
  if (limpo.isEmpty || limpo != limpo.toLowerCase()) return limpo;

  final palavras = limpo.split(' ');
  return palavras.asMap().entries.map((entrada) {
    final palavra = entrada.value;
    if (palavra.isEmpty) return palavra;
    // "de/da/do" so ficam minusculos no meio, nunca na primeira palavra
    if (entrada.key > 0 && _palavrasMenores.contains(palavra)) return palavra;
    return palavra[0].toUpperCase() + palavra.substring(1);
  }).join(' ');
}
