import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/endereco.dart';

// consulta de CEP no ViaCEP (gratuito, sem chave) -- usado pra preencher
// logradouro, bairro, cidade e UF sozinhos no formulario de endereco
class CepService {
  CepService._();
  static final CepService instance = CepService._();

  // retorna null se o CEP nao existe. Numero e complemento nao vem da API,
  // ficam vazios. CEP geral de cidade pequena vem sem logradouro/bairro
  Future<Endereco?> buscar(String cep) async {
    final digitos = cep.replaceAll(RegExp(r'\D'), '');
    if (digitos.length != 8) return null;

    final response = await http
        .get(Uri.parse('https://viacep.com.br/ws/$digitos/json/'))
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw Exception('Erro na API ViaCEP: HTTP ${response.statusCode}');
    }

    final dados = json.decode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    // CEP com formato valido mas inexistente volta 200 com {"erro": true}
    if (dados['erro'] != null) return null;

    return Endereco(
      cep: cep,
      logradouro: dados['logradouro'] ?? '',
      bairro: dados['bairro'] ?? '',
      cidade: dados['localidade'] ?? '',
      estado: dados['uf'] ?? '',
    );
  }
}
