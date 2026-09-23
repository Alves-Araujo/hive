import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:moradia_app/models/filtro_state.dart';
import 'package:moradia_app/models/imovel.dart';

Imovel anuncio({
  TipoListing tipo = TipoListing.moradia,
  double preco = 800,
  String tipoImovel = 'Casa',
  List<String> tags = const ['Mobiliado', 'Garagem'],
  bool agua = true,
  bool luz = false,
}) => Imovel(
  id: 'imovel',
  titulo: 'Teste',
  descricao: '',
  preco: preco,
  posicao: const LatLng(-22.25, -45.70),
  tipo: tipo,
  tipoImovel: tipoImovel,
  tags: tags,
  endereco: '',
  incluiAgua: agua,
  incluiLuz: luz,
);

bool aceita(FiltrosMapa filtro, Imovel item, {Set<String> perto = const {}}) =>
    filtro.aceitaAnuncio(item, atendeLocalidade: perto.contains);

void main() {
  test('padrão mostra todas as categorias e não limita os imóveis', () {
    final filtro = FiltrosMapa();
    expect(opcoesCategoria.every((c) => filtro.mostraCategoria(c.id)), isTrue);
    expect(aceita(filtro, anuncio()), isTrue);
    expect(aceita(filtro, anuncio(tipo: TipoListing.evento)), isTrue);
    expect(filtro.quantidadeAtiva, 0);
  });

  test('ocultar um estabelecimento não esconde moradias nem eventos', () {
    final filtro = FiltrosMapa(categoriasOcultas: ['mercado']);
    expect(filtro.mostraCategoria('mercado'), isFalse);
    expect(filtro.mostraCategoria('farmacia'), isTrue);
    expect(aceita(filtro, anuncio()), isTrue);
    expect(aceita(filtro, anuncio(tipo: TipoListing.evento)), isTrue);
  });

  test('eventos ignoram critérios exclusivos de moradia', () {
    final filtro = FiltrosMapa(
      precoMaximo: 100,
      tipos: ['Kitnet'],
      tags: ['Elevador'],
      contas: [contaLuz],
      localidades: ['mercado'],
    );
    expect(aceita(filtro, anuncio()), isFalse);
    expect(aceita(filtro, anuncio(tipo: TipoListing.evento)), isTrue);
  });

  test('visibilidade explícita permite ocultar todos os grupos', () {
    final filtro = FiltrosMapa(
      categoriasOcultas: opcoesCategoria.map((o) => o.id),
    );
    expect(opcoesCategoria.any((c) => filtro.mostraCategoria(c.id)), isFalse);
    expect(aceita(filtro, anuncio()), isFalse);
    expect(aceita(filtro, anuncio(tipo: TipoListing.evento)), isFalse);
  });

  test('faixa aceita limites abertos, inclusivos e digitados ao contrário', () {
    expect(aceita(FiltrosMapa(precoMaximo: 800), anuncio()), isTrue);
    expect(aceita(FiltrosMapa(precoMinimo: 800), anuncio()), isTrue);
    expect(aceita(FiltrosMapa(precoMaximo: 799), anuncio()), isFalse);
    expect(
      aceita(FiltrosMapa(precoMinimo: 900, precoMaximo: 600), anuncio()),
      isTrue,
    );
    expect(
      aceita(FiltrosMapa(precoMinimo: 4000), anuncio(preco: 5000)),
      isTrue,
    );
  });

  test('tipos são alternativas e mantêm compatibilidade com tags antigas', () {
    final filtro = FiltrosMapa(tipos: ['República', 'Apartamento']);
    expect(aceita(filtro, anuncio(tipoImovel: ' republica ')), isTrue);
    expect(
      aceita(filtro, anuncio(tipoImovel: '', tags: ['Apartamento'])),
      isTrue,
    );
    expect(aceita(filtro, anuncio()), isFalse);
    expect(
      aceita(filtro, anuncio(tipoImovel: 'Casa', tags: ['Apartamento'])),
      isFalse,
    );
  });

  test('comodidades e contas são cumulativas, com campos separados', () {
    expect(
      aceita(FiltrosMapa(tags: ['Mobiliado'], contas: [contaAgua]), anuncio()),
      isTrue,
    );
    expect(
      aceita(FiltrosMapa(tags: ['Mobiliado', 'Elevador']), anuncio()),
      isFalse,
    );
    expect(
      aceita(FiltrosMapa(contas: [contaAgua, contaLuz]), anuncio()),
      isFalse,
    );
  });

  // A categoria nasce em CategoriaLugar e se espalha sozinha pelas duas
  // listas de filtro. O teste existe pra isso nao regredir em silencio: uma
  // categoria com naFichaDoAnuncio errado some da aba "Perto do imóvel" sem
  // quebrar nada, e ninguem percebe ate abrir a folha no aparelho
  test('restaurante entra nas duas listas de filtro', () {
    expect(opcoesCategoria.map((o) => o.id), contains('restaurante'));
    expect(opcoesLocalidade.map((o) => o.id), contains('restaurante'));

    final soComRestaurante = FiltrosMapa(localidades: ['restaurante']);
    expect(aceita(soComRestaurante, anuncio(), perto: {'restaurante'}), isTrue);
    expect(aceita(soComRestaurante, anuncio(), perto: {'mercado'}), isFalse);

    final semPins = FiltrosMapa(categoriasOcultas: ['restaurante']);
    expect(semPins.mostraCategoria('restaurante'), isFalse);
    expect(semPins.mostraCategoria('mercado'), isTrue);
  });

  test('proximidade exige todos os locais e independe dos pins visíveis', () {
    final filtro = FiltrosMapa(
      localidades: ['mercado', localidadeFaculdade],
      categoriasOcultas: ['mercado'],
    );
    expect(aceita(filtro, anuncio(), perto: {'mercado'}), isFalse);
    expect(
      aceita(filtro, anuncio(), perto: {'mercado', localidadeFaculdade}),
      isTrue,
    );
  });

  test('perfis alternativos não exigem duas exclusividades ao mesmo tempo', () {
    final filtro = FiltrosMapa(tags: tagsPreferenciaGenero);
    expect(
      aceita(filtro, anuncio(tags: [tagsPreferenciaGenero.first])),
      isTrue,
    );
    expect(aceita(filtro, anuncio()), isFalse);
  });

  test('estado aplicado não compartilha conjuntos mutáveis com o rascunho', () {
    final tipos = {'Casa'};
    final filtros = FiltrosMapa(tipos: tipos);
    final estado = FiltroState();
    var avisos = 0;
    estado.addListener(() => avisos++);
    estado.aplicar(filtros);
    tipos.clear();
    expect(estado.atual.tipos, {'Casa'});
    expect(() => estado.atual.tipos.clear(), throwsUnsupportedError);
    expect(avisos, 1);
    estado.dispose();
  });
}
