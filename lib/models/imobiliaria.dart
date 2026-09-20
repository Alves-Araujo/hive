import 'package:google_maps_flutter/google_maps_flutter.dart';

class Imobiliaria {
  final String id;
  final String nome;
  final String nomeBusca;
  final String cnpj;
  final String cnpjBusca;
  final String email;
  final String emailBusca;
  final bool emailVerificado;
  final String fotoUrl;
  final String endereco;

  // coordenada do escritorio, pro pin no mapa. Fica null quando o endereco
  // nao pode ser geocodificado (ou em cadastro antigo, feito antes disso
  // existir) -- e a ausencia dela que decide se a imobiliaria aparece no mapa
  final LatLng? posicao;

  Imobiliaria({
    required this.id,
    required this.nome,
    this.nomeBusca = '',
    required this.cnpj,
    this.cnpjBusca = '',
    required this.email,
    this.emailBusca = '',
    this.emailVerificado = false,
    this.fotoUrl = '',
    this.endereco = '',
    this.posicao,
  });

  factory Imobiliaria.fromMap(Map<String, dynamic> map, String id) {
    return Imobiliaria(
      id: id,
      nome: map['nome'] ?? '',
      nomeBusca: map['nomeBusca'] ?? '',
      cnpj: map['cnpj'] ?? '',
      cnpjBusca: map['cnpjBusca'] ?? '',
      email: map['email'] ?? '',
      emailBusca: map['emailBusca'] ?? '',
      emailVerificado: map['emailVerificado'] ?? false,
      fotoUrl: map['fotoUrl'] ?? '',
      endereco: map['endereco'] ?? '',
      posicao: (map['latitude'] is num && map['longitude'] is num)
          ? LatLng((map['latitude'] as num).toDouble(),
              (map['longitude'] as num).toDouble())
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nome': nome,
      'nomeBusca': nomeBusca,
      'cnpj': cnpj,
      'cnpjBusca': cnpjBusca,
      'email': email,
      'emailBusca': emailBusca,
      'emailVerificado': emailVerificado,
      'fotoUrl': fotoUrl,
      'endereco': endereco,
      // gravados soltos (nao como GeoPoint) pra seguir o mesmo formato que
      // os imoveis ja usam na colecao "imoveis"
      if (posicao != null) 'latitude': posicao!.latitude,
      if (posicao != null) 'longitude': posicao!.longitude,
    };
  }
}
