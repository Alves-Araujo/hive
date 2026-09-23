import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/usuario.dart';
import '../utils/moderacao.dart';
import 'perfil_publico_service.dart';

class UsuarioService {
  UsuarioService._();
  static final UsuarioService instance = UsuarioService._();

  final _colecao = FirebaseFirestore.instance.collection('usuarios');

  Future<Usuario?> buscarPorUid(String uid) async {
    final doc = await _colecao.doc(uid).get();
    if (!doc.exists) return null;
    return Usuario.fromMap(doc.data()!, doc.id);
  }

  // cria o perfil minimo -- tipo de conta e o resto dos dados so vem depois,
  // na tela de completar perfil
  Future<void> criarPerfil({
    required String uid,
    required String nome,
    required String email,
  }) async {
    await _colecao.doc(uid).set({
      'nome': nome,
      'nomeBusca': normalizarNome(nome),
      'email': email,
      'tipoUsuario': '',
      'fotoUrl': '',
      'perfilCompleto': false,
      'dataCriacao': FieldValue.serverTimestamp(),
    });

    // A versao publica do perfil pode ser negada aqui: em producao as regras
    // so deixam escrever em "perfisPublicos" depois que o e-mail e
    // confirmado, e o cadastro roda ANTES disso. Nao e perda nenhuma -- o
    // perfil publico e regravado ao salvar "Concluir perfil", que so abre
    // pra quem ja confirmou. Barrar aqui fazia o cadastro inteiro falhar
    try {
      await PerfilPublicoService.instance.sincronizar(
        Usuario(uid: uid, nome: nome, email: email),
      );
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
    }
  }

  // true se ja existe outro usuario com esse nome (comparacao normalizada) --
  // consulta a colecao publica, ja que "usuarios" so o proprio dono pode ler
  Future<bool> nomeJaExiste(String nome, {String? ignorarUid}) async {
    final normalizado = normalizarNome(nome);
    final query = await FirebaseFirestore.instance
        .collection('perfisPublicos')
        .where('nomeBusca', isEqualTo: normalizado)
        .get();
    return query.docs.any((doc) => doc.id != ignorarUid);
  }

  Future<void> atualizarPerfil(String uid, {String? nome, String? fotoUrl}) async {
    final dados = <String, dynamic>{};
    if (nome != null) {
      dados['nome'] = nome;
      dados['nomeBusca'] = normalizarNome(nome);
    }
    if (fotoUrl != null) dados['fotoUrl'] = fotoUrl;
    if (dados.isEmpty) return;
    await _colecao.doc(uid).update(dados);

    final atualizado = await buscarPorUid(uid);
    if (atualizado != null) await PerfilPublicoService.instance.sincronizar(atualizado);
  }

  // grava o formulario inteiro de "concluir perfil" de uma vez.
  //
  // O que ja foi definido no cadastro nunca vai no update de quem ja
  // finalizou: CPF/CNPJ porque sao identidade, tipo de conta, subtipo e papel
  // na imobiliaria porque decidem o que a conta pode fazer (anunciar, aprovar
  // corretor) e ja circularam em anuncio, chat e avaliacao -- virar "admin"
  // depois seria se promover a dono de uma empresa que alguem ja cadastrou.
  // As regras do Firestore recusariam
  // o update inteiro -- entao o que esta gravado prevalece sobre o que veio do
  // formulario. A tela ja bloqueia os campos, isto e a rede de seguranca
  static const List<String> _camposImutaveis = [
    'cpf', 'cnpj', 'tipoUsuario', 'subtipoCorretor', 'papelImobiliaria',
  ];

  Future<void> completarPerfil(Usuario usuario) async {
    final dados = usuario.toMap();
    final anterior = (await _colecao.doc(usuario.uid).get()).data();
    if (anterior != null && anterior['perfilCompleto'] == true) {
      for (final campo in _camposImutaveis) {
        final salvo = anterior[campo];
        if (salvo is String && salvo.isNotEmpty) dados[campo] = salvo;
      }
    }
    await _colecao.doc(usuario.uid).update(dados);
    await PerfilPublicoService.instance.sincronizar(usuario);
  }

  // Traz de volta a resposta da imobiliaria ao pedido de vinculo.
  //
  // Quem aprova (ou recusa) e OUTRA pessoa, e ela so alcanca "perfisPublicos"
  // -- as regras nao deixam ninguem escrever no documento de "usuarios" de
  // quem nao e ele mesmo. Entao o perfil do proprio corretor e que vem buscar
  // a resposta, na abertura do app: sem isso ele continuaria "pendente" pra
  // sempre do lado de ca, e o botao de anunciar nunca apareceria.
  //
  // Devolve o perfil atualizado (ou o mesmo, quando nao mudou nada)
  Future<Usuario> sincronizarVinculo(Usuario perfil) async {
    if (!perfil.ehCorretorDeEmpresa || perfil.imobiliariaId.isEmpty) return perfil;

    final publico = await PerfilPublicoService.instance.buscarPorUid(perfil.uid);
    if (publico == null || publico.imobiliariaId != perfil.imobiliariaId) return perfil;
    if (publico.vinculoConfirmado == perfil.vinculoConfirmado &&
        publico.vinculoRecusado == perfil.vinculoRecusado) {
      return perfil;
    }

    try {
      await _colecao.doc(perfil.uid).update({
        'vinculoConfirmado': publico.vinculoConfirmado,
        'vinculoRecusado': publico.vinculoRecusado,
      });
    } catch (e) {
      // sem a gravacao o app segue com o valor lido -- na proxima abertura
      // tenta de novo. Nao vale travar a tela do mapa por causa disso
      debugPrint('Não foi possível sincronizar o vínculo: $e');
    }
    return await buscarPorUid(perfil.uid) ?? perfil;
  }

  // marca "visto por ultimo agora" -- usado pro indicador de atividade
  Future<void> atualizarUltimoAcesso(String uid) async {
    await _colecao.doc(uid).update({'ultimoAcesso': FieldValue.serverTimestamp()});
    await PerfilPublicoService.instance.atualizarUltimoAcesso(uid);
  }
}
