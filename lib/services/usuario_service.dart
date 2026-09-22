import 'package:cloud_firestore/cloud_firestore.dart';
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
  // CPF e CNPJ de quem ja finalizou o cadastro nunca vao no update: o
  // documento e imutavel dali em diante (as regras do Firestore recusariam o
  // update inteiro), entao o que estiver gravado prevalece sobre o que veio
  // do formulario -- a tela ja bloqueia os campos, isto e a rede de seguranca
  Future<void> completarPerfil(Usuario usuario) async {
    final dados = usuario.toMap();
    final anterior = (await _colecao.doc(usuario.uid).get()).data();
    if (anterior != null && anterior['perfilCompleto'] == true) {
      for (final campo in ['cpf', 'cnpj']) {
        final salvo = anterior[campo];
        if (salvo is String && salvo.isNotEmpty) dados[campo] = salvo;
      }
    }
    await _colecao.doc(usuario.uid).update(dados);
    await PerfilPublicoService.instance.sincronizar(usuario);
  }

  // marca "visto por ultimo agora" -- usado pro indicador de atividade
  Future<void> atualizarUltimoAcesso(String uid) async {
    await _colecao.doc(uid).update({'ultimoAcesso': FieldValue.serverTimestamp()});
    await PerfilPublicoService.instance.atualizarUltimoAcesso(uid);
  }
}
