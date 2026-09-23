import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import '../models/imobiliaria.dart';
import '../models/perfil_publico.dart';
import '../utils/moderacao.dart';
import 'notificacao_service.dart';

// CNPJ que ja tem cadastro no app. Quem esbarra nisso nao e dono de nada
// ainda: ou a empresa dele ja esta aqui (e ele entra como corretor da equipe,
// pedindo aprovacao), ou e um cadastro antigo sem dono, que precisa de suporte.
// Adotar o cadastro alheio automaticamente seria entregar uma empresa -- e os
// corretores dela -- pra quem souber digitar o CNPJ
class ImobiliariaJaCadastradaException implements Exception {
  final Imobiliaria existente;
  ImobiliariaJaCadastradaException(this.existente);

  @override
  String toString() => 'Imobiliária já cadastrada: ${existente.nome}';
}

class ImobiliariaService {
  ImobiliariaService._();
  static final ImobiliariaService instance = ImobiliariaService._();

  final _colecao = FirebaseFirestore.instance.collection('imobiliarias');

  static String normalizarCnpj(String cnpj) => cnpj.replaceAll(RegExp(r'\D'), '');

  Future<Imobiliaria?> buscarPorId(String id) async {
    if (id.isEmpty) return null;
    final doc = await _colecao.doc(id).get();
    if (!doc.exists) return null;
    return Imobiliaria.fromMap(doc.data()!, doc.id);
  }

  // as imobiliarias ja cadastradas, em ordem alfabetica -- e a lista que o
  // corretor escolhe no cadastro. Sao poucas e o cadastro e uma tela so, entao
  // vem todas de uma vez e o filtro por texto e feito na memoria (o Firestore
  // nao filtra "contem", so prefixo)
  Future<List<Imobiliaria>> listarTodas() async {
    final snap = await _colecao.orderBy('nomeBusca').get();
    return snap.docs.map((d) => Imobiliaria.fromMap(d.data(), d.id)).toList();
  }

  // A imobiliaria cadastrada pela conta master dela, no proprio "concluir
  // perfil" -- o UNICO jeito de criar uma imobiliaria no app.
  //
  // Antes existia um "cadastrar nova" solto na folha de escolha do corretor:
  // ele digitava os dados da empresa e o e-mail que ficava gravado era o DA
  // EMPRESA, nao o da conta dele. Como o dono era deduzido do e-mail, o
  // cadastro nascia sem ninguem por ele: quem criou nao editava, nao aprovava
  // corretor, e os pedidos de vinculo ficavam pendentes pra sempre.
  //
  // Agora o dono e o uid de quem cadastra (donoUid), gravado junto, e o e-mail
  // e o da propria conta -- os dois criterios apontam pra mesma pessoa.
  //
  // Devolve a imobiliaria com o id que o Firestore deu. Se o CNPJ ja tiver
  // cadastro, levanta ImobiliariaJaCadastradaException em vez de criar a
  // segunda copia da mesma empresa
  Future<Imobiliaria> criarParaDono({
    required String donoUid,
    required String nome,
    required String cnpj,
    required String telefone,
    required String endereco,
    required String email,
    required bool emailVerificado,
  }) async {
    final cnpjBusca = normalizarCnpj(cnpj);
    final existente = await _colecao.where('cnpjBusca', isEqualTo: cnpjBusca).limit(1).get();
    if (existente.docs.isNotEmpty) {
      final doc = existente.docs.first;
      throw ImobiliariaJaCadastradaException(
        Imobiliaria.fromMap(doc.data(), doc.id),
      );
    }

    final nova = Imobiliaria(
      id: '',
      donoUid: donoUid,
      nome: nome,
      nomeBusca: normalizarNome(nome),
      cnpj: cnpj,
      cnpjBusca: cnpjBusca,
      email: email,
      emailBusca: email.toLowerCase().trim(),
      // nasce sempre nao confirmada, e a confirmacao vai num update separado
      // logo abaixo -- ver o comentario de lá
      emailVerificado: false,
      telefone: telefone,
      endereco: endereco,
      // o endereco e digitado como texto; o pin no mapa precisa de coordenada
      posicao: await _geocodificar(endereco),
    );
    final doc = await _colecao.add(nova.toMap());
    NotificacaoService.instance.avisarNovaImobiliaria(id: doc.id, nome: nome, endereco: endereco);

    // A confirmacao do e-mail vem num update separado, e nao no create, de
    // proposito: a regra PUBLICADA hoje so aceita create com emailVerificado
    // false (ela e de quando o e-mail gravado era o da EMPRESA e ninguem tinha
    // provado nada sobre ele). Como agora o e-mail e o da propria conta, este
    // update passa pelas duas versoes da regra -- entao o cadastro funciona
    // igual antes e depois de as regras novas subirem pro projeto.
    //
    // Nada no app depende dessa confirmacao pra conta master editar o cadastro
    // ou aprovar corretor: quem decide isso e o donoUid. Ela e so o selo
    // "Cadastro confirmado" que aparece no painel do pin, entao se o update for
    // recusado a imobiliaria fica sem selo e segue funcionando
    var confirmada = false;
    if (emailVerificado) {
      try {
        await doc.update({'emailVerificado': true});
        confirmada = true;
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
        debugPrint('A imobiliária ficou sem o selo de cadastro confirmado: ${e.code}');
      }
    }

    return Imobiliaria.fromMap(
      {...nova.toMap(), 'emailVerificado': confirmada},
      doc.id,
    );
  }

  // a imobiliaria desta conta master. E o criterio novo de "quem manda nela":
  // vale mesmo quando o e-mail da conta nao e o que esta gravado no cadastro
  Future<Imobiliaria?> buscarPorDono(String uid) async {
    if (uid.isEmpty) return null;
    final query = await _colecao.where('donoUid', isEqualTo: uid).limit(1).get();
    if (query.docs.isEmpty) return null;
    return Imobiliaria.fromMap(query.docs.first.data(), query.docs.first.id);
  }

  // O bloco que a conta master reedita ao voltar em "concluir perfil": nome,
  // telefone e endereco da sede. Descricao, logotipo e galeria ficam de fora
  // porque ali nao ha campo pra eles -- quem mexe nisso e a
  // EditarImobiliariaScreen, e mandar vazio daqui apagaria o que ela salvou.
  // O CNPJ tambem nao vem: e a chave que identifica a empresa
  Future<Imobiliaria> atualizarDadosDaSede({
    required Imobiliaria atual,
    required String nome,
    required String telefone,
    required String endereco,
  }) async {
    final dados = <String, dynamic>{
      'nome': nome,
      'nomeBusca': normalizarNome(nome),
      'telefone': telefone,
      'endereco': endereco,
    };

    // mesma regra da tela de edicao: endereco novo pede coordenada nova, e sem
    // coordenada o pin sai do mapa em vez de ficar apontando pro lugar errado
    final mudouEndereco = endereco.trim() != atual.endereco.trim();
    LatLng? posicao = atual.posicao;
    if (mudouEndereco) {
      posicao = await _geocodificar(endereco);
      dados['latitude'] = posicao?.latitude ?? FieldValue.delete();
      dados['longitude'] = posicao?.longitude ?? FieldValue.delete();
    }

    await _colecao.doc(atual.id).update(dados);

    return atual.copiarCom(
      nome: nome,
      nomeBusca: normalizarNome(nome),
      telefone: telefone,
      endereco: endereco,
      posicao: posicao,
      limparPosicao: mudouEndereco && posicao == null,
    );
  }

  // Atualiza o cadastro da propria imobiliaria -- quem chama e a conta master
  // dela (ver buscarPorDono e EditarImobiliariaScreen).
  //
  // Vai so o bloco editavel no update: CNPJ, e-mail e dono ficam de fora porque
  // sao o que identifica a empresa (o CNPJ e a chave que impede dois cadastros
  // pro mesmo numero; e-mail e donoUid decidem QUEM responde por ela -- trocar
  // um deles aqui seria entregar a imobiliaria pra outra conta). As regras do
  // Firestore recusam o update que mexer neles, entao nem adianta mandar.
  //
  // Devolve a imobiliaria ja com os valores novos, pra tela nao precisar
  // reler o documento so pra se redesenhar
  Future<Imobiliaria> atualizarPerfil({
    required Imobiliaria atual,
    required String nome,
    required String descricao,
    required String telefone,
    required String endereco,
    required String fotoUrl,
    required List<String> fotos,
  }) async {
    final dados = <String, dynamic>{
      'nome': nome,
      'nomeBusca': normalizarNome(nome),
      'descricao': descricao,
      'telefone': telefone,
      'fotoUrl': fotoUrl,
      'fotos': fotos,
      'endereco': endereco,
    };

    // endereco novo pede coordenada nova: manter a antiga deixaria o pin do
    // mapa apontando pro escritorio de onde a imobiliaria acabou de sair.
    // Quando o geocoder nao reconhece o endereco novo, a coordenada e APAGADA
    // -- sai do mapa ate alguem corrigir, que e melhor que ficar errada
    final mudouEndereco = endereco.trim() != atual.endereco.trim();
    LatLng? posicao = atual.posicao;
    if (mudouEndereco) {
      posicao = await _geocodificar(endereco);
      dados['latitude'] = posicao?.latitude ?? FieldValue.delete();
      dados['longitude'] = posicao?.longitude ?? FieldValue.delete();
    }

    await _colecao.doc(atual.id).update(dados);

    return atual.copiarCom(
      nome: nome,
      nomeBusca: normalizarNome(nome),
      descricao: descricao,
      telefone: telefone,
      fotoUrl: fotoUrl,
      fotos: fotos,
      endereco: endereco,
      posicao: posicao,
      limparPosicao: mudouEndereco && posicao == null,
    );
  }

  // endereco escrito -> coordenada. Null quando o servico nao reconhece o
  // endereco: a imobiliaria e cadastrada do mesmo jeito, so nao entra no mapa
  Future<LatLng?> _geocodificar(String endereco) async {
    if (endereco.trim().isEmpty) return null;
    try {
      final locais = await Geocoding().locationFromAddress(endereco);
      if (locais.isEmpty) return null;
      return LatLng(locais.first.latitude, locais.first.longitude);
    } catch (e) {
      debugPrint('Não foi possível geocodificar a imobiliária: $e');
      return null;
    }
  }

  // imobiliarias com coordenada -- as unicas que tem como aparecer no mapa
  Stream<List<Imobiliaria>> streamComPosicao() {
    return _colecao.snapshots().map((snap) => snap.docs
        .map((d) => Imobiliaria.fromMap(d.data(), d.id))
        .where((i) => i.posicao != null)
        .toList());
  }

  // a imobiliaria desse e-mail, confirmada ou nao. E o criterio ANTIGO de
  // "quem manda nela", de quando a imobiliaria nao tinha donoUid: quem entra
  // com o e-mail gravado no cadastro responde pelos corretores dele. Continua
  // existindo pelos cadastros feitos antes disso -- em cadastro novo os dois
  // criterios apontam pra mesma conta (ver criarParaDono)
  Future<Imobiliaria?> buscarPorEmail(String email) async {
    final emailBusca = email.toLowerCase().trim();
    final query = await _colecao.where('emailBusca', isEqualTo: emailBusca).limit(1).get();
    if (query.docs.isEmpty) return null;
    return Imobiliaria.fromMap(query.docs.first.data(), query.docs.first.id);
  }

  // corretores que pediram vinculo e ainda nao foram respondidos. Le da
  // colecao publica (a "usuarios" so o proprio dono le) e filtra aqui, pra nao
  // precisar de indice composto
  Future<List<PerfilPublico>> vinculosPendentes(String imobiliariaId) async {
    final snap = await FirebaseFirestore.instance
        .collection('perfisPublicos')
        .where('imobiliariaId', isEqualTo: imobiliariaId)
        .get();
    return snap.docs
        .map((d) => PerfilPublico.fromMap(d.data(), d.id))
        .where((p) => p.vinculoPendente)
        .toList();
  }

  // Responde UM pedido -- aprovar libera o corretor a anunciar pela
  // imobiliaria; recusar deixa registrado, pra ele poder escolher outra.
  //
  // So mexe na colecao publica: quem responde nao e o dono do perfil do
  // corretor, entao nao pode escrever no documento dele em "usuarios" (o
  // proprio corretor puxa a resposta de volta na abertura seguinte do app --
  // ver UsuarioService.sincronizarVinculo).
  //
  // A primeira resposta tambem confirma a imobiliaria, nos cadastros antigos em
  // que a confirmacao ficou pendente: quem esta respondendo provou ser o dono
  // do e-mail dela ao entrar com ele. Cadastro novo ja nasce confirmado, porque
  // o e-mail e o da propria conta master (ver criarParaDono)
  Future<void> responderVinculo({
    required String imobiliariaId,
    required String corretorUid,
    required bool aprovado,
  }) async {
    final imobiliaria = await _colecao.doc(imobiliariaId).get();
    if (imobiliaria.data()?['emailVerificado'] != true) {
      await _colecao.doc(imobiliariaId).update({'emailVerificado': true});
    }

    // um campo por vez: as regras so aceitam a mudanca de UM deles por update,
    // justamente pra esse acesso de terceiro nao virar escrita livre no perfil
    final campo = aprovado ? 'vinculoConfirmado' : 'vinculoRecusado';
    await FirebaseFirestore.instance
        .collection('perfisPublicos')
        .doc(corretorUid)
        .set({campo: true}, SetOptions(merge: true));

    await NotificacaoService.instance.avisarRespostaDeVinculo(
      corretorUid: corretorUid,
      imobiliariaId: imobiliariaId,
      nomeImobiliaria: imobiliaria.data()?['nome'] ?? 'a imobiliária',
      aprovado: aprovado,
    );
  }

  // corretores confirmados dessa imobiliaria -- le da colecao publica (nao
  // da "usuarios", que so o proprio dono pode ler); filtro de confirmado
  // feito aqui pra nao precisar de indice composto no firestore.
  //
  // A conta master entra na lista sem vinculo confirmado: ela nao pediu
  // aprovacao a ninguem, e responder pela empresa ja e mais que trabalhar nela.
  // Sem isso, a imobiliaria de um corretor sozinho aparecia "sem corretor
  // vinculado" no proprio perfil publico
  Stream<List<PerfilPublico>> streamCorretoresVinculados(String imobiliariaId) {
    return FirebaseFirestore.instance
        .collection('perfisPublicos')
        .where('imobiliariaId', isEqualTo: imobiliariaId)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => PerfilPublico.fromMap(d.data(), d.id))
            .where((p) => p.vinculoConfirmado || p.ehAdminImobiliaria)
            .toList());
  }
}
