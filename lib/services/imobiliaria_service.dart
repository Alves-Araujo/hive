import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import '../models/imobiliaria.dart';
import '../models/perfil_publico.dart';
import '../utils/moderacao.dart';
import 'notificacao_service.dart';

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

  // acha a imobiliaria pelo cnpj ou cria uma nova, pendente de confirmacao --
  // retorna o id (usado como "imobiliariaId" no perfil do corretor)
  Future<String> encontrarOuCriar({
    required String nome,
    required String cnpj,
    required String email,
    required String endereco,
  }) async {
    final cnpjBusca = normalizarCnpj(cnpj);
    final existente = await _colecao.where('cnpjBusca', isEqualTo: cnpjBusca).limit(1).get();
    if (existente.docs.isNotEmpty) {
      final doc = existente.docs.first;
      // imobiliaria cadastrada antes de existir pin no mapa fica sem
      // coordenada pra sempre se ninguem preencher -- aproveita esse cadastro
      // pra completar, sem obrigar nada de quem esta se vinculando
      final dados = doc.data();
      if (dados['latitude'] == null && endereco.trim().isNotEmpty) {
        final posicao = await _geocodificar(endereco);
        if (posicao != null) {
          await doc.reference.update({
            'endereco': endereco,
            'latitude': posicao.latitude,
            'longitude': posicao.longitude,
          });
        }
      }
      return doc.id;
    }

    final novaImobiliaria = Imobiliaria(
      id: '',
      nome: nome,
      nomeBusca: normalizarNome(nome),
      cnpj: cnpj,
      cnpjBusca: cnpjBusca,
      email: email,
      emailBusca: email.toLowerCase().trim(),
      endereco: endereco,
      // o endereco e digitado como texto; o pin no mapa precisa de coordenada
      posicao: await _geocodificar(endereco),
    );
    final doc = await _colecao.add(novaImobiliaria.toMap());
    NotificacaoService.instance.avisarNovaImobiliaria(id: doc.id, nome: nome, endereco: endereco);
    return doc.id;
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

  // a imobiliaria desse e-mail, confirmada ou nao. Quem entra com ele e o
  // "administrador" dela: e por aqui que o app descobre que esta conta tem
  // pedidos de vinculo pra responder
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
  // A primeira resposta tambem confirma a imobiliaria: quem esta respondendo
  // provou ser o dono do e-mail dela ao entrar com ele
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
  // feito aqui pra nao precisar de indice composto no firestore
  Stream<List<PerfilPublico>> streamCorretoresVinculados(String imobiliariaId) {
    return FirebaseFirestore.instance
        .collection('perfisPublicos')
        .where('imobiliariaId', isEqualTo: imobiliariaId)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => PerfilPublico.fromMap(d.data(), d.id))
            .where((p) => p.vinculoConfirmado)
            .toList());
  }
}
