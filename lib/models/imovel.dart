import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/inatividade.dart';
import '../utils/texto.dart';

enum TipoListing { moradia, evento }

// tipos especificos de moradia (campo "Tipo" do anuncio)
const List<String> tiposImovelDisponiveis = ['Casa', 'Apartamento', 'República', 'Pensão', 'Kitnet'];

// tags organizadas por categoria, usadas na criacao do anuncio e nos filtros do mapa
// "Perto da Facul" virou "Perto da Faculdade". O nome antigo continua
// gravado nos anuncios ja existentes, entao NAO basta renomear aqui: sem
// converter na leitura, anuncio antigo mostraria o texto velho e deixaria de
// casar com o filtro novo. Ver tagCompativel() abaixo
const String tagPertoDaFaculdade = 'Perto da Faculdade';
const String _tagPertoDaFaculdadeAntiga = 'Perto da Facul';

// "Com Wi-Fi" deixou de ser tag: o Wi-Fi ja e um campo proprio (incluiWifi,
// em "Contas inclusas"), e a tela mostrava a mesma informacao duas vezes.
// Anuncio antigo com a tag gravada tem ela convertida em incluiWifi na
// leitura (ver fromMap)
const String _tagWifiAntiga = 'Com Wi-Fi';

// "Sem elevador" saiu: dizer que o predio NAO tem elevador nao e
// caracteristica que alguem procura -- quem precisa de elevador marca
// "Elevador", e o resto nao filtra por isso. Anuncio antigo com a tag gravada
// tem ela descartada na leitura (ver fromMap)
const String _tagSemElevadorAntiga = 'Sem elevador';

// comodidades do proprio imovel -- as unicas que valem como caracteristica
// tanto no anuncio quanto no filtro
const List<String> tagsComodidade = ['Mobiliado', 'Garagem', 'Suíte', 'Elevador'];

const List<String> tagsPositivas = [...tagsComodidade, tagPertoDaFaculdade];

// converte tag gravada no banco pro nome atual
String tagCompativel(String tag) =>
    tag == _tagPertoDaFaculdadeAntiga ? tagPertoDaFaculdade : tag;
const List<String> tagsPreferenciaGenero = ['Exclusivo para Mulheres', 'Exclusivo para Homens'];

const List<String> tagsDisponiveis = [...tagsPositivas, ...tagsPreferenciaGenero];

// contas que ja podem vir no aluguel. Nao sao tags: cada uma tem campo
// proprio no anuncio (incluiLuz/incluiAgua/incluiWifi), e no filtro elas
// formam um grupo separado das caracteristicas. Os nomes e a ordem sao os
// mesmos do "O que está incluso" da ficha e do cadastro
const String contaLuz = 'Luz';
const String contaAgua = 'Água';
const String contaWifi = 'Wi-Fi';
const List<String> opcoesContasInclusas = [contaLuz, contaAgua, contaWifi];

// caracteristicas do filtro do mapa. "Perto da Faculdade" NAO entra aqui: no
// filtro a proximidade virou o grupo "Localidade", medido pela distancia real
// (ver opcoesLocalidade em filtro_state.dart) em vez do que o anunciante
// achou que era perto. Como tag do anuncio ela continua valendo, pra aparecer
// no card e na ficha
const List<String> opcoesDeFiltro = [...tagsComodidade, ...tagsPreferenciaGenero];

// siglas dos estados brasileiros, usadas no campo "Estado" do endereco estruturado
const List<String> estadosBrasileiros = [
  'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS', 'MG',
  'PA', 'PB', 'PR', 'PE', 'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO',
];

class Imovel {
  final String id;
  final String titulo;
  final String descricao;
  final double preco;
  final LatLng posicao;
  final TipoListing tipo;
  final List<String> tags;
  final String endereco; // string completa, composta a partir dos campos abaixo
  final List<String> fotos;
  final String donoUid;

  // imobiliaria do corretor que publicou. Vazio em anuncio de proprietario ou
  // de corretor autonomo -- e o que liga o imovel a empresa em nome de quem
  // ele foi anunciado
  final String imobiliariaId;

  // endereco estruturado (exigido por completo no formulario, exceto complemento)
  final String cep;
  final String logradouro;
  final String numero;
  final String complemento;
  final String bairro;
  final String cidade;
  final String estado;

  // campos do novo fluxo de cadastro (so preenchidos quando tipo == moradia)
  final String tipoImovel;
  final String andar;
  final String comprovanteResidenciaUrl;
  final double iptuValor;
  final String iptuComprovanteUrl;
  final bool incluiLuz;
  final bool incluiAgua;
  final bool incluiWifi;

  // Desde quando alguem mandou mensagem neste anuncio e ninguem respondeu.
  // Nulo = ninguem esperando. Nao e escrito pela tela de cadastro e nem sai
  // em toMap(): quem liga e desliga esse relogio e o envio de mensagem, por
  // ImovelService.registrarMensagem (ver utils/inatividade.dart). Se ele
  // entrasse no toMap(), reabrir o anuncio pra corrigir o preco zeraria o
  // prazo -- editar nao e responder ninguem
  final DateTime? aguardandoRespostaDesde;

  Imovel({
    required this.id,
    required this.titulo,
    required this.descricao,
    required this.preco,
    required this.posicao,
    required this.tipo,
    required this.tags,
    required this.endereco,
    this.fotos = const [],
    this.donoUid = '',
    this.imobiliariaId = '',
    this.cep = '',
    this.logradouro = '',
    this.numero = '',
    this.complemento = '',
    this.bairro = '',
    this.cidade = '',
    this.estado = '',
    this.tipoImovel = '',
    this.andar = '',
    this.comprovanteResidenciaUrl = '',
    this.iptuValor = 0,
    this.iptuComprovanteUrl = '',
    this.incluiLuz = false,
    this.incluiAgua = false,
    this.incluiWifi = false,
    this.aguardandoRespostaDesde,
  });

  factory Imovel.fromMap(Map<String, dynamic> map, String docId) {
    double lat = 0.0;
    double lng = 0.0;

    if (map['posicao'] != null) {
      if (map['posicao'] is GeoPoint) {
        lat = (map['posicao'] as GeoPoint).latitude;
        lng = (map['posicao'] as GeoPoint).longitude;
      } else {
        try {
          lat = map['posicao']['lat'] ?? 0.0;
          lng = map['posicao']['lng'] ?? 0.0;
        } catch (_) {}
      }
    }

    final List<String> tagsGravadas = List<String>.from(map['tags'] ?? []).map(normalizarTracos).toList();
    final bool tinhaTagWifi = tagsGravadas.contains(_tagWifiAntiga);

    return Imovel(
      id: docId,
      // texto que veio do banco passa por normalizarTracos -- anuncios
      // antigos foram gravados com travessao e apareciam com o traco longo
      // na interface (ver utils/texto.dart)
      titulo: normalizarTracosOuVazio(map['titulo']),
      descricao: normalizarTracosOuVazio(map['descricao']),
      preco: (map['preco'] ?? 0.0).toDouble(),
      posicao: LatLng(lat, lng),
      tipo: (map['tipo'] ?? '') == 'evento' ? TipoListing.evento : TipoListing.moradia,
      tags: tagsGravadas
          .where((t) => t != _tagWifiAntiga && t != _tagSemElevadorAntiga)
          .map(tagCompativel)
          .toList(),
      endereco: normalizarTracosOuVazio(map['endereco']),
      fotos: List<String>.from(map['fotos'] ?? []),
      donoUid: map['donoUid'] ?? '',
      imobiliariaId: map['imobiliariaId'] ?? '',
      cep: map['cep'] ?? '',
      logradouro: normalizarTracosOuVazio(map['logradouro']),
      numero: map['numero'] ?? '',
      complemento: normalizarTracosOuVazio(map['complemento']),
      bairro: normalizarTracosOuVazio(map['bairro']),
      cidade: normalizarTracosOuVazio(map['cidade']),
      estado: map['estado'] ?? '',
      tipoImovel: normalizarTracosOuVazio(map['tipoImovel']),
      andar: map['andar'] ?? '',
      comprovanteResidenciaUrl: map['comprovanteResidenciaUrl'] ?? '',
      iptuValor: (map['iptuValor'] ?? 0.0).toDouble(),
      iptuComprovanteUrl: map['iptuComprovanteUrl'] ?? '',
      incluiLuz: map['incluiLuz'] ?? false,
      incluiAgua: map['incluiAgua'] ?? false,
      incluiWifi: (map['incluiWifi'] ?? false) || tinhaTagWifi,
      // vem nulo enquanto o horario do servidor esta pendente (a mensagem que
      // ligou o relogio acabou de sair deste aparelho) -- e nulo ja e o que
      // significa "ninguem esperando", entao o anuncio so nao conta esses
      // segundos a mais
      aguardandoRespostaDesde:
          (map['aguardandoRespostaDesde'] as Timestamp?)?.toDate(),
    );
  }

  // Ha quanto tempo este anuncio deve resposta, traduzido pro que isso muda
  // na pratica. Evento fica de fora: ele ja nasce com data pra acabar, e quem
  // o publicou nao esta ocupando o lugar de ninguem no mapa depois disso
  EstadoResposta get estadoResposta => tipo == TipoListing.evento
      ? EstadoResposta.emDia
      : estadoDeResposta(aguardandoRespostaDesde);

  // Passou dos cinco meses sem ninguem responder: nao aparece mais pra quem
  // procura (mapa e lista). Continua existindo, e no painel do dono -- basta
  // responder pra voltar
  bool get foraDoMapaPorFaltaDeResposta =>
      estadoResposta == EstadoResposta.foraDoMapa;

  // o aluguel ja inclui essa conta?
  bool incluiConta(String conta) => switch (conta) {
        contaLuz => incluiLuz,
        contaAgua => incluiAgua,
        contaWifi => incluiWifi,
        _ => false,
      };

  Map<String, dynamic> toMap() {
    return {
      // normaliza na gravacao tambem, senao um titulo colado (ou "corrigido"
      // pelo teclado do celular) com travessao voltaria a sujar o banco
      'titulo': normalizarTracos(titulo),
      'descricao': normalizarTracos(descricao),
      'preco': preco,
      'posicao': GeoPoint(posicao.latitude, posicao.longitude),
      'tipo': tipo == TipoListing.evento ? 'evento' : 'moradia',
      'tags': tags.map(normalizarTracos).toList(),
      'endereco': normalizarTracos(endereco),
      'fotos': fotos,
      'donoUid': donoUid,
      'imobiliariaId': imobiliariaId,
      'cep': cep,
      'logradouro': normalizarTracos(logradouro),
      'numero': numero,
      'complemento': normalizarTracos(complemento),
      'bairro': normalizarTracos(bairro),
      'cidade': normalizarTracos(cidade),
      'estado': estado,
      'tipoImovel': normalizarTracos(tipoImovel),
      'andar': andar,
      'comprovanteResidenciaUrl': comprovanteResidenciaUrl,
      'iptuValor': iptuValor,
      'iptuComprovanteUrl': iptuComprovanteUrl,
      'incluiLuz': incluiLuz,
      'incluiAgua': incluiAgua,
      'incluiWifi': incluiWifi,
      // aguardandoRespostaDesde NAO entra aqui de proposito (ver o campo la
      // em cima). Por isso a gravacao do anuncio e feita com merge: sem ele,
      // salvar uma edicao apagaria o relogio de resposta
    };
  }
}
