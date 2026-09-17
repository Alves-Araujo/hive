import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/texto.dart';

enum TipoListing { moradia, evento }

// tipos especificos de moradia (campo "Tipo" do anuncio)
const List<String> tiposImovelDisponiveis = ['Casa', 'Apartamento', 'República', 'Pensão', 'Kitnet'];

// tags organizadas por categoria, usadas na criacao do anuncio e nos filtros do mapa
const List<String> tagsPositivas = ['Mobiliado', 'Garagem', 'Com Wi-Fi', 'Suíte', 'Elevador', 'Perto da Facul'];
const List<String> tagsNegativas = ['Sem elevador'];
const List<String> tagsPreferenciaGenero = ['Exclusivo para Mulheres', 'Exclusivo para Homens'];

const List<String> tagsDisponiveis = [...tagsPositivas, ...tagsNegativas, ...tagsPreferenciaGenero];

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
      tags: List<String>.from(map['tags'] ?? []).map(normalizarTracos).toList(),
      endereco: normalizarTracosOuVazio(map['endereco']),
      fotos: List<String>.from(map['fotos'] ?? []),
      donoUid: map['donoUid'] ?? '',
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
      incluiWifi: map['incluiWifi'] ?? false,
    );
  }

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
    };
  }
}
