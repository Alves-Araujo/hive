import 'package:flutter/material.dart';

import '../services/lugares_service.dart';

// uma opcao do grupo "Localidade" do filtro: "tem X a ate `raio` metros
// daqui". Diferente das tags, isso nao e declarado pelo anunciante -- e
// medido: a faculdade pela distancia ate o Inatel, o resto pelo que o
// LugaresService achou perto da moradia
class OpcaoLocalidade {
  final String id; // guardado no filtro; pras categorias e o CategoriaLugar.name
  final String rotulo;
  final IconData icone;
  final int raio; // metros

  const OpcaoLocalidade(this.id, this.rotulo, this.icone, this.raio);
}

const String localidadeFaculdade = 'faculdade';

// o mesmo criterio do "Perto da Faculdade" que o anunciante marcava a olho,
// agora com um numero: 1,2 km e a distancia que da pra fazer a pe
const int raioFaculdade = 1200;

// a lista sai das categorias do LugaresService em vez de ser escrita na mao:
// categoria nova no servico (ou raio ajustado) aparece aqui sozinha, sem
// ninguem lembrar de vir mexer neste arquivo.
//
// O recorte e o mesmo da ficha do anuncio (naFichaDoAnuncio): hotel fica de
// fora -- "perto de um hotel" nao ajuda quem vai morar ali
final List<OpcaoLocalidade> opcoesLocalidade = [
  const OpcaoLocalidade(localidadeFaculdade, 'Faculdade', Icons.school_rounded, raioFaculdade),
  ...CategoriaLugar.values.where((c) => c.naFichaDoAnuncio).map(
        (c) => OpcaoLocalidade(c.name, c.rotulo, c.icone, c.raio),
      ),
];

// uma opcao do grupo "Categorias": diz O QUE aparece no mapa, e nao qual
// anuncio passa. Difere da Localidade justamente nisso -- "Farmácias" aqui
// mostra os pins de farmacia, enquanto "Farmácia" na localidade mostra as
// moradias que TEM uma farmacia por perto
class OpcaoCategoria {
  final String id; // 'evento' ou o CategoriaLugar.name
  final String rotulo;
  final IconData icone;

  const OpcaoCategoria(this.id, this.rotulo, this.icone);
}

// o unico tipo de anuncio que e uma categoria por si so. Moradia nao entra:
// ela e o assunto do resto da folha (preco, comodidade, contas)
const String categoriaEvento = 'evento';

// Eventos + os estabelecimentos que ganham pin no mapa. Hotel fica de fora
// pelo mesmo motivo da ficha do anuncio (ver CategoriaLugar)
final List<OpcaoCategoria> opcoesCategoria = [
  const OpcaoCategoria(categoriaEvento, 'Eventos', Icons.celebration_rounded),
  ...CategoriaLugar.values.where((c) => c.naFichaDoAnuncio).map(
        (c) => OpcaoCategoria(c.name, c.rotuloPlural, c.icone),
      ),
];

// gerencia o estado dos filtros do mapa (faixa de preco, caracteristicas,
// localidade e categoria). E local da tela do mapa de proposito: so os
// markers dependem disso
class FiltroState extends ChangeNotifier {
  // null = sem limite naquela ponta. A faixa e aberta dos dois lados: nao
  // existe mais um teto de 3000 fixado pelo fim do slider
  double? _precoMinimo;
  double? _precoMaximo;
  List<String> _tagsSelecionadas = [];
  List<String> _contasSelecionadas = [];
  List<String> _localidadesSelecionadas = [];
  List<String> _categoriasSelecionadas = [];

  double? get precoMinimo => _precoMinimo;
  double? get precoMaximo => _precoMaximo;
  List<String> get tagsSelecionadas => List.unmodifiable(_tagsSelecionadas);
  List<String> get contasSelecionadas => List.unmodifiable(_contasSelecionadas);
  List<String> get localidadesSelecionadas => List.unmodifiable(_localidadesSelecionadas);

  // vazio = mapa completo (moradias, eventos e todos os pins). Com alguma
  // categoria escolhida, so o que foi escolhido fica no mapa
  List<String> get categoriasSelecionadas => List.unmodifiable(_categoriasSelecionadas);

  bool get temFiltrosAtivos => quantidadeAtiva > 0;

  // cada ponta do preco conta como um filtro -- e o que aparece no "N
  // filtro(s) aplicado(s)" e no badge do botao
  int get quantidadeAtiva =>
      (_precoMinimo != null ? 1 : 0) +
      (_precoMaximo != null ? 1 : 0) +
      _tagsSelecionadas.length +
      _contasSelecionadas.length +
      _localidadesSelecionadas.length +
      _categoriasSelecionadas.length;

  void aplicarEstado({
    double? precoMinimo,
    double? precoMaximo,
    required List<String> tags,
    required List<String> contas,
    required List<String> localidades,
    required List<String> categorias,
  }) {
    _precoMinimo = precoMinimo;
    _precoMaximo = precoMaximo;
    _tagsSelecionadas = List.from(tags);
    _contasSelecionadas = List.from(contas);
    _localidadesSelecionadas = List.from(localidades);
    _categoriasSelecionadas = List.from(categorias);
    notifyListeners();
  }
}
