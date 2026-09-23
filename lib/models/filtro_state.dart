import 'package:flutter/material.dart';

import '../services/lugares_service.dart';
import '../utils/moderacao.dart' show normalizarNome;
import 'imovel.dart';

class OpcaoLocalidade {
  final String id;
  final String rotulo;
  final IconData icone;
  final int raio;

  const OpcaoLocalidade(this.id, this.rotulo, this.icone, this.raio);
}

const localidadeFaculdade = 'faculdade';
const raioFaculdade = 1200;

final List<OpcaoLocalidade> opcoesLocalidade = [
  const OpcaoLocalidade(
    localidadeFaculdade,
    'Faculdade',
    Icons.school_rounded,
    raioFaculdade,
  ),
  ...CategoriaLugar.values
      .where((c) => c.naFichaDoAnuncio)
      .map((c) => OpcaoLocalidade(c.name, c.rotulo, c.icone, c.raio)),
];

class OpcaoCategoria {
  final String id;
  final String rotulo;
  final IconData icone;

  const OpcaoCategoria(this.id, this.rotulo, this.icone);
}

const categoriaMoradia = 'moradia';
const categoriaEvento = 'evento';

final List<OpcaoCategoria> opcoesCategoria = [
  const OpcaoCategoria(categoriaMoradia, 'Imóveis', Icons.home_rounded),
  const OpcaoCategoria(categoriaEvento, 'Eventos', Icons.celebration_rounded),
  ...CategoriaLugar.values.map(
    (c) => OpcaoCategoria(c.name, c.rotuloPlural, c.icone),
  ),
];

/// Critérios de moradia e visibilidade do mapa são independentes.
/// A folha edita uma cópia; o mapa só recebe as escolhas ao aplicar.
class FiltrosMapa {
  final double? precoMinimo;
  final double? precoMaximo;
  final Set<String> tipos;
  final Set<String> _tiposNormalizados;
  final Set<String> tags;
  final Set<String> contas;
  final Set<String> localidades;
  final Set<String> categoriasOcultas;

  FiltrosMapa({
    double? precoMinimo,
    double? precoMaximo,
    Iterable<String> tipos = const [],
    Iterable<String> tags = const [],
    Iterable<String> contas = const [],
    Iterable<String> localidades = const [],
    Iterable<String> categoriasOcultas = const [],
  }) : precoMinimo =
           precoMinimo != null &&
               precoMaximo != null &&
               precoMinimo > precoMaximo
           ? precoMaximo
           : precoMinimo,
       precoMaximo =
           precoMinimo != null &&
               precoMaximo != null &&
               precoMinimo > precoMaximo
           ? precoMinimo
           : precoMaximo,
       tipos = Set.unmodifiable(tipos),
       _tiposNormalizados = tipos.map(normalizarNome).toSet(),
       tags = Set.unmodifiable(tags),
       contas = Set.unmodifiable(contas),
       localidades = Set.unmodifiable(localidades),
       categoriasOcultas = Set.unmodifiable(categoriasOcultas);

  int get quantidadeImovel =>
      (precoMinimo == null && precoMaximo == null ? 0 : 1) +
      tipos.length +
      tags.length +
      contas.length +
      localidades.length;

  int get quantidadeAtiva => quantidadeImovel + categoriasOcultas.length;
  bool mostraCategoria(String id) => !categoriasOcultas.contains(id);

  bool aceitaImovel(
    Imovel item, {
    required bool Function(String) atendeLocalidade,
  }) {
    if (item.tipo != TipoListing.moradia) return false;
    if (precoMinimo != null && item.preco < precoMinimo!) return false;
    if (precoMaximo != null && item.preco > precoMaximo!) return false;
    // Anúncios antigos podem guardar o tipo apenas nas tags.
    if (tipos.isNotEmpty &&
        !_tiposNormalizados.contains(normalizarNome(item.tipoImovel)) &&
        !(item.tipoImovel.trim().isEmpty &&
            item.tags.map(normalizarNome).any(_tiposNormalizados.contains))) {
      return false;
    }
    if (!tags.where(tagsComodidade.contains).every(item.tags.contains)) {
      return false;
    }
    final preferencias = tags.where(tagsPreferenciaGenero.contains);
    if (preferencias.isNotEmpty && !preferencias.any(item.tags.contains)) {
      return false;
    }
    if (!contas.every(item.incluiConta)) return false;
    return localidades.every(atendeLocalidade);
  }

  bool aceitaAnuncio(
    Imovel item, {
    required bool Function(String) atendeLocalidade,
  }) {
    if (item.tipo == TipoListing.evento) {
      return mostraCategoria(categoriaEvento);
    }
    return mostraCategoria(categoriaMoradia) &&
        aceitaImovel(item, atendeLocalidade: atendeLocalidade);
  }
}

class FiltroState extends ChangeNotifier {
  FiltrosMapa _atual = FiltrosMapa();
  FiltrosMapa get atual => _atual;
  int get quantidadeAtiva => _atual.quantidadeAtiva;
  bool get temFiltrosAtivos => quantidadeAtiva > 0;

  void aplicar(FiltrosMapa filtros) {
    _atual = filtros;
    notifyListeners();
  }
}
