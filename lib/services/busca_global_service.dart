import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/imobiliaria.dart';
import '../models/perfil_publico.dart';
import '../utils/moderacao.dart';
import 'perfil_publico_service.dart';

// resultado generico da pesquisa global -- ou e uma pessoa (perfil publico)
// ou uma imobiliaria, nunca os dois
class ResultadoBuscaGlobal {
  final PerfilPublico? pessoa;
  final Imobiliaria? imobiliaria;

  ResultadoBuscaGlobal.pessoa(this.pessoa) : imobiliaria = null;
  ResultadoBuscaGlobal.imobiliaria(this.imobiliaria) : pessoa = null;

  String get nome => pessoa?.nome ?? imobiliaria?.nome ?? '';
  String get fotoUrl => pessoa?.fotoUrl ?? imobiliaria?.fotoUrl ?? '';

  String get rotulo {
    if (imobiliaria != null) return 'Imobiliária';
    switch (pessoa?.tipoUsuario) {
      case 'corretor':
        if (pessoa?.ehAdminImobiliaria ?? false) return 'Imobiliária (administrador)';
        return pessoa?.subtipoCorretor == 'empresa' ? 'Corretor (Empresa)' : 'Corretor Autônomo';
      case 'proprietario':
        return 'Proprietário';
      case 'estudante':
        return 'Estudante';
      default:
        return 'Usuário';
    }
  }
}

// pesquisa em tempo real por nome, combinando alunos/corretores/proprietarios
// (perfisPublicos) e imobiliarias -- as duas colecoes ja tem "nomeBusca"
// normalizado, entao da pra usar range query (prefixo) sem indice composto
class BuscaGlobalService {
  BuscaGlobalService._();
  static final BuscaGlobalService instance = BuscaGlobalService._();

  Future<List<ResultadoBuscaGlobal>> buscar(String termo, {int limitePorTipo = 8}) async {
    final normalizado = normalizarNome(termo);
    if (normalizado.isEmpty) return [];

    final pessoas = await PerfilPublicoService.instance.buscarPorPrefixoDeNome(normalizado, limite: limitePorTipo);

    final imobiliariasQuery = await FirebaseFirestore.instance
        .collection('imobiliarias')
        .orderBy('nomeBusca')
        .startAt([normalizado])
        .endAt(['$normalizado'])
        .limit(limitePorTipo)
        .get();
    final imobiliarias = imobiliariasQuery.docs.map((d) => Imobiliaria.fromMap(d.data(), d.id)).toList();

    return [
      ...pessoas.map(ResultadoBuscaGlobal.pessoa),
      ...imobiliarias.map(ResultadoBuscaGlobal.imobiliaria),
    ];
  }
}
