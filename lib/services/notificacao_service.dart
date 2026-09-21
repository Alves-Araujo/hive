import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/imovel.dart';
import '../models/notificacao.dart';
import '../utils/moeda.dart';

// Notificacoes DENTRO do app (sininho + aviso na tela). Nao e push: o
// projeto nao tem Cloud Functions, e push precisa de um servidor que dispare
// o envio. Aqui quem faz a acao grava o aviso no firestore e quem esta com o
// app aberto recebe em tempo real pelo listener.
//
// Mesmo padrao do resto do app (ValueNotifier global, sem pacote de estado):
// TelaPrincipal liga ao entrar e desliga ao sair, e qualquer tela le daqui.
class NotificacaoService {
  NotificacaoService._();
  static final NotificacaoService instance = NotificacaoService._();

  static const int _limite = 40;

  final _db = FirebaseFirestore.instance;

  // lista unica, das duas origens, mais recente primeiro
  final ValueNotifier<List<Notificacao>> notificacoes = ValueNotifier([]);
  final ValueNotifier<int> naoLidas = ValueNotifier(0);

  // cada aviso que chega com o app aberto passa por aqui -- a TelaPrincipal
  // escuta e mostra o aviso flutuante
  final ValueNotifier<Notificacao?> ultimaRecebida = ValueNotifier(null);

  // chat aberto agora: mensagem nova DESSE chat nao vira aviso flutuante,
  // a pessoa ja esta lendo
  String? chatAberto;

  String? _uid;
  DateTime? _lidasAte;
  List<Notificacao> _gerais = [];
  List<Notificacao> _pessoais = [];
  final List<StreamSubscription> _inscricoes = [];

  CollectionReference<Map<String, dynamic>> get _colecaoGeral => _db.collection('notificacoes');

  CollectionReference<Map<String, dynamic>> _colecaoPessoal(String uid) =>
      _db.collection('usuarios').doc(uid).collection('notificacoes');

  void iniciar(String uid) {
    if (_uid == uid) return;
    parar();
    _uid = uid;

    _inscricoes.add(_db.collection('usuarios').doc(uid).snapshots().listen((doc) {
      final lidasEm = (doc.data()?['notificacoesLidasEm'] as Timestamp?)?.toDate();
      // logo depois de marcar como lidas o horario do servidor ainda esta
      // pendente e chega nulo -- mantem o valor local em vez de voltar tudo
      // pra "nao lida" por um instante
      if (lidasEm == null && doc.metadata.hasPendingWrites) return;
      _lidasAte = lidasEm;
      _recalcular();
    }, onError: (e) => debugPrint('Notificações (leitura): $e')));

    _inscricoes.add(_ouvir(
      _colecaoGeral.orderBy('criadoEm', descending: true).limit(_limite),
      (lista) => _gerais = lista,
    ));
    _inscricoes.add(_ouvir(
      _colecaoPessoal(uid).orderBy('criadoEm', descending: true).limit(_limite),
      (lista) => _pessoais = lista,
    ));
  }

  StreamSubscription _ouvir(
    Query<Map<String, dynamic>> consulta,
    void Function(List<Notificacao>) guardar,
  ) {
    var primeiraCarga = true;
    return consulta.snapshots().listen((snap) {
      // o proprio autor nao e avisado do que ele mesmo fez
      guardar(snap.docs.map(Notificacao.fromDoc).where((n) => n.autorUid != _uid).toList());
      _recalcular();

      // a primeira carga e o historico, nao novidade -- so avisa o que
      // chegar depois que o app ja esta aberto
      if (!primeiraCarga) {
        for (final mudanca in snap.docChanges) {
          if (mudanca.type != DocumentChangeType.added) continue;
          final nova = Notificacao.fromDoc(mudanca.doc);
          if (nova.autorUid != _uid) ultimaRecebida.value = nova;
        }
      }
      primeiraCarga = false;
    }, onError: (e) => debugPrint('Notificações: $e'));
  }

  void _recalcular() {
    final todas = [..._gerais, ..._pessoais]
      ..sort((a, b) => (b.criadoEm ?? DateTime.now()).compareTo(a.criadoEm ?? DateTime.now()));
    notificacoes.value = todas;
    naoLidas.value = todas.where(naoLida).length;
  }

  bool naoLida(Notificacao n) {
    if (_lidasAte == null) return true;
    return n.criadoEm != null && n.criadoEm!.isAfter(_lidasAte!);
  }

  // "li tudo ate agora" -- um horario so no perfil, em vez de marcar aviso
  // por aviso (os gerais sao compartilhados, nao da pra gravar "lido" neles)
  Future<void> marcarTodasComoLidas() async {
    final uid = _uid;
    if (uid == null || naoLidas.value == 0) return;
    _lidasAte = DateTime.now();
    _recalcular();
    try {
      await _db.collection('usuarios').doc(uid).update({
        'notificacoesLidasEm': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Não foi possível marcar as notificações como lidas: $e');
    }
  }

  void parar() {
    for (final s in _inscricoes) {
      s.cancel();
    }
    _inscricoes.clear();
    _uid = null;
    _lidasAte = null;
    _gerais = [];
    _pessoais = [];
    chatAberto = null;
    notificacoes.value = [];
    naoLidas.value = 0;
    ultimaRecebida.value = null;
  }

  // ---------------------------------------------------------------------------
  // gravacao. Aviso e acessorio: se falhar (rede, regra), a acao principal
  // (publicar, mandar mensagem...) ja deu certo e nao pode ser desfeita por
  // isso -- entao nenhum destes metodos lanca erro

  Future<void> _gravar(CollectionReference<Map<String, dynamic>> colecao, Notificacao n) async {
    try {
      await colecao.add(n.toMap());
    } catch (e) {
      debugPrint('Não foi possível gravar a notificação: $e');
    }
  }

  String get _meuUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  Future<void> avisarNovoAnuncio(Imovel imovel) {
    final ehEvento = imovel.tipo == TipoListing.evento;
    final local = [imovel.bairro, imovel.cidade].where((p) => p.isNotEmpty).join(', ');
    final detalhes = <String>[
      if (!ehEvento && imovel.tipoImovel.isNotEmpty) imovel.tipoImovel,
      if (local.isNotEmpty) local,
      if (imovel.preco > 0) ehEvento ? formatarPreco(imovel.preco) : '${formatarPreco(imovel.preco)}/mês',
    ];
    return _gravar(
      _colecaoGeral,
      Notificacao(
        id: '',
        tipo: ehEvento ? TipoNotificacao.novoEvento : TipoNotificacao.novaMoradia,
        titulo: ehEvento ? 'Novo evento: ${imovel.titulo}' : 'Nova moradia: ${imovel.titulo}',
        corpo: detalhes.join(' · '),
        autorUid: _meuUid,
        alvoId: imovel.id,
      ),
    );
  }

  Future<void> avisarNovaImobiliaria({required String id, required String nome, required String endereco}) {
    return _gravar(
      _colecaoGeral,
      Notificacao(
        id: '',
        tipo: TipoNotificacao.novaImobiliaria,
        titulo: 'Nova imobiliária: $nome',
        corpo: endereco.isNotEmpty ? endereco : 'Agora no Hive',
        autorUid: _meuUid,
        alvoId: id,
      ),
    );
  }

  // contatoUid e com quem o DESTINATARIO conversa ao abrir o aviso
  Future<void> avisarNovaMensagem({
    required Iterable<String> destinatarios,
    required String remetenteNome,
    required String previa,
    required String chatId,
    required String contatoUid,
    String imovelTitulo = '',
  }) async {
    final eu = _meuUid;
    final aviso = Notificacao(
      id: '',
      tipo: TipoNotificacao.novaMensagem,
      titulo: imovelTitulo.isNotEmpty ? '$remetenteNome · $imovelTitulo' : remetenteNome,
      corpo: previa,
      autorUid: eu,
      alvoId: chatId,
      contatoUid: contatoUid,
      imovelTitulo: imovelTitulo,
    );
    await Future.wait(destinatarios
        .where((uid) => uid.isNotEmpty && uid != eu)
        .toSet()
        .map((uid) => _gravar(_colecaoPessoal(uid), aviso)));
  }

  Future<void> avisarNovaAvaliacao({
    required String avaliadoUid,
    required String avaliadorNome,
    required int nota,
    String comentario = '',
  }) {
    if (avaliadoUid.isEmpty || avaliadoUid == _meuUid) return Future.value();
    return _gravar(
      _colecaoPessoal(avaliadoUid),
      Notificacao(
        id: '',
        tipo: TipoNotificacao.novaAvaliacao,
        titulo: '$avaliadorNome te avaliou com $nota ${nota == 1 ? 'estrela' : 'estrelas'}',
        corpo: comentario.isNotEmpty ? comentario : 'Toque para ver seu perfil',
        autorUid: _meuUid,
        alvoId: avaliadoUid,
      ),
    );
  }
}
