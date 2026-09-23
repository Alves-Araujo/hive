// lista curta de palavroes mais comuns em pt-br -- da pra crescer depois
const List<String> _palavroesConhecidos = [
  'porra', 'caralho', 'merda', 'buceta', 'piroca', 'pinto', 'puta', 'putaria',
  'viado', 'bicha', 'cuzao', 'cu', 'fdp', 'arrombado', 'arrombada', 'corno',
  'desgraca', 'imbecil', 'retardado', 'babaca', 'otario', 'otaria', 'idiota',
  'vagabundo', 'vagabunda', 'safado', 'safada', 'escroto', 'escrota',
];

// sinais de acento que vem soltos, depois da letra (Unicode combining marks).
// Teclado de celular manda "ã" de dois jeitos: um caractere so (U+00E3) ou
// "a" + til solto (U+0061 U+0303). Os dois aparecem identicos na tela
final RegExp _acentoSolto = RegExp(r'\p{M}', unicode: true);

// tira acento de uma string, pra comparacao mais tolerante
String semAcento(String texto) {
  const comAcento = 'áàâãäéèêëíìîïóòôõöúùûüçñÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑ';
  const semAcentoEquivalente = 'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN';
  var resultado = texto;
  for (var i = 0; i < comAcento.length; i++) {
    resultado = resultado.replaceAll(comAcento[i], semAcentoEquivalente[i]);
  }
  // o mesmo nome digitado nas duas formas tem que gerar a MESMA chave de
  // busca, senao "João" do celular e "João" do navegador viram dois nomes
  // diferentes na checagem de duplicidade
  return resultado.replaceAll(_acentoSolto, '');
}

// nome normalizado (minusculo, sem acento, sem espaco duplicado) -- usado
// pra checar duplicidade e pra busca
String normalizarNome(String nome) {
  return semAcento(nome.trim().toLowerCase()).replaceAll(RegExp(r'\s+'), ' ');
}

// Letra de qualquer alfabeto (\p{L}) + o acento que vem solto depois dela
// (\p{M}), mais espaco, apostrofo e hifen -- e nada mais.
//
// Nome NAO passa por lista de caracteres escritos um a um: foi assim que
// "a-zA-Z" barrou meio pais, e depois "À-ÿ" ainda barrava o "ã" que o teclado
// manda como "a" + til solto -- a pessoa via o nome certo na tela e o app
// dizia que estava errado. \p{L} resolve a familia toda de uma vez ("João",
// "Inês", "Gonçalves", "Núria Peña"). Numero e simbolo continuam fora --
// "Ana2" ou "Ana <3" nao sao nome de pessoa
final RegExp _apenasLetrasDeNome = RegExp(r"^[\p{L}\p{M}' -]+$", unicode: true);

bool nomeTemCaracteresValidos(String nome) => _apenasLetrasDeNome.hasMatch(nome.trim());

bool temNomeESobrenome(String nome) {
  final partes = nome.trim().split(RegExp(r'\s+')).where((p) => p.length >= 2).toList();
  return partes.length >= 2;
}

bool contemPalavraImpropria(String nome) {
  final palavras = normalizarNome(nome).split(' ');
  return palavras.any((p) => _palavroesConhecidos.contains(p));
}
