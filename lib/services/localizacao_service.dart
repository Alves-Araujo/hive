import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

// em que pe esta o acesso a localizacao do aparelho.
//
// O app inteiro funciona sem isso: a pessoa navega o mapa, abre anuncios,
// busca locais e ve a distancia ate a faculdade do mesmo jeito. O que exige
// permissao e so o que parte de ONDE ELA ESTA -- o ponto azul, centralizar,
// tracar rota e o modo "Ir".
enum EstadoLocalizacao {
  // ainda nao perguntamos ao sistema nesta sessao
  desconhecido,

  // permitida e com o GPS ligado: da pra usar tudo
  permitida,

  // recusou agora, mas o sistema ainda deixa perguntar de novo
  negada,

  // recusou de vez (no Android, depois da segunda recusa; no iOS, "nunca").
  // O dialogo do sistema nao aparece mais -- so pelos ajustes do aparelho
  negadaParaSempre,

  // permissao existe, mas a localizacao do aparelho esta desligada
  servicoDesligado,
}

// fonte unica da localizacao do usuario.
//
// Antes cada tela repetia o proprio checkPermission/requestPermission e, no
// "nao", so dava return ou um SnackBar generico -- a pessoa nao entendia o
// que tinha perdido nem como voltar atras, e o mapa ainda pedia permissao por
// fora (pelo myLocationEnabled) sem explicar nada. Aqui o estado fica em UM
// lugar, as telas escutam e se adaptam.
class LocalizacaoService {
  LocalizacaoService._();
  static final LocalizacaoService instance = LocalizacaoService._();

  final ValueNotifier<EstadoLocalizacao> estado =
      ValueNotifier(EstadoLocalizacao.desconhecido);

  // posicao ao vivo, atualizada enquanto o app esta aberto e a permissao
  // vale. Fica null quando nao ha permissao -- quem usa deve tratar isso
  final ValueNotifier<LatLng?> posicao = ValueNotifier(null);

  StreamSubscription<Position>? _inscricao;
  StreamSubscription<ServiceStatus>? _inscricaoServico;

  bool get permitida => estado.value == EstadoLocalizacao.permitida;

  // da pra tentar de novo pelo dialogo do sistema? Se nao, o caminho e os
  // ajustes do aparelho -- e a UI precisa dizer isso, senao o botao "Permitir"
  // nao faz nada e parece quebrado
  bool get podeTentarDeNovo =>
      estado.value != EstadoLocalizacao.negadaParaSempre;

  EstadoLocalizacao _traduzir(LocationPermission p, bool servicoAtivo) {
    if (p == LocationPermission.deniedForever) {
      return EstadoLocalizacao.negadaParaSempre;
    }
    if (p == LocationPermission.denied) return EstadoLocalizacao.negada;
    if (!servicoAtivo) return EstadoLocalizacao.servicoDesligado;
    return EstadoLocalizacao.permitida;
  }

  // le o estado atual SEM abrir nenhum dialogo.
  //
  // E o que roda na abertura do app: quem ja permitiu antes volta com tudo
  // funcionando, e quem nao permitiu nao leva um pedido na cara antes de ver
  // o app -- o pedido so aparece quando ela toca em algo que precisa
  Future<EstadoLocalizacao> verificar() async {
    final servicoAtivo = await Geolocator.isLocationServiceEnabled();
    final permissao = await Geolocator.checkPermission();
    final novo = _traduzir(permissao, servicoAtivo);
    _aplicar(novo);
    _ouvirServico();
    return novo;
  }

  // pede a permissao de verdade (abre o dialogo do sistema quando ele ainda
  // aparece). Devolve o estado depois da resposta
  Future<EstadoLocalizacao> pedir() async {
    var permissao = await Geolocator.checkPermission();

    if (permissao == LocationPermission.denied) {
      permissao = await Geolocator.requestPermission();
    }

    final servicoAtivo = await Geolocator.isLocationServiceEnabled();
    final novo = _traduzir(permissao, servicoAtivo);
    _aplicar(novo);
    _ouvirServico();
    return novo;
  }

  void _aplicar(EstadoLocalizacao novo) {
    estado.value = novo;
    if (novo == EstadoLocalizacao.permitida) {
      _acompanhar();
    } else {
      pararAcompanhamento();
      posicao.value = null;
    }
  }

  // acompanha a posicao em tempo real enquanto o app esta aberto.
  //
  // distanceFilter de 15 m de proposito: o ponto azul e a origem de rota nao
  // precisam de cada metro, e filtrar no sistema operacional gasta menos
  // bateria do que receber tudo e descartar no Dart. O modo "Ir" assina o
  // proprio stream, de alta precisao, e pausa este enquanto dura
  void _acompanhar() {
    if (_inscricao != null) return;
    _inscricao = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 15,
      ),
    ).listen(
      (p) => posicao.value = LatLng(p.latitude, p.longitude),
      onError: (_) {
        // o stream morre quando desligam a localizacao no meio do caminho;
        // o estado real vem do getServiceStatusStream logo abaixo
        posicao.value = null;
      },
    );
  }

  void pararAcompanhamento() {
    _inscricao?.cancel();
    _inscricao = null;
  }

  // ligar/desligar a localizacao pelo atalho do sistema nao passa por
  // permissao nenhuma -- sem escutar isso o app continuaria achando que pode
  // usar o GPS depois de a pessoa desliga-lo
  void _ouvirServico() {
    _inscricaoServico ??= Geolocator.getServiceStatusStream().listen((status) {
      if (status == ServiceStatus.disabled) {
        if (estado.value == EstadoLocalizacao.permitida) {
          _aplicar(EstadoLocalizacao.servicoDesligado);
        }
      } else if (estado.value == EstadoLocalizacao.servicoDesligado) {
        verificar();
      }
    });
  }

  // ultima posicao conhecida, ou uma leitura nova se ainda nao chegou
  // nenhuma. Null significa "nao da" -- sem permissao ou sem GPS
  Future<LatLng?> posicaoParaRota() async {
    if (!permitida) return null;
    final jaTem = posicao.value;
    if (jaTem != null) return jaTem;
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final convertida = LatLng(p.latitude, p.longitude);
      posicao.value = convertida;
      return convertida;
    } catch (_) {
      return null;
    }
  }

  // ajustes do app (permissao) ou do aparelho (GPS), conforme o caso
  Future<void> abrirAjustes() async {
    if (estado.value == EstadoLocalizacao.servicoDesligado) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}
