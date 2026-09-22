import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle, FilteringTextInputFormatter;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart' show TravelMode;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'concluir_perfil_screen.dart';
import 'detalhes_imovel_screen.dart';
import 'novo_anuncio_screen.dart';
import 'notificacoes_screen.dart';
import '../main.dart';
import '../models/imobiliaria.dart';
import '../models/imovel.dart';
import '../models/filtro_state.dart';
import '../models/usuario.dart';
import '../services/auth_service.dart';
import '../services/busca_service.dart';
import '../services/imobiliaria_service.dart';
import '../services/localizacao_service.dart';
import '../services/lugares_service.dart';
import '../services/notificacao_service.dart';
import '../services/rota_service.dart';
import '../services/usuario_service.dart';
import '../utils/cor_foto.dart';
import '../utils/distancia.dart';
import '../utils/icones_tag.dart';
import '../utils/moeda.dart';
import '../utils/pins_mapa.dart';
import '../utils/moderacao.dart';
import '../widgets/avatar_widget.dart';
import '../widgets/glass_card.dart';
import '../widgets/painel_inatel.dart';
import '../widgets/painel_localizacao.dart';
import '../widgets/painel_lugar.dart';
import '../widgets/pressionavel.dart';
import '../widgets/animated_gradient_button.dart';

class CentroDoMapa extends StatefulWidget {
  final Usuario perfil;

  const CentroDoMapa({super.key, required this.perfil});

  @override
  State<CentroDoMapa> createState() => _CentroDoMapaState();
}

class _CentroDoMapaState extends State<CentroDoMapa>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {

  GoogleMapController? _mapController;

  final TextEditingController _buscaController = TextEditingController();
  final FocusNode _buscaFocusNode = FocusNode();
  Timer? _debounceSugestoes;
  // as sugestoes vem de duas fontes com tempos MUITO diferentes: a local e
  // instantanea (filtro em memoria), a online leva de 200 ms a 3 s. Guardar
  // as duas separadas e o que permite a lista crescer sem nunca piscar --
  // quando as duas dividiam a mesma lista, cada tecla apagava o que a
  // internet tinha acabado de trazer, e a pessoa via o resultado sumir
  List<SugestaoBusca> _sugestoesLocais = [];
  List<SugestaoBusca> _sugestoesOnline = [];
  bool _buscandoOnline = false;

  // lista mostrada: locais primeiro (sao as mais provaveis e ja estao certas),
  // depois as online que ainda casam com o que esta escrito agora
  List<SugestaoBusca> get _sugestoes {
    final palavras = BuscaService.instance.palavras(_buscaController.text);
    if (palavras.isEmpty) return const [];

    final vistos = <String>{};
    final juntas = <SugestaoBusca>[];
    for (final s in [..._sugestoesLocais, ..._sugestoesOnline]) {
      if (!vistos.add(normalizarNome(s.texto))) continue;
      juntas.add(s);
      if (juntas.length >= 8) break;
    }
    return juntas;
  }

  String _modoMapaAtual = 'Normal';

  late Usuario _perfilAtual;

  String _estiloMapaEscuro = '';
  String _estiloMapaLimpo = '';
  String? _estiloAtivo;

  final FiltroState _filtroState = FiltroState();

  Set<Marker> _marcadores = {};

  // pins desenhados uma vez e reusados. Ficam nulos ate _prepararPins()
  // terminar; enquanto isso os markers saem com o icone padrao, o que evita
  // a tela abrir sem marcador nenhum
  // um trio (normal, origem, destino) por tipo de anuncio
  Map<TipoPin, (BitmapDescriptor, BitmapDescriptor, BitmapDescriptor)> _pinsAnuncio = {};
  BitmapDescriptor? _pinInatel;
  BitmapDescriptor? _pinInatelOrigem;
  BitmapDescriptor? _pinInatelDestino;
  Marker? _marcadorInatel;

  // imobiliarias cadastradas com endereco geocodificado
  BitmapDescriptor? _pinImobiliaria;
  List<Imobiliaria> _imobiliarias = [];
  Set<Marker> _marcadoresImobiliarias = {};
  StreamSubscription<List<Imobiliaria>>? _inscricaoImobiliarias;

  // mercado, farmacia, posto, hotel e hospital mais perto de cada moradia
  // (Google Places). Por id do Google: duas republicas vizinhas costumam ter
  // a mesma farmacia como a mais perto, e o pin sairia duplicado
  Map<String, Lugar> _lugares = {};
  // os que aparecem sempre (ver LugaresService.fixos). Ficam em campo
  // separado porque _lugares e trocado inteiro a cada busca nova, e eles nao
  // podem sumir junto
  Map<String, Lugar> _lugaresFixos = {};
  // os estabelecimentos da cidade inteira (ver LugaresService.naCidade). Sao
  // eles que dao ao mapa as farmacias, os postos e os hospitais: o campo
  // _lugares acima so tem o que esta perto de algum ANUNCIO, entao sem
  // anuncio carregado ele vem vazio e sobravam so os mercados de _lugaresFixos
  Map<String, Lugar> _lugaresCidade = {};
  Set<Marker> _marcadoresLugares = {};
  // o que cada moradia tem por perto, por id do anuncio -- e o que o grupo
  // "Localidade" do filtro consulta. Fica vazio enquanto a busca nao volta
  // (ou se a Places falhar), e nesse caso o filtro de localidade avisa em vez
  // de esconder tudo em silencio
  Map<String, Set<CategoriaLugar>> _categoriasPerto = {};
  // posicoes de moradia ja consultadas -- o snapshot dos imoveis dispara a
  // cada mudanca no banco, e sem isso cada edicao de anuncio refaria tudo
  String _chaveLugaresConsultados = '';

  // --- modo navegacao ("Ir") ---
  bool _navegando = false;
  StreamSubscription<Position>? _inscricaoNav;
  Position? _posicaoNav;
  BitmapDescriptor? _setaNav;
  // rumo suavizado. Guardado a parte do GPS porque a leitura crua oscila e
  // faria o mapa tremer a cada frame
  double _rumoSuave = 0;
  // limita a frequencia das animacoes de camera -- ver _aoMoverNavegando
  DateTime _ultimoAjusteCamera = DateTime.fromMillisecondsSinceEpoch(0);
  // o usuario arrastou o mapa: para de seguir ate ele recentralizar
  bool _seguindoCamera = true;
  // metros que faltam SEGUINDO A ROTA (ver TrilhaRota) -- antes era linha
  // reta, que numa malha de quarteiroes chega a mostrar metade do caminho real
  double? _metrosRestantes;
  // tempo restante estimado, proporcional ao trecho que falta
  int? _segundosRestantes;
  // rota preparada pra consulta rapida; refeita quando o trajeto muda
  TrilhaRota? _trilhaNav;
  // recalculo automatico quando o usuario sai do trajeto
  bool _recalculandoRota = false;
  DateTime _ultimoRecalculo = DateTime.fromMillisecondsSinceEpoch(0);
  bool _buscaComTexto = false;

  // destaque visual do resultado de busca selecionado -- rua vira linha
  // solida, bairro/regiao vira contorno tracejado SEM preenchimento (igual o
  // Google Maps mostra), ponto de interesse vira marker
  Set<Polyline> _destaqueRuaBusca = {};
  Set<Polyline> _destaqueAreaBusca = {};
  Set<Polygon> _preenchimentoAreaBusca = {};
  Marker? _destaquePoiBusca;

  // contorno do bairro chegando (busca no Overpass depois da escolha)
  bool _carregandoContorno = false;

  // ultimo resultado de busca escolhido -- fica guardado pra oferecer o
  // "Traçar rota" ate ele (igual o Google Maps, que mostra o botao de rotas
  // no card do local depois que voce seleciona um ponto da busca)
  SugestaoBusca? _localSelecionado;

  // true enquanto o campo de busca deve ser editavel. Precisa ser estado
  // proprio e nao derivar de _buscaFocusNode.hasFocus: quando o rotulo esta
  // em tela o TextField nao existe na arvore, entao o FocusNode nao esta
  // anexado a nada e requestFocus() nao tem onde aplicar -- o toque no rotulo
  // nao devolvia a edicao
  bool _editandoBusca = false;
  bool _buscandoOrigemRota = false;

  List<Imovel> _imoveisDoBanco = [];

  // estado visual da rota (markers/polyline) montado a partir de
  // rotaAtivaGlobal/rotaCarregandoGlobal -- o calculo em si roda fora dessa
  // tela (ver main.dart e rota_service.dart) porque essa State e recriada
  // toda vez que o usuario troca de aba, entao nao pode ser a dona do
  // Future -- so espelha o que ja esta pronto globalmente
  Set<Marker> _marcadoresRota = {};
  Set<Polyline> _rotas = {};
  RotaAtiva? _rotaAtual;
  bool _carregandoRota = false;
  // so pra destacar o icone certo no seletor de transporte -- guardado a
  // parte do RotaAtiva.modo porque "moto" nao existe na Directions API
  // classica, entao na hora de pedir a rota ele vira "carro" por baixo dos
  // panos (ver _trocarModoTransporte), mas a UI continua mostrando moto selecionada
  TravelMode _modoTransporteUi = TravelMode.driving;

  late VoidCallback _temaListener;
  late VoidCallback _filtroListener;
  late VoidCallback _rotaAtivaListener;
  late VoidCallback _rotaCarregandoListener;
  late VoidCallback _rotaErroListener;
  late VoidCallback _localizacaoListener;
  late VoidCallback _bairroListener;

  late AnimationController _animIniciaisController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _perfilAtual = widget.perfil;
    _carregarDadosUsuarioLogado();
    _carregarEstilosDoAsset();
    // le o estado da permissao SEM pedir nada e, se ja houver, liga o
    // acompanhamento em tempo real
    LocalizacaoService.instance.verificar();
    _localizacaoListener = () {
      if (mounted) setState(() {});
    };
    LocalizacaoService.instance.estado.addListener(_localizacaoListener);
    _verificarVinculoPendente();

    _animIniciaisController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(parent: _animIniciaisController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animIniciaisController, curve: Curves.easeOutCubic));
    _animIniciaisController.forward();

    // imobiliarias com endereco geocodificado -- atualiza ao vivo, igual os
    // imoveis, entao uma que acaba de se cadastrar ja aparece no mapa
    _inscricaoImobiliarias =
        ImobiliariaService.instance.streamComPosicao().listen((lista) {
      if (!mounted) return;
      setState(() {
        _imobiliarias = lista;
        _atualizarMarcadoresImobiliarias();
      });
    });

    FirebaseFirestore.instance.collection('imoveis').snapshots().listen((snapshot) {
      if (mounted) {
        setState(() {
          _imoveisDoBanco = snapshot.docs
              .map((doc) => Imovel.fromMap(doc.data(), doc.id))
              .toList();
        });
        _atualizarMarcadoresFiltrados();
        _carregarLugaresProximos();
      }
    });

    // nenhum dos dois depende de anuncio, entao nao esperam o Firestore
    _carregarLugaresFixos();
    _carregarLugaresDaCidade();

    _temaListener = () {
      if (mounted) {
        _atualizarEstiloMapa();
        // as polylines das alternativas tem cor dependente do tema (ver
        // _sincronizarComRotaGlobal) e ficam guardadas em campo, entao
        // precisam ser remontadas aqui -- um setState vazio nao as atualiza
        setState(_sincronizarComRotaGlobal);
      }
    };
    temaGlobal.addListener(_temaListener);

    _filtroListener = () {
      if (!mounted) return;
      // a categoria manda nos pins de estabelecimento tambem, que ficam fora
      // de _marcadores -- por isso os dois conjuntos sao remontados aqui
      setState(_atualizarMarcadoresLugares);
      _atualizarMarcadoresFiltrados();
    };
    _filtroState.addListener(_filtroListener);

    // espelha o resultado/estado de carregamento da rota, que sao globais
    // (ver comentario nos campos acima) -- inclui o valor JA atual na hora
    // de montar essa tela, pra cobrir o caso de trocar de aba enquanto uma
    // rota ainda esta sendo calculada em outra instancia que ja foi destruida
    _sincronizarComRotaGlobal();
    _rotaAtivaListener = () {
      if (mounted) _atualizarEstadoDaRota();
    };
    rotaAtivaGlobal.addListener(_rotaAtivaListener);
    _rotaCarregandoListener = () {
      if (!mounted) return;
      setState(() {
        _carregandoRota = rotaCarregandoGlobal.value;
        // o recalculo acabou -- inclusive quando falhou, senao um erro de
        // rede travaria o "Recalculando" na tela pra sempre
        if (!_carregandoRota) _recalculandoRota = false;
      });
    };
    rotaCarregandoGlobal.addListener(_rotaCarregandoListener);
    _rotaErroListener = () {
      final erro = rotaErroGlobal.value;
      if (erro == null || !mounted) return;
      rotaErroGlobal.value = null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível calcular a rota: $erro'), backgroundColor: corErro),
      );
    };
    rotaErroGlobal.addListener(_rotaErroListener);

    _bairroListener = () {
      final pedido = bairroPendenteGlobal.value;
      if (pedido == null || !mounted) return;
      bairroPendenteGlobal.value = null;
      _mostrarBairroNoMapa(pedido);
    };
    bairroPendenteGlobal.addListener(_bairroListener);

    _buscaController.addListener(() {
      setState(() {
        _buscaComTexto = _buscaController.text.isNotEmpty;
        if (!_buscaComTexto) _limparDestaqueBusca();
      });
      _atualizarMarcadoresFiltrados();

      // as sugestoes locais (imoveis + lista fixa) saem NA HORA, sem debounce
      // e sem rede: sao um filtro em memoria, esperar pra mostrar era so
      // atraso de graça. O debounce fica so pra parte online, que custa uma
      // chamada por consulta
      final termoAgora = _buscaController.text;
      final palavras = BuscaService.instance.palavras(termoAgora);
      setState(() {
        _sugestoesLocais =
            BuscaService.instance.buscarSugestoes(termoAgora, _imoveisDoBanco);

        // o que a internet ja trouxe CONTINUA na tela enquanto ainda fizer
        // sentido pro que esta escrito. Antes a lista inteira era zerada a
        // cada tecla, entao o resultado online sumia e so voltava depois de
        // outra ida a rede -- dava a impressao de busca que "nao acha"
        _sugestoesOnline = palavras.isEmpty
            ? []
            : _sugestoesOnline
                .where((s) => BuscaService.instance
                    .combina('${s.texto} ${s.detalhe}', palavras))
                .toList();
      });

      _debounceSugestoes?.cancel();
      if (palavras.isEmpty) {
        setState(() => _buscandoOnline = false);
        return;
      }

      _debounceSugestoes = Timer(const Duration(milliseconds: 250), () async {
        if (!mounted) return;
        final termo = _buscaController.text;

        // se ja achou uma instituicao conhecida (Inatel, UNIFEI, FAI, UNIVÁS...)
        // na lista fixa, nao busca online pra essa mesma consulta -- evita que
        // um bairro/regiao homonimo do Nominatim apareca do lado do pin certo
        // e a pessoa acabe clicando no lugar errado
        final achouInstituicaoConhecida =
            _sugestoesLocais.any((s) => s.tipo == TipoSugestao.faculdade);
        if (achouInstituicaoConhecida) return;

        setState(() => _buscandoOnline = true);

        // ruas, bairros e cidades de verdade vem depois, via busca online.
        // referencia de proximidade: onde a pessoa esta; sem permissao de
        // localizacao, a faculdade -- que e o centro de gravidade do app
        final locaisOnline = await BuscaService.instance.buscarLocaisOnline(
          termo,
          perto: LocalizacaoService.instance.posicao.value ?? posicaoInatel,
        );
        if (!mounted) return;
        // texto mudou no meio do caminho: a resposta e de outra pergunta
        if (_buscaController.text != termo) return;
        setState(() {
          _buscandoOnline = false;
          _sugestoesOnline = locaisOnline;
        });
      });
    });

    _buscaFocusNode.addListener(() {
      setState(() {
        // perdeu o foco: volta pro rotulo com reticencias
        if (!_buscaFocusNode.hasFocus) _editandoBusca = false;
      });
    });
  }

  // pede permissao de localizacao e centraliza o mapa no gps
  // desenha os pins na densidade real da tela. Roda em didChangeDependencies
  // e nao em initState porque precisa do MediaQuery, que so existe depois que
  // o widget tem contexto
  bool _pinsPedidos = false;

  Future<void> _prepararPins() async {
    final double densidade = MediaQuery.of(context).devicePixelRatio;
    final pinsAnuncio = <TipoPin, (BitmapDescriptor, BitmapDescriptor, BitmapDescriptor)>{};
    for (final tipo in TipoPin.values) {
      if (tipo == TipoPin.faculdade || tipo == TipoPin.imobiliaria) continue;
      pinsAnuncio[tipo] = (
        await PinsMapa.obter(tipo, densidade),
        await PinsMapa.obter(tipo, densidade, isOrigem: true),
        await PinsMapa.obter(tipo, densidade, isDestino: true),
      );
    }

    final inatel = await PinsMapa.obter(TipoPin.faculdade, densidade);
    final inatelO = await PinsMapa.obter(TipoPin.faculdade, densidade, isOrigem: true);
    final inatelD = await PinsMapa.obter(TipoPin.faculdade, densidade, isDestino: true);

    final imobiliaria = await PinsMapa.obter(TipoPin.imobiliaria, densidade);

    if (!mounted) return;
    setState(() {
      _pinsAnuncio = pinsAnuncio;

      _pinInatel = inatel;
      _pinInatelOrigem = inatelO;
      _pinInatelDestino = inatelD;

      _pinImobiliaria = imobiliaria;

      _atualizarMarcadorInatel();
      _atualizarMarcadoresImobiliarias();
      _atualizarMarcadoresLugares();
    });
    _atualizarMarcadoresFiltrados();
  }

  // busca os estabelecimentos perto de cada moradia. As buscas correm em
  // paralelo e o servico guarda o resultado da sessao, entao voltar pro mapa
  // nao repete nada
  Future<void> _carregarLugaresProximos() async {
    final moradias = _imoveisDoBanco.where((i) => i.tipo != TipoListing.evento).toList();
    final chave = (moradias.map((i) =>
            '${i.posicao.latitude.toStringAsFixed(4)},${i.posicao.longitude.toStringAsFixed(4)}').toList()
          ..sort())
        .join('|');
    if (chave == _chaveLugaresConsultados) return;
    _chaveLugaresConsultados = chave;

    final porMoradia = await Future.wait(
      moradias.map((i) => LugaresService.instance.proximosDe(i.posicao)),
    );
    // outra leva de imoveis chegou no meio do caminho: essa resposta e velha
    if (!mounted || chave != _chaveLugaresConsultados) return;

    final lugares = <String, Lugar>{};
    final categorias = <String, Set<CategoriaLugar>>{};
    for (var i = 0; i < moradias.length; i++) {
      // o servico ja devolve so o que esta dentro do raio da categoria,
      // entao estar na lista ja significa "perto"
      categorias[moradias[i].id] = {for (final l in porMoradia[i]) l.lugar.categoria};
      for (final l in porMoradia[i]) {
        lugares[l.lugar.id] = l.lugar;
      }
    }
    // nada veio (API fora ou desligada): libera pra tentar de novo na
    // proxima mudanca, em vez de ficar sem pins a sessao inteira
    if (lugares.isEmpty) _chaveLugaresConsultados = '';
    setState(() {
      _lugares = lugares;
      _categoriasPerto = lugares.isEmpty ? {} : categorias;
      _atualizarMarcadoresLugares();
    });
    // um filtro de localidade pode estar ligado desde antes dessa resposta
    _atualizarMarcadoresFiltrados();
  }

  // "tem isso a ate X metros?". A faculdade sai da distancia ate o Inatel,
  // que nao depende do Places; o resto vem do que o servico achou perto
  bool _atendeLocalidade(Imovel item, String id) {
    if (id == localidadeFaculdade) {
      return metrosAteInatel(item.posicao) <= raioFaculdade;
    }
    return _categoriasPerto[item.id]?.any((c) => c.name == id) ?? false;
  }

  // pins dos estabelecimentos -- fora de _marcadores pelo mesmo motivo das
  // imobiliarias: nao sao anuncio, o filtro de preco e tag nao se aplica
  // pins que nao dependem de anuncio nenhum por perto
  Future<void> _carregarLugaresFixos() async {
    final fixos = await LugaresService.instance.fixos();
    if (!mounted || fixos.isEmpty) return;
    setState(() {
      _lugaresFixos = {for (final l in fixos) l.id: l};
      _atualizarMarcadoresLugares();
    });
  }

  // os estabelecimentos da cidade -- os pins que existem independente de
  // haver anuncio por perto
  Future<void> _carregarLugaresDaCidade() async {
    final lugares = await LugaresService.instance.naCidade();
    if (!mounted || lugares.isEmpty) return;
    setState(() {
      _lugaresCidade = {for (final l in lugares) l.id: l};
      _atualizarMarcadoresLugares();
    });
  }

  void _atualizarMarcadoresLugares() {
    final rota = rotaAtivaGlobal.value;
    final categorias = _filtroState.categoriasSelecionadas;
    // a chave e o place id, entao o mesmo lugar achado por dois caminhos
    // (varredura da cidade, lista fixa, busca por anuncio) nao vira dois
    // pins. A ordem importa: quem vem depois vence, e a busca por anuncio e
    // a que garante foto no painel
    _marcadoresLugares = {..._lugaresCidade, ..._lugaresFixos, ..._lugares}
        .values
        // sem categoria escolhida o mapa mostra tudo; com alguma, so os pins
        // daquele tipo ficam (escolher "Eventos" tira todos os pins daqui)
        .where((lugar) => categorias.isEmpty || categorias.contains(lugar.categoria.name))
        .map((lugar) {
      final pins = _pinsAnuncio[lugar.categoria.pin];
      BitmapDescriptor? icone = pins?.$1;
      if (rota != null && lugar.posicao == rota.destino) icone = pins?.$3;
      return Marker(
        markerId: MarkerId('lugar_${lugar.id}'),
        position: lugar.posicao,
        icon: icone ?? BitmapDescriptor.defaultMarker,
        // abaixo das moradias: quando um pin cai em cima do outro, o anuncio
        // e que tem que ficar por cima
        zIndexInt: -1,
        // sem infoWindow, igual o Inatel: o toque abre o painel completo
        onTap: () => _abrirPainelLugar(lugar),
      );
    }).toSet();
  }

  void _abrirPainelLugar(Lugar lugar) {
    PainelLugar.mostrar(
      context,
      lugar,
      aoTracarRota: () => _tracarRotaAte(destino: lugar.posicao, nomeDestino: lugar.nome),
    );
  }

  // pins das imobiliarias -- ficam FORA de _marcadores de proposito, igual o
  // Inatel: nao sao anuncios, entao nao podem sumir quando a pessoa filtra
  // por preco ou tag
  void _atualizarMarcadoresImobiliarias() {
    final icone = _pinImobiliaria;
    if (icone == null) return;
    _marcadoresImobiliarias = _imobiliarias
        .where((i) => i.posicao != null)
        .map((i) => Marker(
              markerId: MarkerId('imobiliaria_${i.id}'),
              position: i.posicao!,
              icon: icone,
              zIndexInt: 1,
              infoWindow: InfoWindow(
                title: i.nome,
                snippet: i.endereco.isNotEmpty ? i.endereco : 'Imobiliária',
              ),
            ))
        .toSet();
  }

  void _atualizarMarcadorInatel() {
    if (_pinInatel == null) return;
    final ativa = rotaAtivaGlobal.value;
    BitmapDescriptor icone = _pinInatel!;
    if (ativa != null) {
      if (ativa.origem == posicaoInatel) icone = _pinInatelOrigem!;
      if (ativa.destino == posicaoInatel) icone = _pinInatelDestino!;
    }
    _marcadorInatel = Marker(
      markerId: const MarkerId('inatel_fixo'),
      position: posicaoInatel,
      icon: icone,
      zIndexInt: 2,
      // sem infoWindow: o toque abre o painel completo da faculdade (fotos,
      // engenharias e links), e o balaozinho do Google por cima dele so
      // roubaria o lugar do proprio pin
      onTap: _abrirPainelInatel,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_pinsPedidos) {
      _pinsPedidos = true;
      _prepararPins();
    }
  }

  // centraliza o mapa em quem esta usando. Sem permissao, explica e pergunta
  // em vez de simplesmente nao fazer nada (era o que acontecia antes: o toque
  // no botao morria em silencio e parecia defeito)
  Future<void> _obterLocalizacaoReal() async {
    final servico = LocalizacaoService.instance;

    if (!servico.permitida) {
      final liberou = await pedirLocalizacaoComExplicacao(context);
      if (!liberou || !mounted) return;
    }

    final posicao = await servico.posicaoParaRota();
    if (posicao == null || !mounted) {
      if (mounted) _avisarSemLocalizacao();
      return;
    }

    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: posicao, zoom: 16.0),
      ),
    );
  }

  // centraliza em quem ja tinha permitido, sem abrir dialogo nenhum
  Future<void> _centralizarSeJaPermitido() async {
    final servico = LocalizacaoService.instance;
    if (!servico.permitida) return;
    final posicao = await servico.posicaoParaRota();
    if (posicao == null || !mounted) return;
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: posicao, zoom: 16.0),
      ),
    );
  }

  void _avisarSemLocalizacao() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Não conseguimos acessar sua localização agora.'),
        backgroundColor: corErro,
      ),
    );
  }

  Future<void> _carregarDadosUsuarioLogado() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final perfil = await UsuarioService.instance.buscarPorUid(user.uid);
      if (perfil != null && mounted) {
        setState(() => _perfilAtual = perfil);
      }
    } catch (e) {
      debugPrint("Erro ao carregar dados do usuário: $e");
    }
  }

  // se o e-mail dessa conta bate com o de uma imobiliaria ainda pendente
  // (algum corretor se vinculou a ela), oferece a confirmacao aqui
  Future<void> _verificarVinculoPendente() async {
    final email = FirebaseAuth.instance.currentUser?.email;
    if (email == null) return;
    final pendente = await ImobiliariaService.instance.buscarPendentePorEmail(email);
    if (pendente == null || !mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? superficieEscura : superficieClara,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.apartment_rounded, color: corPrimaria, size: 40),
              const SizedBox(height: 16),
              Text(
                'Você é responsável por "${pendente.nome}"?',
                style: AppTextStyles.heading3.copyWith(color: isDark ? Colors.white : Colors.black87),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Um ou mais corretores pediram vínculo com essa imobiliária usando esse e-mail. Confirme pra liberar o perfil público deles.',
                style: AppTextStyles.caption.copyWith(color: isDark ? Colors.white54 : Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              AnimatedGradientButton(
                label: 'Confirmar vínculo',
                onTap: () async {
                  await ImobiliariaService.instance.confirmar(pendente.id);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: Text('Agora não', style: TextStyle(color: isDark ? Colors.white38 : Colors.grey)),
              ),
            ],
          ),
        );
      },
    );
  }

  // limpa qualquer destaque de busca anterior (chamado toda vez que uma nova
  // busca comeca ou o texto e apagado)
  void _limparDestaqueBusca() {
    _destaqueRuaBusca = {};
    _destaqueAreaBusca = {};
    _preenchimentoAreaBusca = {};
    _destaquePoiBusca = null;
    _localSelecionado = null;
  }

  // ao escolher um resultado, desenha o destaque certo pro tipo de local
  // (igual o Google Maps faz: rua pintada, bairro delimitado, POI com pin) e
  // enquadra a camera no que foi desenhado
  Future<void> _selecionarSugestao(SugestaoBusca sugestao) async {
    _buscaController.text = sugestao.texto;
    _editandoBusca = false;
    _buscaFocusNode.unfocus();
    _desenharSugestao(sugestao);

    // bairro cujo contorno ainda nao foi buscado: mostra o ponto na hora e
    // troca pelo tracejado quando o contorno chegar. A alternativa era travar
    // a lista inteira esperando isso -- era assim antes, e era lento
    if (sugestao.contornoPendente) {
      setState(() => _carregandoContorno = true);
      final completa = await BuscaService.instance.garantirContorno(sugestao);
      if (!mounted) return;
      setState(() => _carregandoContorno = false);
      // texto trocado nesse meio tempo: a escolha ja nao vale mais
      if (_localSelecionado?.texto != sugestao.texto) return;
      _desenharSugestao(completa);
    }
  }

  // atende o "ver o bairro no mapa" vindo da tela do imovel: acha o contorno
  // real da regiao e desenha o mesmo tracejado da busca. Reusa o caminho da
  // sugestao inteiro -- desenho, enquadramento e card sao os mesmos
  Future<void> _mostrarBairroNoMapa(BairroPendente pedido) async {
    final inicial = SugestaoBusca(
      texto: pedido.nome,
      detalhe: 'Bairro',
      tipo: TipoSugestao.endereco,
      destino: pedido.perto,
    );
    _buscaController.text = pedido.nome;
    _editandoBusca = false;
    _desenharSugestao(inicial);

    setState(() => _carregandoContorno = true);
    final pontos = await BuscaService.instance
        .buscarContornoDeArea(pedido.nome, pedido.perto);
    if (!mounted) return;
    setState(() => _carregandoContorno = false);
    // a pessoa pode ter buscado outra coisa enquanto o contorno vinha
    if (_localSelecionado?.texto != pedido.nome) return;

    if (pontos.length >= 3) {
      _desenharSugestao(inicial.comGeometria(TipoGeometria.area, pontos));
    } else {
      // bairro sem contorno no OpenStreetMap (comum em cidade pequena):
      // fica o pin, e a pessoa fica sabendo por que nao veio o tracejado
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'O contorno do bairro ${pedido.nome} ainda não está mapeado no OpenStreetMap.'),
          backgroundColor: corPrimaria,
        ),
      );
    }
  }

  void _desenharSugestao(SugestaoBusca sugestao) {
    // area/linha sem pontos ainda (contorno a caminho) cai no marker: sem
    // essa guarda o caso "area vazia" tentava fechar o anel pelo primeiro
    // ponto de uma lista VAZIA e estourava, derrubando o setState inteiro
    // -- o destaque nao aparecia e a camera nem chegava a se mover.
    //
    // Fica FORA do setState porque o enquadramento da camera, la embaixo,
    // usa os dois valores
    final bool temGeometria = sugestao.pontosGeometria.length >= 2;
    final TipoGeometria tipoEfetivo =
        temGeometria ? sugestao.tipoGeometria : TipoGeometria.ponto;

    // local que ja tem pin proprio no mapa (moradia, lugar, imobiliaria,
    // Inatel): o pin roxo da busca caia por cima e escondia o original. Nesse
    // caso nao desenha destaque nenhum, so abre o balao do pin que ja existe
    final Marker? pinExistente = tipoEfetivo == TipoGeometria.ponto
        ? _pinExistenteEm(sugestao.destino)
        : null;

    setState(() {
      // fecha a lista: escolheu, nao precisa mais das opcoes
      _sugestoesLocais = [];
      _sugestoesOnline = [];
      _buscandoOnline = false;
      _limparDestaqueBusca();
      _localSelecionado = sugestao;

      switch (tipoEfetivo) {
        case TipoGeometria.linha:
          _destaqueRuaBusca = {
            Polyline(
              polylineId: const PolylineId('destaque_busca'),
              points: sugestao.pontosGeometria,
              color: const Color(0xFFFF6D00),
              width: 6,
            ),
          };
        case TipoGeometria.area:
          // bairro/regiao igual o Google Maps: contorno TRACEJADO com um
          // preenchimento bem fraco por baixo. Sao duas camadas porque o
          // Polygon do plugin nao aceita traco pontilhado e o Polyline nao
          // aceita preenchimento -- entao o Polygon entra so pela cor de
          // dentro (stroke zerado) e o Polyline fechado faz o tracejado
          _destaqueAreaBusca = {
            Polyline(
              polylineId: const PolylineId('destaque_busca'),
              points: [...sugestao.pontosGeometria, sugestao.pontosGeometria.first],
              color: const Color(0xFFE53935),
              width: 4,
              patterns: [PatternItem.dash(20), PatternItem.gap(12)],
            ),
          };
          _preenchimentoAreaBusca = {
            Polygon(
              polygonId: const PolygonId('preenchimento_busca'),
              points: sugestao.pontosGeometria,
              strokeWidth: 0,
              fillColor: const Color(0xFFE53935).withAlpha(18),
            ),
          };
        case TipoGeometria.ponto:
          if (pinExistente != null) break;
          _destaquePoiBusca = Marker(
            markerId: const MarkerId('destaque_busca'),
            position: sugestao.destino,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
            infoWindow: InfoWindow(title: sugestao.texto),
          );
      }
    });

    // enquadra pelo DESENHO quando existe um desenho. Enquadrar por pontos
    // soltos que nao viraram contorno (o Overpass as vezes devolve dois
    // pontos) abria uma visao larga sem nada dentro -- parecia que o mapa
    // tinha pulado pro lugar errado
    if (temGeometria && tipoEfetivo != TipoGeometria.ponto) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(RotaService.calcularBounds(sugestao.pontosGeometria), 60),
      );
    } else {
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(sugestao.destino, 16));
    }

    if (pinExistente != null) {
      _mapController?.showMarkerInfoWindow(pinExistente.markerId);
    }
  }

  // pin ja desenhado no mapa a poucos metros do ponto. A tolerancia cobre a
  // diferenca entre a coordenada da busca (lista de locais conhecidos,
  // Nominatim) e a coordenada cadastrada do anuncio
  Marker? _pinExistenteEm(LatLng ponto) {
    for (final m in [
      ?_marcadorInatel,
      ..._marcadoresImobiliarias,
      ..._marcadoresLugares,
      ..._marcadores,
    ]) {
      final metros = Geolocator.distanceBetween(
        ponto.latitude,
        ponto.longitude,
        m.position.latitude,
        m.position.longitude,
      );
      if (metros <= 30) return m;
    }
    return null;
  }

  // reage na hora se o usuario trocar o modo escuro/claro do celular
  // enquanto o app ta aberto (so importa quando temaGlobal esta em "sistema")
  @override
  void didChangePlatformBrightness() {
    if (temaGlobal.value == ThemeMode.system) _atualizarEstiloMapa();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    temaGlobal.removeListener(_temaListener);
    _filtroState.removeListener(_filtroListener);
    _inscricaoNav?.cancel();
    _inscricaoImobiliarias?.cancel();
    rotaAtivaGlobal.removeListener(_rotaAtivaListener);
    rotaCarregandoGlobal.removeListener(_rotaCarregandoListener);
    rotaErroGlobal.removeListener(_rotaErroListener);
    LocalizacaoService.instance.estado.removeListener(_localizacaoListener);
    bairroPendenteGlobal.removeListener(_bairroListener);
    _filtroState.dispose();
    _debounceSugestoes?.cancel();
    _buscaController.dispose();
    _buscaFocusNode.dispose();
    _animIniciaisController.dispose();
    super.dispose();
  }

  Future<void> _carregarEstilosDoAsset() async {
    _estiloMapaEscuro = await rootBundle.loadString('assets/map_styles/style_dark.json');
    _estiloMapaLimpo = await rootBundle.loadString('assets/map_styles/style_clean.json');
    if (mounted) _atualizarEstiloMapa();
  }

  // o item bate com o texto da caixa de busca? Fica separado dos filtros da
  // folha porque e outra caixa: a folha nao mexe nele
  bool _passaNaBusca(Imovel item) {
    final textoBusca = _buscaController.text.toLowerCase().trim();
    if (textoBusca.isEmpty) return true;
    return '${item.titulo} ${item.descricao}'.toLowerCase().contains(textoBusca);
  }

  // o item passa pelos filtros da folha? Recebe os valores por parametro (em
  // vez de ler _filtroState) pra folha poder contar quantos imoveis sobram
  // COM o que esta escolhido ali, antes de aplicar
  bool _passaNosFiltros(
    Imovel item, {
    required double? precoMinimo,
    required double? precoMaximo,
    required List<String> tags,
    required List<String> contas,
    required List<String> localidades,
    required List<String> categorias,
  }) {
    // com categoria escolhida o mapa mostra SO aquilo: anuncio so continua se
    // for evento e "Eventos" estiver marcado. Escolher "Mercados" sozinho
    // deixa no mapa os pins de mercado e mais nada -- que e o que a pessoa
    // pediu ao marcar so aquela categoria
    if (categorias.isNotEmpty) {
      final bool ehEvento = item.tipo == TipoListing.evento;
      if (!ehEvento || !categorias.contains(categoriaEvento)) return false;
    }
    // evento nao tem preco de aluguel, entao pula so o filtro de preco
    if (item.tipo != TipoListing.evento) {
      if (precoMinimo != null && item.preco < precoMinimo) return false;
      if (precoMaximo != null && item.preco > precoMaximo) return false;
    }
    if (!tags.every(item.tags.contains)) return false;
    if (!contas.every(item.incluiConta)) return false;
    if (!localidades.every((id) => _atendeLocalidade(item, id))) return false;
    return true;
  }

  // quantos pins de estabelecimento sobrariam com essas categorias -- o
  // companheiro de _quantosAtendem pro botao da folha, ja que um filtro so de
  // categoria pode nao deixar anuncio nenhum e ainda assim mostrar muita coisa
  int _quantosLugares(List<String> categorias) {
    if (categorias.isEmpty) return 0;
    // a mesma juncao de _atualizarMarcadoresLugares: a contagem do botao tem
    // que bater com o que vai aparecer no mapa
    return {..._lugaresCidade, ..._lugaresFixos, ..._lugares}
        .values
        .where((l) => categorias.contains(l.categoria.name))
        .length;
  }

  // quantos imoveis sobrariam com essa escolha -- alimenta o numero do botao
  // da folha de filtros
  int _quantosAtendem({
    required double? precoMinimo,
    required double? precoMaximo,
    required List<String> tags,
    required List<String> contas,
    required List<String> localidades,
    required List<String> categorias,
  }) =>
      _imoveisDoBanco
          .where((item) =>
              _passaNaBusca(item) &&
              _passaNosFiltros(
                item,
                precoMinimo: precoMinimo,
                precoMaximo: precoMaximo,
                tags: tags,
                contas: contas,
                localidades: localidades,
                categorias: categorias,
              ))
          .length;

  void _atualizarMarcadoresFiltrados() {
    final imovelFiltrados = _imoveisDoBanco
        .where((item) =>
            _passaNaBusca(item) &&
            _passaNosFiltros(
              item,
              precoMinimo: _filtroState.precoMinimo,
              precoMaximo: _filtroState.precoMaximo,
              tags: _filtroState.tagsSelecionadas,
              contas: _filtroState.contasSelecionadas,
              localidades: _filtroState.localidadesSelecionadas,
              categorias: _filtroState.categoriasSelecionadas,
            ))
        .toList();

    final rota = rotaAtivaGlobal.value;

    setState(() {
      _marcadores = imovelFiltrados.map((item) {
        final bool isEvento = item.tipo == TipoListing.evento;
        final pins = _pinsAnuncio[tipoPinDoImovel(item)];

        BitmapDescriptor? iconeBase = pins?.$1;
        if (rota != null) {
          if (item.posicao == rota.origem) {
            iconeBase = pins?.$2;
          } else if (item.posicao == rota.destino) {
            iconeBase = pins?.$3;
          }
        }

        return Marker(
          markerId: MarkerId(item.id),
          position: item.posicao,
          icon: iconeBase ??
              BitmapDescriptor.defaultMarkerWithHue(
                isEvento ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueAzure,
              ),
          infoWindow: InfoWindow(
            title: item.titulo,
            snippet: item.descricao,
          ),
          onTap: () => _abrirDetalhesImovel(item),
        );
      }).toSet();
    });
  }

  // agora o toque em qualquer marker (moradia ou evento) abre a pagina de
  // detalhes -- o calculo de rota mora la dentro, nao mais aqui no mapa
  void _abrirDetalhesImovel(Imovel imovel) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => DetalhesImovelScreen(imovel: imovel)),
    );
  }

  // so mexe nos campos, sem setState -- usado no initState (onde o setState
  // e desnecessario e arriscado, ja que o primeiro build ainda nem rodou)
  void _sincronizarComRotaGlobal() {
    final ativa = rotaAtivaGlobal.value;
    _rotaAtual = ativa;
    _carregandoRota = rotaCarregandoGlobal.value;
    
    if (ativa == null) {
      _rotas = {};
      _marcadoresRota = {};
      _atualizarMarcadoresFiltrados();
      _atualizarMarcadorInatel();
      _atualizarMarcadoresLugares();
      return;
    }
    
    // Atualiza as cores dos pins que ja existem no mapa (moradias, eventos, inatel)
    _atualizarMarcadoresFiltrados();
    _atualizarMarcadorInatel();
    _atualizarMarcadoresLugares();

    // desenha todas as alternativas: as nao escolhidas em cinza e por baixo
    // (zIndex menor), clicaveis pra virar a ativa; a escolhida em destaque por
    // cima. consumeTapEvents evita que o toque atravesse a linha e caia no
    // mapa (que fecha paineis/limpa selecao)
    //
    // Navegando, so a linha escolhida fica: alternativa cinza no meio do
    // trajeto vira ruido e ainda e clicavel, o que trocaria a rota debaixo de
    // quem esta dirigindo
    _rotas = {
      for (var i = 0; i < ativa.opcoes.length; i++)
        if (i != ativa.indiceSelecionado && !_navegando)
          Polyline(
            polylineId: PolylineId('rota_alt_$i'),
            points: ativa.opcoes[i].pontos,
            color: _deveUsarEstiloEscuro ? Colors.white54 : Colors.grey.shade500,
            width: 5,
            zIndex: 1,
            consumeTapEvents: true,
            onTap: () => _selecionarAlternativa(i),
          ),
      Polyline(
        polylineId: const PolylineId('rota_ativa'),
        points: ativa.selecionada.pontos,
        color: corPrimaria,
        width: 6,
        zIndex: 2,
      ),
    };

    // se a origem ou destino for um local generico (buscado via Google, etc)
    // e nao estiver na nossa lista de imoveis/Inatel, ai sim criamos um pin generico
    final origemEhImovelOuInatel = ativa.origem == posicaoInatel || _imoveisDoBanco.any((i) => i.posicao == ativa.origem);
    final destinoEhImovelOuInatel = ativa.destino == posicaoInatel || _imoveisDoBanco.any((i) => i.posicao == ativa.destino);

    _marcadoresRota = {
      // o pin de origem some na navegacao: ele marca de onde a rota partiu, e
      // durante o deslocamento fica bem embaixo da seta, escondendo justamente
      // a unica coisa que importa olhar
      if (!origemEhImovelOuInatel && !_navegando)
        Marker(
          markerId: const MarkerId('rota_origem'),
          position: ativa.origem,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
      if (!destinoEhImovelOuInatel)
        Marker(
          markerId: const MarkerId('rota_destino'),
          position: ativa.destino,
          infoWindow: InfoWindow(title: ativa.nomeDestino),
        ),
    };
  }

  // reconstroi markers/polyline a partir do rotaAtivaGlobal atual e enquadra
  // a camera -- chamado toda vez que o valor global muda (depois do primeiro build)
  void _atualizarEstadoDaRota() {
    final ativa = rotaAtivaGlobal.value;
    // trocar de alternativa reusa a mesma lista de opcoes (ver
    // RotaAtiva.selecionar), entao da pra diferenciar "rota nova" de "so
    // mudou a escolhida" por identidade -- sem isso a camera reenquadraria a
    // cada toque numa alternativa, jogando a visao do usuario fora do lugar
    final rotaNova = ativa != null && !identical(_rotaAtual?.opcoes, ativa.opcoes);

    setState(_sincronizarComRotaGlobal);

    // navegando, a camera pertence ao deslocamento: enquadrar a rota inteira
    // aqui jogaria a visao do usuario pra longe no meio do caminho, toda vez
    // que um recalculo chegasse
    if (rotaNova && !_navegando) {
      // enquadra TODAS as alternativas, nao so a escolhida, pra elas ja
      // aparecerem na tela e o usuario ver que existe opcao
      _mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(
          RotaService.calcularBounds(ativa.opcoes.expand((o) => o.pontos).toList()),
          60,
        ),
      );
    }
  }

  // traca a rota da posicao atual do usuario ate o local escolhido na busca
  // (Inatel, uma faculdade, um endereco...) -- reusa o mesmo pipeline global
  // que a tela de detalhes usa, entao as alternativas e o seletor de modal
  // vem de graca, sem nenhum caminho novo de calculo
  Future<void> _tracarRotaAteLocalBuscado() async {
    final local = _localSelecionado;
    if (local == null) return;
    await _tracarRotaAte(destino: local.destino, nomeDestino: local.texto);
  }

  // pega a localizacao atual e pede a rota ate um destino qualquer. Nasceu de
  // _tracarRotaAteLocalBuscado, que era o unico caminho -- o painel da
  // faculdade precisa do MESMO comportamento (mesma origem, mesmo modo de
  // transporte escolhido, mesmo tratamento de erro), entao chama daqui em vez
  // de repetir o bloco
  Future<void> _tracarRotaAte({
    required LatLng destino,
    required String nomeDestino,
  }) async {
    if (_buscandoOrigemRota) return;

    // rota parte de ONDE A PESSOA ESTA -- sem permissao nao ha o que calcular.
    // Explica e pergunta; se ela recusar, sai sem erro nenhum na cara
    if (!LocalizacaoService.instance.permitida) {
      final liberou = await pedirLocalizacaoComExplicacao(context);
      if (!liberou || !mounted) return;
    }

    setState(() => _buscandoOrigemRota = true);
    LatLng? origem;
    try {
      origem = await LocalizacaoService.instance.posicaoParaRota();
    } catch (e) {
      origem = null;
    }
    if (!mounted) return;
    setState(() => _buscandoOrigemRota = false);

    if (origem == null) {
      _avisarSemLocalizacao();
      return;
    }

    // mantem o modal que o usuario ja tinha escolhido no seletor, com o mesmo
    // desvio de "moto" que _trocarModoTransporte faz (nao existe na API classica)
    final modoParaApi =
        _modoTransporteUi == TravelMode.twoWheeler ? TravelMode.driving : _modoTransporteUi;

    rotaPendenteGlobal.value = RotaPendente(
      origem: origem,
      destino: destino,
      nomeDestino: nomeDestino,
      modo: modoParaApi,
    );
  }

  // painel da faculdade -- abre ao tocar no pin fixo do Inatel
  void _abrirPainelInatel() {
    PainelInatel.mostrar(
      context,
      aoTracarRota: () => _tracarRotaAte(
        destino: posicaoInatel,
        nomeDestino: 'Inatel - Instituto Nacional de Telecomunicações',
      ),
    );
  }

  // ---------------------------------------------------------------------
  // MODO NAVEGACAO
  // ---------------------------------------------------------------------

  // mistura dois angulos de bussola pelo menor caminho.
  //
  // Interpolar 350 -> 10 na marra daria uma volta de 340 graus pro lado
  // errado (o mapa girando inteiro). O truque do (+540) % 360 - 180 traz a
  // diferenca pro intervalo [-180, 180], que e sempre o caminho curto.
  double _misturarRumo(double atual, double alvo, double fator) {
    final double delta = ((alvo - atual + 540) % 360) - 180;
    return (atual + delta * fator + 360) % 360;
  }

  Future<void> _iniciarNavegacao() async {
    if (_navegando) return;

    // le o DPR antes dos await: depois deles o context pode nao valer mais
    final double densidade = MediaQuery.of(context).devicePixelRatio;

    // navegar e seguir a pessoa pelo trajeto: sem localizacao nao existe modo
    // "Ir". Mesmo pedido explicado das outras acoes, nada de dialogo seco
    if (!LocalizacaoService.instance.permitida) {
      final liberou = await pedirLocalizacaoComExplicacao(context);
      if (!liberou || !mounted) return;
    }

    final seta = _setaNav ?? await setaNavegacao(densidade);
    if (!mounted) return;

    setState(() {
      _setaNav = seta;
      _navegando = true;
      _rumoSuave = 0;
      _seguindoCamera = true;
      _metrosRestantes = null;
      _segundosRestantes = null;
      _trilhaNav = null;
      _recalculandoRota = false;
      _ultimoRecalculo = DateTime.now();
      // redesenha rota e pins ja no modo navegacao (sem alternativas, sem
      // pin de origem) -- eles foram montados com _navegando ainda falso
      _sincronizarComRotaGlobal();
    });
    navegandoGlobal.value = true;

    // o stream de navegacao e de alta precisao e entrega toda leitura; o
    // ambiente (15 m) nao acrescenta nada aqui e so gastaria bateria em
    // paralelo. Volta a valer em _encerrarNavegacao
    LocalizacaoService.instance.pararAcompanhamento();

    _inscricaoNav = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        // bestForNavigation e o modo de maior precisao; distanceFilter 0
        // entrega toda atualizacao, necessario pra camera acompanhar liso
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    ).listen(_aoMoverNavegando);
  }

  void _aoMoverNavegando(Position posicao) {
    // o rumo do GPS so tem sentido em movimento: parado ele devolve lixo ou
    // o ultimo valor, e usar isso faria o mapa girar sozinho com o usuario
    // imovel. Abaixo de ~0,7 m/s (caminhada lenta) mantem o rumo anterior
    if (posicao.speed > 0.7 && posicao.heading >= 0) {
      _rumoSuave = _misturarRumo(_rumoSuave, posicao.heading, 0.28);
    }

    final ativa = _rotaAtual;
    final LatLng aqui = LatLng(posicao.latitude, posicao.longitude);

    // quanto falta PELA ROTA (nao em linha reta) e o quanto o usuario esta
    // afastado dela. A trilha e remontada quando o trajeto muda -- comparar
    // por identidade cobre tanto o inicio da navegacao quanto um recalculo
    double? restante;
    double? desvio;
    int? segundos;
    if (ativa != null) {
      if (!identical(_trilhaNav?.pontos, ativa.selecionada.pontos)) {
        _trilhaNav = TrilhaRota.montar(ativa.selecionada.pontos);
      }
      final trilha = _trilhaNav!;
      final progresso = trilha.progresso(aqui);
      restante = progresso.metrosRestantes;
      desvio = progresso.desvioMetros;

      // a API so devolve a duracao do trajeto inteiro, entao o que falta sai
      // por proporcao do que falta andar. Nao e previsao de transito, e uma
      // estimativa honesta -- melhor que nao mostrar tempo nenhum
      if (trilha.total > 0) {
        segundos =
            (ativa.selecionada.duracaoSegundos * (restante / trilha.total)).round();
      }
    }

    if (!mounted) return;
    setState(() {
      _posicaoNav = posicao;
      _metrosRestantes = restante;
      _segundosRestantes = segundos;
    });

    // chegada mede em LINHA RETA ate o destino: no fim do trajeto as duas
    // medidas se encontram, e a reta nao depende de o GPS ter acompanhado a
    // linha ate o ultimo ponto. 35 m cobre o erro tipico do GPS urbano
    final destino = ativa?.destino;
    if (destino != null) {
      final emLinhaReta = Geolocator.distanceBetween(
        posicao.latitude, posicao.longitude,
        destino.latitude, destino.longitude,
      );
      if (emLinhaReta < 35) {
        _encerrarNavegacao(chegou: true);
        return;
      }
    }

    // saiu do trajeto: pede uma rota nova a partir de onde esta, igual o
    // Waze/Maps fazem. 70 m e folgado o bastante pra nao disparar com erro de
    // GPS entre predios, e o intervalo minimo evita repetir a chamada (que e
    // paga) enquanto a anterior nao chegou ou o usuario segue fora da linha
    if (desvio != null && desvio > 70) _recalcularRotaNavegando(aqui);

    if (!_seguindoCamera) return;

    // NAO dispara animacao a cada leitura: cada animateCamera novo cancela o
    // anterior, e com leituras chegando de fracao em fracao de segundo a
    // camera nunca terminava o movimento -- era por isso que a inclinacao
    // parecia nao aplicar. Uma animacao por vez, com duracao proxima do
    // intervalo entre leituras, da movimento continuo de verdade
    final agora = DateTime.now();
    if (agora.difference(_ultimoAjusteCamera).inMilliseconds < 850) return;
    _ultimoAjusteCamera = agora;

    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(posicao.latitude, posicao.longitude),
          zoom: 17.5,
          tilt: 55, // perspectiva 3D
          bearing: _rumoSuave, // o movimento aponta pro topo da tela
        ),
      ),
      duration: const Duration(milliseconds: 800),
    );
  }

  // pede o trajeto de novo a partir da posicao atual, mantendo destino, nome
  // e modo. Reusa o mesmo pipeline global (rotaPendenteGlobal) que todo o
  // resto do app usa pra calcular rota -- nenhum caminho de calculo novo
  void _recalcularRotaNavegando(LatLng origem) {
    final ativa = _rotaAtual;
    if (ativa == null || _recalculandoRota) return;
    if (DateTime.now().difference(_ultimoRecalculo).inSeconds < 20) return;

    _ultimoRecalculo = DateTime.now();
    setState(() => _recalculandoRota = true);

    rotaPendenteGlobal.value = RotaPendente(
      origem: origem,
      destino: ativa.destino,
      nomeDestino: ativa.nomeDestino,
      modo: ativa.modo,
    );
  }

  // volta a seguir depois de o usuario ter arrastado o mapa
  void _recentralizarNavegacao() {
    setState(() => _seguindoCamera = true);
    final p = _posicaoNav;
    if (p == null) return;
    _ultimoAjusteCamera = DateTime.now();
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(p.latitude, p.longitude),
          zoom: 17.5,
          tilt: 55,
          bearing: _rumoSuave,
        ),
      ),
    );
  }

  Future<void> _encerrarNavegacao({bool chegou = false}) async {
    await _inscricaoNav?.cancel();
    _inscricaoNav = null;
    // religa o acompanhamento ambiente -- verificar() em vez de religar na
    // mao porque a permissao pode ter mudado nos ajustes durante o trajeto
    LocalizacaoService.instance.verificar();
    if (!mounted) return;
    setState(() {
      _navegando = false;
      _posicaoNav = null;
      _metrosRestantes = null;
      _segundosRestantes = null;
      _trilhaNav = null;
      _recalculandoRota = false;
      _seguindoCamera = true;
      // volta a desenhar alternativas e pins que ficam escondidos na navegacao
      _sincronizarComRotaGlobal();
    });
    navegandoGlobal.value = false;

    if (chegou) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Você chegou em ${_rotaAtual?.nomeDestino ?? "seu destino"}.'),
          backgroundColor: corSucesso,
        ),
      );
    }
    // desfaz inclinacao e rotacao, senao o mapa fica torto depois de sair
    final alvo = _rotaAtual != null
        ? _rotaAtual!.selecionada.pontos.first
        : posicaoInatel;
    _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: alvo, zoom: 16, tilt: 0, bearing: 0),
      ),
    );
  }

  Widget _painelNavegacao(bool isDark) {
    final String restante = _metrosRestantes == null
        ? '--'
        : formatarDistancia(_metrosRestantes!);
    final String? tempo = _segundosRestantes == null
        ? null
        : formatarDuracaoCurta(_segundosRestantes!);
    final String destinoTexto = _rotaAtual?.nomeDestino ?? '';

    return Stack(
      children: [
        // faixa superior: so o essencial. Durante o deslocamento o usuario
        // olha a tela de relance, entao cabe pouca informacao
        Positioned(
          top: (MediaQuery.of(context).padding.top > 0
                  ? MediaQuery.of(context).padding.top
                  : 6) +
              AppSpacing.sm,
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          child: GlassCard(
            radius: 22,
            sombra: AppShadows.nivel3(isDark),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm + 2),
                  decoration: BoxDecoration(
                    gradient: gradientePrincipal,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: const Icon(Icons.navigation_rounded,
                      color: Colors.white, size: 20),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            restante,
                            style: AppTextStyles.heading3.copyWith(
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          if (tempo != null) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              '· $tempo',
                              style: AppTextStyles.bodyBold.copyWith(
                                color: isDark ? Colors.white70 : corPrimaria,
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        // o recalculo troca a linha debaixo do usuario; sem
                        // aviso a distancia pula sozinha e parece defeito
                        _recalculandoRota
                            ? 'Recalculando rota...'
                            : 'até $destinoTexto',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(
                          color: _recalculandoRota
                              // azul da marca e escuro demais pra texto pequeno
                              // no vidro escuro -- no modo noturno usa o tom
                              // claro da mesma familia
                              ? (isDark ? const Color(0xFF8FBEE8) : corPrimaria)
                              : (isDark ? Colors.white38 : Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // rodape: encerrar, e recentralizar caso o usuario tenha arrastado
        Positioned(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          bottom: MediaQuery.of(context).padding.bottom + AppSpacing.xl,
          child: Row(
            children: [
              if (!_seguindoCamera) ...[
                Pressionavel(
                  onTap: _recentralizarNavegacao,
                  child: GlassCard(
                    radius: AppRadius.md,
                    child: const SizedBox(
                      width: 54,
                      height: 54,
                      child: Icon(Icons.my_location_rounded, size: 24),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Pressionavel(
                  onTap: _encerrarNavegacao,
                  child: Container(
                    height: 54,
                    decoration: BoxDecoration(
                      color: corErro,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      boxShadow: AppShadows.nivel2(isDark),
                    ),
                    child: Center(
                      child: Text(
                        'Encerrar navegação',
                        style: AppTextStyles.bodyBold.copyWith(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // troca a alternativa ativa sem bater na API de novo -- todos os trajetos
  // ja vieram juntos na mesma resposta, entao isso e instantaneo
  void _selecionarAlternativa(int indice) {
    final ativa = rotaAtivaGlobal.value;
    if (ativa == null || indice == ativa.indiceSelecionado) return;
    rotaAtivaGlobal.value = ativa.selecionar(indice);
  }

  void _limparRota() {
    rotaAtivaGlobal.value = null;
  }

  // reusa o mesmo pipeline global (rotaPendenteGlobal -> processarPedidoDeRota)
  // que a tela de detalhes ja usa, so trocando o modo -- refaz a chamada na
  // Directions API com o mesmo par origem/destino e redesenha a rota certa
  void _trocarModoTransporte(TravelMode modoEscolhido) {
    if (_rotaAtual == null) return;
    setState(() => _modoTransporteUi = modoEscolhido);

    // "moto" nao existe na Directions API classica (so na Routes API nova,
    // que exigiria habilitar outra api no google cloud) -- usa carro como
    // aproximacao por baixo dos panos, mantendo o icone de moto selecionado na UI
    final modoParaApi = modoEscolhido == TravelMode.twoWheeler ? TravelMode.driving : modoEscolhido;

    rotaPendenteGlobal.value = RotaPendente(
      origem: _rotaAtual!.origem,
      destino: _rotaAtual!.destino,
      nomeDestino: _rotaAtual!.nomeDestino,
      modo: modoParaApi,
    );
  }

  // busca terminou e nao achou nada -- nem local, nem online
  bool get _semResultado =>
      _buscaComTexto && !_buscandoOnline && _sugestoes.isEmpty;

  // ultima linha da lista: diz o que a busca esta fazendo. Sem ela, quem
  // digita algo que ainda nao casou ve o painel simplesmente sumir e conclui
  // que a busca nao funciona -- era a queixa de "digito e nao aparece"
  Widget? _rodapeBusca(bool isDark) {
    if (_buscandoOnline) {
      return ListTile(
        dense: true,
        leading: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: corPrimaria.withAlpha(150),
          ),
        ),
        title: Text(
          'Procurando mais lugares...',
          style: AppTextStyles.caption.copyWith(
            color: isDark ? Colors.white38 : Colors.black45,
          ),
        ),
      );
    }
    if (_semResultado) {
      return ListTile(
        dense: true,
        leading: Icon(Icons.search_off_rounded,
            color: isDark ? Colors.white38 : Colors.black38),
        title: Text(
          'Nada encontrado para "${_buscaController.text.trim()}"',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.caption.copyWith(
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
        subtitle: Text(
          'Tente o nome da rua, do bairro ou da cidade',
          style: AppTextStyles.caption.copyWith(
            color: isDark ? Colors.white30 : Colors.black38,
          ),
        ),
      );
    }
    return null;
  }

  // o card do local sai de cena enquanto existe rota na tela (o card de rota
  // no topo ja mostra destino/distancia, e os dois juntos poluiriam) -- se o
  // usuario fechar a rota ele volta, dando pra tracar de novo sem rebuscar
  bool get _mostrandoCardLocal =>
      _localSelecionado != null && _rotaAtual == null && !_carregandoRota;

  // card do local escolhido na busca, com o botao de tracar rota ate ele --
  // mesmo papel do painel que o Google Maps abre ao selecionar um ponto
  Widget _cardLocalBuscado(bool isDark) {
    final local = _localSelecionado!;
    final icone = switch (local.tipo) {
      TipoSugestao.cidade => Icons.location_city_rounded,
      TipoSugestao.faculdade => Icons.school_rounded,
      TipoSugestao.moradia => Icons.home_rounded,
      TipoSugestao.endereco => Icons.signpost_outlined,
    };

    return GlassCard(
      radius: 24,
      sombra: AppShadows.nivel3(isDark),
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.sm, AppSpacing.lg - 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                // mesmo gradiente escuro do botao logo abaixo -- os dois estao
                // no mesmo card, e o azul claro/ciano destoava
                decoration: BoxDecoration(gradient: gradientePrincipal, borderRadius: BorderRadius.circular(10)),
                child: Icon(icone, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      local.texto,
                      style: TextStyle(fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black87),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // o contorno do bairro chega depois da escolha; sem esse
                    // aviso o tracejado aparecia do nada segundos depois e
                    // parecia falha de renderizacao
                    if (_carregandoContorno)
                      Text(
                        'Traçando o bairro...',
                        style: AppTextStyles.caption.copyWith(
                          color: isDark ? Colors.white38 : Colors.black45,
                        ),
                      )
                    else if (local.detalhe.isNotEmpty)
                      Text(
                        local.detalhe,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.caption.copyWith(
                          color: isDark ? Colors.white38 : Colors.black45,
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  _buscaController.clear();
                  setState(_limparDestaqueBusca);
                },
                icon: Icon(Icons.close_rounded, color: isDark ? Colors.white38 : Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: _tracarRotaAteLocalBuscado,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(gradient: gradientePrincipal, borderRadius: BorderRadius.circular(14)),
                child: Center(
                  child: _buscandoOrigemRota
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                        )
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.directions_rounded, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Traçar rota',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // chips pra escolher entre os trajetos que vieram na mesma resposta da
  // Directions API -- rola na horizontal porque o Google pode devolver 3
  // alternativas e os rotulos nao cabem numa linha fixa em tela pequena
  Widget _seletorAlternativas(bool isDark) {
    final ativa = _rotaAtual!;
    final maisRapidaSegundos =
        ativa.opcoes.map((o) => o.duracaoSegundos).reduce((a, b) => a < b ? a : b);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < ativa.opcoes.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _chipAlternativa(i, ativa.opcoes[i], maisRapidaSegundos, isDark),
          ],
        ],
      ),
    );
  }

  Widget _chipAlternativa(int indice, RotaOpcao opcao, int maisRapidaSegundos, bool isDark) {
    final selecionado = indice == _rotaAtual!.indiceSelecionado;

    // compara com a mais rapida pra dar contexto ("+7 min" diz muito mais que
    // o tempo absoluto sozinho). Empate exato no segundo conta como mais
    // rapida; diferenca que arredonda pra zero mostra "+1 min" em vez de
    // fingir que sao iguais
    final ehMaisRapida = opcao.duracaoSegundos == maisRapidaSegundos;
    final atrasoMin = ((opcao.duracaoSegundos - maisRapidaSegundos) / 60).round();
    final rotulo = ehMaisRapida ? 'Mais rápida' : '+${atrasoMin < 1 ? 1 : atrasoMin} min';

    return GestureDetector(
      onTap: _carregandoRota ? null : () => _selecionarAlternativa(indice),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: selecionado ? gradientePrincipal : null,
          color: selecionado ? null : (isDark ? Colors.white.withAlpha(10) : Colors.grey.withAlpha(15)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              opcao.duracaoTexto,
              style: AppTextStyles.captionBold.copyWith(
                color: selecionado ? Colors.white : (isDark ? Colors.white : Colors.black87),
              ),
            ),
            const SizedBox(height: 1),
            Text(
              rotulo,
              style: AppTextStyles.label.copyWith(
                color: selecionado
                    ? Colors.white.withAlpha(200)
                    : (ehMaisRapida ? corSucesso : (isDark ? Colors.white38 : Colors.grey)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seletorModoTransporte(bool isDark) {
    const opcoes = [
      (TravelMode.driving, Icons.directions_car_rounded),
      (TravelMode.walking, Icons.directions_walk_rounded),
      (TravelMode.bicycling, Icons.directions_bike_rounded),
      (TravelMode.twoWheeler, Icons.two_wheeler_rounded),
      (TravelMode.transit, Icons.directions_bus_rounded),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: opcoes.map((opcao) {
        final (modo, icone) = opcao;
        final selecionado = _modoTransporteUi == modo;
        return GestureDetector(
          onTap: _carregandoRota ? null : () => _trocarModoTransporte(modo),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: selecionado ? gradientePrincipal : null,
              color: selecionado ? null : (isDark ? Colors.white.withAlpha(10) : Colors.grey.withAlpha(15)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icone, size: 20, color: selecionado ? Colors.white : (isDark ? Colors.white54 : Colors.grey.shade700)),
          ),
        );
      }).toList(),
    );
  }

  // antes so checava "== ThemeMode.dark" -- como o padrao do app e
  // ThemeMode.system, o mapa nunca respeitava o modo escuro do celular
  // (sempre caia no estilo claro). Agora, quando ta em "sistema", consulta
  // o brightness real da plataforma
  bool get _deveUsarEstiloEscuro {
    if (temaGlobal.value == ThemeMode.dark) return true;
    if (temaGlobal.value == ThemeMode.light) return false;
    return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
  }

  void _atualizarEstiloMapa() {
    if (_estiloMapaEscuro.isEmpty) return;
    String? novoEstilo;
    if (_modoMapaAtual != 'Satélite') {
      novoEstilo = _deveUsarEstiloEscuro ? _estiloMapaEscuro : _estiloMapaLimpo;
    }
    if (mounted) setState(() => _estiloAtivo = novoEstilo);
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    _atualizarEstiloMapa();
    // so centraliza sozinho em quem JA permitiu antes -- abrir o app pedindo
    // permissao antes de a pessoa ver o mapa e pedir sem ter explicado nada
    _centralizarSeJaPermitido();
  }

  // chip fixo na barra superior -- so navega a camera ate a cidade parceira
  // escolhida, nunca oculta/filtra imovel nenhum (isso e trabalho do filtro
  // de cidade que fica dentro da folha de Filtros, uma funcao separada)
  // filtros + configuracoes, com divisor vertical, vivendo DENTRO do painel
  // de vidro da busca (igual a referencia). Sem GlassCard proprio de
  // proposito: vidro dentro de vidro aplicaria o BackdropFilter duas vezes --
  // dobra o custo e o resultado sai turvo
  // rotulo que substitui o campo quando ha local escolhido e nada em foco.
  // Toca pra voltar a editar -- o TextField reaparece com o nome completo,
  // que continua guardado no controller
  Widget _rotuloLocalNaBusca(bool isDark) {
    return GestureDetector(
      onTap: () {
        setState(() => _editandoBusca = true);
        // o foco so pode ser pedido depois que o TextField entrar na arvore
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _buscaFocusNode.requestFocus(),
        );
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md + 2),
        child: Row(
          children: [
            Icon(Icons.search_rounded, color: isDark ? Colors.white54 : Colors.black38, size: 20),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                _buscaController.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ajustesDentroDaBusca(bool isDark) {
    final Color corIcone = isDark ? Colors.white : const Color(0xFF14304F);

    Widget botao({required Widget icone, required VoidCallback onTap}) {
      return Pressionavel(
        onTap: onTap,
        child: SizedBox(width: 42, height: 44, child: Center(child: icone)),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // divisor que some nas pontas -- linha de ponta a ponta brigaria com
        // a borda refratada do vidro
        Container(
          width: 1,
          height: 22,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                corIcone.withAlpha(0),
                corIcone.withAlpha(isDark ? 60 : 50),
                corIcone.withAlpha(0),
              ],
            ),
          ),
        ),
        botao(
          onTap: _mostrarFiltros,
          icone: Badge(
            isLabelVisible: _filtroState.temFiltrosAtivos,
            smallSize: 7,
            backgroundColor: corPrimaria,
            child: Icon(Icons.tune_rounded, color: corIcone, size: 21),
          ),
        ),
        botao(
          onTap: _mostrarConfiguracoes,
          icone: Icon(Icons.settings_rounded, color: corIcone, size: 21),
        ),
        const SizedBox(width: AppSpacing.xs),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildSeletorCidadeGlobal(bool isDark) {
    return Pressionavel(
      onTap: _abrirSeletorCidadeGlobal,
      child: GlassCard(
        radius: 20,
        sombra: AppShadows.nivel1(isDark),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm + 1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.explore_outlined, size: 16, color: isDark ? Colors.white54 : corPrimaria.withAlpha(180)),
            const SizedBox(width: AppSpacing.sm - 2),
            Text(
              'Cidades parceiras',
              style: AppTextStyles.captionBold.copyWith(
                fontSize: 12,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // essa barra e so pras cidades PARCEIRAS do app (lista fixa) -- nao mistura
  // com cidades soltas vindas de imoveis cadastrados, e so move a camera (voo
  // suave ate o centro da cidade); nunca esconde nem filtra nenhum imovel
  void _abrirSeletorCidadeGlobal() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? superficieEscura : superficieClara,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Cidades parceiras', style: AppTextStyles.heading3.copyWith(color: isDark ? Colors.white : Colors.black87)),
                const SizedBox(height: 4),
                Text(
                  'Só leva a câmera até a região escolhida -- nenhum imóvel some do mapa. Pra buscar um endereço específico, use a busca lá em cima.',
                  style: AppTextStyles.caption.copyWith(color: isDark ? Colors.white38 : Colors.grey),
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.zoom_out_map_rounded, color: corPrimaria),
                        title: const Text('Visão geral'),
                        subtitle: const Text('Só afasta o zoom, sem mover o mapa'),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          // so um zoom out de verdade -- mantem o centro onde
                          // a camera ja esta, nao pula pra nenhuma coordenada fixa
                          _mapController?.animateCamera(CameraUpdate.zoomOut());
                        },
                      ),
                      for (final cidade in cidadesParceiras)
                        ListTile(
                          leading: const Icon(Icons.location_city_rounded, color: corPrimaria),
                          title: Text(cidade.texto, style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _mapController?.animateCamera(CameraUpdate.newLatLngZoom(cidade.destino, 13));
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // o que a pessoa digitou no campo de preco, em reais. Vazio (ou zero) = sem
  // limite naquela ponta
  double? _precoDigitado(TextEditingController campo) {
    final so = campo.text.replaceAll(RegExp(r'[^0-9]'), '');
    final valor = double.tryParse(so);
    return (valor == null || valor == 0) ? null : valor;
  }

  // faixas prontas -- quase todo aluguel de estudante cai numa dessas, e um
  // toque preenche os dois campos. (minimo, maximo, rotulo); null = ponta aberta
  static const List<(double?, double?, String)> _faixasSugeridas = [
    (null, 600, 'Até 600'),
    (600, 1000, '600 a 1.000'),
    (1000, 1500, '1.000 a 1.500'),
    (1500, null, 'Acima de 1.500'),
  ];

  void _mostrarFiltros() {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final List<String> tagsTemp = List.from(_filtroState.tagsSelecionadas);
    final List<String> contasTemp = List.from(_filtroState.contasSelecionadas);
    final List<String> localidadesTemp = List.from(_filtroState.localidadesSelecionadas);
    final List<String> categoriasTemp = List.from(_filtroState.categoriasSelecionadas);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      // a folha desenha o proprio fundo (cantos, borda de luz e sombra), por
      // isso o do modal sai da frente
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _CamposDePreco(
          minimoInicial: _filtroState.precoMinimo?.toInt().toString() ?? '',
          maximoInicial: _filtroState.precoMaximo?.toInt().toString() ?? '',
          builder: (context, precoMinCtrl, precoMaxCtrl) => StatefulBuilder(
          builder: (context, setModalState) {
            // ja sai ordenado: quem digita 1500 no minimo e 800 no maximo
            // quis a mesma faixa ao contrario, e nao um mapa vazio
            var minimo = _precoDigitado(precoMinCtrl);
            var maximo = _precoDigitado(precoMaxCtrl);
            if (minimo != null && maximo != null && minimo > maximo) {
              final troca = minimo;
              minimo = maximo;
              maximo = troca;
            }
            final int quantosFiltros = (minimo != null ? 1 : 0) +
                (maximo != null ? 1 : 0) +
                tagsTemp.length +
                contasTemp.length +
                localidadesTemp.length +
                categoriasTemp.length;
            final int resultados = _quantosAtendem(
              precoMinimo: minimo,
              precoMaximo: maximo,
              tags: tagsTemp,
              contas: contasTemp,
              localidades: localidadesTemp,
              categorias: categoriasTemp,
            );
            // filtrar so por "Farmácias" deixa zero anuncio e ainda assim
            // enche o mapa de pins -- o botao tem que contar os dois
            final int pontosDeInteresse = _quantosLugares(categoriasTemp);

            return Container(
              margin: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              decoration: BoxDecoration(
                color: isDark ? corCardEscuro : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
                // fio de luz na borda de cima -- e o que separa a folha do
                // mapa escuro atras sem precisar de sombra pesada
                border: Border(
                  top: BorderSide(color: isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(10)),
                ),
                boxShadow: AppShadows.nivel3(isDark),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xxl, AppSpacing.md, AppSpacing.xxl, AppSpacing.xxl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white.withAlpha(30) : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),

                      // cabecalho: selo da marca, titulo e quantos filtros
                      // estao de pe agora
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              gradient: gradientePrincipal,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              boxShadow: AppShadows.marca(forca: 0.6),
                            ),
                            child: const Icon(Icons.tune_rounded, color: Colors.white, size: 20),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Filtrar busca',
                                  style: AppTextStyles.heading3.copyWith(
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                                Text(
                                  quantosFiltros == 0
                                      ? 'Nenhum filtro ativo'
                                      : '$quantosFiltros ${quantosFiltros == 1 ? 'filtro ativo' : 'filtros ativos'}',
                                  style: AppTextStyles.caption.copyWith(
                                    color: quantosFiltros == 0
                                        ? (isDark ? Colors.white38 : Colors.grey)
                                        : corPrimaria2,
                                    fontWeight:
                                        quantosFiltros == 0 ? FontWeight.w400 : FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // so aparece quando ha o que limpar -- botao morto
                          // ocupando o canto e parte do ar de tela inacabada
                          AnimatedOpacity(
                            duration: AppMotion.rapida,
                            opacity: quantosFiltros == 0 ? 0 : 1,
                            child: Pressionavel(
                              onTap: quantosFiltros == 0
                                  ? () {}
                                  : () => setModalState(() {
                                        precoMinCtrl.clear();
                                        precoMaxCtrl.clear();
                                        tagsTemp.clear();
                                        contasTemp.clear();
                                        localidadesTemp.clear();
                                        categoriasTemp.clear();
                                      }),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                                decoration: BoxDecoration(
                                  color: isDark ? Colors.white.withAlpha(12) : Colors.grey.withAlpha(20),
                                  borderRadius: BorderRadius.circular(AppRadius.pill),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.refresh_rounded,
                                        size: 14, color: isDark ? Colors.white60 : Colors.black54),
                                    const SizedBox(width: AppSpacing.xs),
                                    Text(
                                      'Limpar',
                                      style: AppTextStyles.caption.copyWith(
                                        color: isDark ? Colors.white60 : Colors.black54,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xl),

                      // --- categorias ---
                      // vem antes do preco por ser o corte mais grosso: decide
                      // O QUE aparece no mapa antes de refinar quanto custa
                      _rotuloSecao('Categorias', Icons.category_rounded, isDark),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Sem escolher nenhuma, o mapa mostra tudo.',
                        style: AppTextStyles.caption.copyWith(
                          color: isDark ? Colors.white38 : Colors.grey,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: opcoesCategoria
                            .map((opcao) => _chipFiltro(
                                  rotulo: opcao.rotulo,
                                  icone: opcao.icone,
                                  selecionado: categoriasTemp.contains(opcao.id),
                                  isDark: isDark,
                                  onTap: () => setModalState(() {
                                    if (categoriasTemp.contains(opcao.id)) {
                                      categoriasTemp.remove(opcao.id);
                                    } else {
                                      categoriasTemp.add(opcao.id);
                                    }
                                  }),
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: AppSpacing.xl),

                      // --- preco ---
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withAlpha(8) : superficieClara,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color: isDark ? Colors.white.withAlpha(12) : Colors.black.withAlpha(8),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _rotuloSecao('Quanto quer pagar', Icons.payments_rounded, isDark),
                                // o ciano e reservado a preco no app inteiro
                                // (ver gradienteSecundario em main.dart), e e
                                // ele que da a unica cor viva desta folha
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.md, vertical: AppSpacing.xs + 1),
                                  decoration: BoxDecoration(
                                    gradient: gradienteSecundario,
                                    borderRadius: BorderRadius.circular(AppRadius.pill),
                                  ),
                                  child: Text(
                                    _resumoDaFaixaDePreco(minimo, maximo),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            // dois campos em vez do slider: quem procura sabe
                            // o valor que cabe no bolso e digita direto, sem
                            // teto fixo e sem caçar a posicao certa na barra
                            Row(
                              children: [
                                Expanded(
                                  child: _campoPreco(
                                    controller: precoMinCtrl,
                                    rotulo: 'mínimo',
                                    isDark: isDark,
                                    aoMudar: () => setModalState(() {}),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                                  child: Text(
                                    'até',
                                    style: AppTextStyles.caption.copyWith(
                                      color: isDark ? Colors.white38 : Colors.grey,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: _campoPreco(
                                    controller: precoMaxCtrl,
                                    rotulo: 'máximo',
                                    isDark: isDark,
                                    aoMudar: () => setModalState(() {}),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.sm,
                              children: _faixasSugeridas.map((faixa) {
                                final (de, ate, rotulo) = faixa;
                                return _pilulaFaixa(
                                  rotulo: rotulo,
                                  selecionada: minimo == de && maximo == ate,
                                  isDark: isDark,
                                  onTap: () => setModalState(() {
                                    precoMinCtrl.text = de?.toInt().toString() ?? '';
                                    precoMaxCtrl.text = ate?.toInt().toString() ?? '';
                                  }),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),

                      // --- caracteristicas ---
                      _rotuloSecao('Características do imóvel', Icons.home_work_rounded, isDark),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: opcoesDeFiltro
                            .map((tag) => _chipFiltro(
                                  rotulo: tag,
                                  icone: iconeDaTag(tag),
                                  selecionado: tagsTemp.contains(tag),
                                  isDark: isDark,
                                  onTap: () => setModalState(() {
                                    if (tagsTemp.contains(tag)) {
                                      tagsTemp.remove(tag);
                                    } else {
                                      tagsTemp.add(tag);
                                    }
                                  }),
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: AppSpacing.xl),

                      // --- contas inclusas ---
                      _rotuloSecao('Contas inclusas no aluguel', Icons.receipt_long_rounded, isDark),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: opcoesContasInclusas
                            .map((conta) => _chipFiltro(
                                  rotulo: conta,
                                  icone: iconeDaConta(conta),
                                  selecionado: contasTemp.contains(conta),
                                  isDark: isDark,
                                  onTap: () => setModalState(() {
                                    if (contasTemp.contains(conta)) {
                                      contasTemp.remove(conta);
                                    } else {
                                      contasTemp.add(conta);
                                    }
                                  }),
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: AppSpacing.xl),

                      // --- localidade ---
                      _rotuloSecao('O que tem por perto', Icons.place_rounded, isDark),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: opcoesLocalidade.map((opcao) {
                          // so a faculdade sai de conta local; o resto depende
                          // da busca de lugares, que pode nao ter voltado (ou
                          // ter falhado). Chip apagado avisa disso em vez de
                          // filtrar e devolver mapa vazio sem explicacao
                          final habilitado =
                              opcao.id == localidadeFaculdade || _categoriasPerto.isNotEmpty;
                          return _chipFiltro(
                            rotulo: opcao.rotulo,
                            icone: opcao.icone,
                            selecionado: localidadesTemp.contains(opcao.id),
                            habilitado: habilitado,
                            isDark: isDark,
                            onTap: () => setModalState(() {
                              if (localidadesTemp.contains(opcao.id)) {
                                localidadesTemp.remove(opcao.id);
                              } else {
                                localidadesTemp.add(opcao.id);
                              }
                            }),
                          );
                        }).toList(),
                      ),
                      if (_categoriasPerto.isEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.6,
                                color: isDark ? Colors.white38 : Colors.grey,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'Buscando os estabelecimentos de cada imóvel.',
                                style: AppTextStyles.caption.copyWith(
                                  color: isDark ? Colors.white38 : Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xxl),

                      // o numero no botao responde antes do toque quantos
                      // imoveis sobram -- filtro que zera o mapa era
                      // descoberto so depois de fechar a folha
                      AnimatedGradientButton(
                        label: _rotuloDoBotaoDeFiltro(resultados, pontosDeInteresse),
                        icon: resultados == 0 && pontosDeInteresse == 0
                            ? Icons.search_off_rounded
                            : Icons.search_rounded,
                        onTap: () {
                          _filtroState.aplicarEstado(
                            precoMinimo: minimo,
                            precoMaximo: maximo,
                            tags: tagsTemp,
                            contas: contasTemp,
                            localidades: localidadesTemp,
                            categorias: categoriasTemp,
                          );

                          Navigator.pop(context);
                          final qtd = _filtroState.quantidadeAtiva;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                                  const SizedBox(width: 10),
                                  Text(qtd > 0
                                      ? '$qtd ${qtd == 1 ? 'filtro aplicado' : 'filtros aplicados'} no mapa!'
                                      : 'Filtros removidos - todos os imóveis visíveis.'),
                                ],
                              ),
                              backgroundColor: corSucesso,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              margin: const EdgeInsets.all(16),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
          ),
        );
      },
    );
  }

  // o que o botao da folha promete. Um filtro so de categoria (so "Postos",
  // por exemplo) nao deixa anuncio nenhum, mas tambem nao deixa o mapa vazio:
  // nesse caso o botao conta os pontos, e nao os imoveis
  String _rotuloDoBotaoDeFiltro(int imoveis, int pontos) {
    if (imoveis > 0) return 'Ver $imoveis ${imoveis == 1 ? 'imóvel' : 'imóveis'}';
    if (pontos > 0) return 'Ver $pontos ${pontos == 1 ? 'local' : 'locais'} no mapa';
    return 'Nenhum resultado com esses filtros';
  }

  // titulo de secao: icone em selo + texto. O selo e o que tira a folha do
  // "lista de textos cinzas" sem gritar mais que o conteudo
  Widget _rotuloSecao(String titulo, IconData icone, bool isDark) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: corPrimaria.withAlpha(isDark ? 55 : 22),
            borderRadius: BorderRadius.circular(AppRadius.sm - 4),
          ),
          child: Icon(icone, size: 14, color: isDark ? corDestaque : corPrimaria),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          titulo,
          style: AppTextStyles.captionBold.copyWith(
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ],
    );
  }

  // campo de valor da faixa de preco -- so digito, o "R$" fica no prefixo
  Widget _campoPreco({
    required TextEditingController controller,
    required String rotulo,
    required bool isDark,
    required VoidCallback aoMudar,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      style: TextStyle(
        color: isDark ? Colors.white : Colors.black87,
        fontWeight: FontWeight.w700,
        fontSize: 16,
      ),
      onChanged: (_) => aoMudar(),
      decoration: InputDecoration(
        hintText: rotulo,
        hintStyle: TextStyle(
          color: isDark ? Colors.white24 : Colors.grey.shade400,
          fontWeight: FontWeight.w400,
          fontSize: 14,
        ),
        prefixText: 'R\$ ',
        prefixStyle: TextStyle(
          color: isDark ? Colors.white38 : Colors.black45,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
        filled: true,
        fillColor: isDark ? corFundoEscuro : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(
            color: isDark ? Colors.white.withAlpha(15) : Colors.black.withAlpha(12),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: corPrimaria2, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.md + 2),
      ),
    );
  }

  // o texto da etiqueta de preco: diz em portugues o que a faixa significa,
  // inclusive quando so uma das pontas foi preenchida
  String _resumoDaFaixaDePreco(double? minimo, double? maximo) {
    String curto(double v) => formatarPreco(v).replaceAll(',00', '');
    if (minimo == null && maximo == null) return 'Qualquer valor';
    if (minimo == null) return 'Até ${curto(maximo!)}';
    if (maximo == null) return 'A partir de ${curto(minimo)}';
    return '${curto(minimo)} a ${curto(maximo)}';
  }

  // pilula das faixas prontas de preco -- menor e so de contorno, pra nao
  // competir com os chips de caracteristica logo abaixo
  Widget _pilulaFaixa({
    required String rotulo,
    required bool selecionada,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Pressionavel(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.rapida,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm - 2),
        decoration: BoxDecoration(
          color: selecionada
              ? corPrimaria.withAlpha(isDark ? 70 : 28)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selecionada
                ? corPrimaria2
                : (isDark ? Colors.white.withAlpha(25) : Colors.black.withAlpha(20)),
          ),
        ),
        child: Text(
          rotulo,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selecionada ? FontWeight.w700 : FontWeight.w500,
            color: selecionada
                ? (isDark ? Colors.white : corPrimaria)
                : (isDark ? Colors.white60 : Colors.black54),
          ),
        ),
      ),
    );
  }

  // chip dos filtros: mesmo desenho nas caracteristicas e na localidade.
  // Apagado (habilitado: false) = a informacao ainda nao chegou
  Widget _chipFiltro({
    required String rotulo,
    required IconData icone,
    required bool selecionado,
    required bool isDark,
    required VoidCallback onTap,
    bool habilitado = true,
  }) {
    final bool ligado = selecionado && habilitado;
    final Color corTexto = !habilitado
        ? (isDark ? Colors.white24 : Colors.grey.shade400)
        : ligado
            ? Colors.white
            : (isDark ? Colors.white70 : Colors.black87);

    return Pressionavel(
      onTap: habilitado ? onTap : () {},
      child: AnimatedContainer(
        duration: AppMotion.rapida,
        curve: AppMotion.suave,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
        decoration: BoxDecoration(
          gradient: ligado ? gradientePrincipal : null,
          color: ligado
              ? null
              : (isDark ? Colors.white.withAlpha(10) : Colors.white),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: ligado
                ? Colors.transparent
                : (isDark ? Colors.white.withAlpha(20) : Colors.black.withAlpha(15)),
          ),
          // o chip ligado sobe da superficie; o desligado so repousa nela
          boxShadow: ligado ? AppShadows.marca(forca: 0.5) : AppShadows.nivel1(isDark),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 15, color: ligado ? Colors.white : corTexto.withAlpha(200)),
            const SizedBox(width: AppSpacing.sm - 2),
            Text(
              rotulo,
              style: TextStyle(
                color: corTexto,
                fontSize: 13,
                fontWeight: ligado ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarPerfil() {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? superficieEscura : superficieClara,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (sheetContext) {
        return _PerfilPreview(
          perfil: _perfilAtual,
          onConcluirPerfil: () async {
            Navigator.pop(sheetContext);
            final atualizado = await Navigator.push<Usuario>(
              context,
              MaterialPageRoute(builder: (_) => ConcluirPerfilScreen(perfil: _perfilAtual)),
            );
            if (atualizado != null && mounted) {
              setState(() => _perfilAtual = atualizado);
            }
          },
          onSair: () {
            Navigator.pop(sheetContext);
            _confirmarLogout();
          },
          onVerNotificacoes: () {
            Navigator.pop(sheetContext);
            Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificacoesScreen()));
          },
        );
      },
    );
  }

  // pede confirmacao, desloga do firebase e limpa a pilha de telas -- a
  // AuthGate, la no main.dart, percebe sozinha que nao tem mais usuario e
  // troca pra tela de login (mesmo mecanismo usado no resto do app; nao
  // usamos rotas nomeadas em nenhum lugar, entao aqui tambem nao)
  Future<void> _confirmarLogout() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: isDark ? superficieEscura : superficieClara,
        title: const Text('Sair da conta?'),
        content: const Text('Você vai precisar entrar de novo pra acessar o app.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sair', style: TextStyle(color: corErro, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    await AuthService.instance.sair();
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _mostrarConfiguracoes() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            // recalculado aqui dentro (a partir do temaGlobal, nao do Theme.of
            // que so seria atualizado no proximo build da tela por baixo) --
            // antes isDark vinha de fora do StatefulBuilder e ficava preso no
            // valor de quando a folha abriu, so atualizando se fechasse e
            // abrisse ela de novo
            final bool isDark = temaGlobal.value == ThemeMode.dark ||
                (temaGlobal.value == ThemeMode.system &&
                    MediaQuery.platformBrightnessOf(context) == Brightness.dark);
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
              child: Container(
                color: isDark ? superficieEscura : superficieClara,
                padding: const EdgeInsets.all(24.0),
                child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withAlpha(40) : Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Text(
                    'Configurações',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.heading3.copyWith(
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 24),

                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withAlpha(12) : Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(
                        color: isDark ? Colors.white.withAlpha(16) : corPrimaria.withAlpha(20),
                      ),
                      boxShadow: AppShadows.nivel1(isDark),
                    ),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: gradientePrincipal,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          boxShadow: AppShadows.marca(forca: 0.35),
                        ),
                        child: const Icon(Icons.dark_mode_rounded, color: Colors.white, size: 20),
                      ),
                      title: Text(
                        'Tema do Sistema',
                        style: AppTextStyles.bodyBold.copyWith(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      trailing: DropdownButton<ThemeMode>(
                        value: temaGlobal.value,
                        underline: const SizedBox(),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        dropdownColor: isDark ? superficieEscura : superficieClara,
                        items: const [
                          DropdownMenuItem(value: ThemeMode.system, child: Text('Sistema')),
                          DropdownMenuItem(value: ThemeMode.light, child: Text('Claro')),
                          DropdownMenuItem(value: ThemeMode.dark, child: Text('Escuro')),
                        ],
                        onChanged: (ThemeMode? novoModo) {
                          if (novoModo != null) {
                            setModalState(() => temaGlobal.value = novoModo);
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _linhaLocalizacao(isDark, setModalState),
                  const SizedBox(height: 20),

                  Text(
                    'Estilo Visual do Mapa',
                    style: AppTextStyles.captionBold.copyWith(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(child: _botaoModoMapa('Normal', Icons.map_outlined, isDark, setModalState)),
                      const SizedBox(width: 12),
                      Expanded(child: _botaoModoMapa('Satélite', Icons.satellite_alt_rounded, isDark, setModalState)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Divider(color: isDark ? Colors.white.withAlpha(10) : Colors.grey.withAlpha(20)),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _confirmarLogout();
                    },
                    icon: const Icon(Icons.logout_rounded, color: corErro, size: 18),
                    label: const Text('Sair da conta', style: TextStyle(color: corErro, fontWeight: FontWeight.w600)),
                  ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // estado da localizacao dentro das Configuracoes -- e daqui que a pessoa
  // volta atras sem ter que caçar o botao do mapa, nos dois sentidos:
  // permitir depois de ter recusado, ou rever a permissao nos ajustes
  Widget _linhaLocalizacao(bool isDark, StateSetter setModalState) {
    final estado = LocalizacaoService.instance.estado.value;
    final bool ativa = estado == EstadoLocalizacao.permitida;

    final String situacao = switch (estado) {
      EstadoLocalizacao.permitida => 'Ativada - seguindo você em tempo real',
      EstadoLocalizacao.servicoDesligado => 'Localização do aparelho desligada',
      EstadoLocalizacao.negadaParaSempre => 'Bloqueada nos ajustes do sistema',
      _ => 'Desativada - toque para permitir',
    };

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withAlpha(12) : Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isDark ? Colors.white.withAlpha(16) : corPrimaria.withAlpha(20),
        ),
        boxShadow: AppShadows.nivel1(isDark),
      ),
      child: ListTile(
        onTap: () async {
          await pedirLocalizacaoComExplicacao(context);
          // a folha nao se redesenha sozinha: ela vive num StatefulBuilder
          setModalState(() {});
        },
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: ativa ? gradientePrincipal : null,
            color: ativa
                ? null
                : (isDark ? Colors.white.withAlpha(20) : Colors.grey.shade300),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            boxShadow: ativa ? AppShadows.marca(forca: 0.35) : null,
          ),
          child: Icon(
            ativa ? Icons.my_location_rounded : Icons.location_disabled_rounded,
            color: ativa ? Colors.white : (isDark ? Colors.white54 : Colors.black45),
            size: 20,
          ),
        ),
        title: Text(
          'Minha localização',
          style: AppTextStyles.bodyBold.copyWith(
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        subtitle: Text(
          situacao,
          style: AppTextStyles.caption.copyWith(
            color: ativa
                ? (isDark ? const Color(0xFF8FBEE8) : corPrimaria)
                : (isDark ? Colors.white38 : Colors.black45),
          ),
        ),
        trailing: Icon(
          Icons.arrow_forward_ios_rounded,
          size: 14,
          color: isDark ? Colors.white38 : Colors.black38,
        ),
      ),
    );
  }

  Widget _botaoModoMapa(String titulo, IconData icone, bool isDark, StateSetter setModalState) {
    bool isSelected = _modoMapaAtual == titulo;
    return GestureDetector(
      onTap: () {
        setModalState(() => _modoMapaAtual = titulo);
        setState(() => _modoMapaAtual = titulo);
        _atualizarEstiloMapa();
        Navigator.pop(context);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: isSelected ? gradientePrincipal : null,
          color: isSelected ? null : (isDark ? Colors.white.withAlpha(8) : Colors.grey.withAlpha(12)),
          borderRadius: BorderRadius.circular(16),
          boxShadow: isSelected
              ? [BoxShadow(color: corPrimaria.withAlpha(30), blurRadius: 8, offset: const Offset(0, 3))]
              : [],
        ),
        child: Column(
          children: [
            Icon(icone, color: isSelected ? Colors.white : (isDark ? Colors.white54 : Colors.grey), size: 28),
            const SizedBox(height: 8),
            Text(
              titulo,
              style: TextStyle(
                color: isSelected ? Colors.white : (isDark ? Colors.white54 : Colors.grey),
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // avatar com anel de estado, igual a referencia. Pendente (cadastro
  // incompleto) sempre ambar, pra nao se perder no meio da cor da foto.
  // Completo: verde por padrao, ou a cor extraida da propria foto de perfil
  // quando tem uma -- o anel passa a ornar com a pessoa em vez de ser um
  // verde generico.
  //
  // O ponto no canto muda de papel dependendo do estado: com o cadastro
  // pendente ele reforça o ambar do anel; com o cadastro completo ele vira
  // o indicador de notificação não lida (some assim que não tem novidade).
  Widget _buildGlassButton({
    required Widget child,
    required VoidCallback onTap,
    Color? badgeColor,
  }) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool pendente = badgeColor != null;
    final String fotoUrl = _perfilAtual.fotoUrl;

    return Pressionavel(
      onTap: onTap,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 44 com raio 22 = circulo, entao reusa a mesma primitiva de vidro
            // dos cards em vez de manter um caminho proprio
            GlassCard(
              radius: 22,
              espessura: 1.2,
              child: SizedBox(width: 44, height: 44, child: Center(child: child)),
            ),
            // anel por cima, sem preenchimento
            IgnorePointer(
              child: FutureBuilder<Color?>(
                future: (!pendente && fotoUrl.isNotEmpty) ? corDaFoto(fotoUrl) : null,
                initialData: pendente ? null : corDaFotoSalva(fotoUrl),
                builder: (context, snapshot) {
                  final corAnel = pendente ? corAtencao : (snapshot.data ?? corSucesso);
                  return Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: corAnel.withAlpha(215), width: 2),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              top: 1,
              right: 2,
              child: pendente
                  ? _pontoAnel(corAtencao, isDark)
                  : ValueListenableBuilder<int>(
                      valueListenable: NotificacaoService.instance.naoLidas,
                      builder: (_, naoLidas, _) =>
                          naoLidas > 0 ? _pontoAnel(corErro, isDark) : const SizedBox.shrink(),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pontoAnel(Color cor, bool isDark) => Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(
          color: cor,
          shape: BoxShape.circle,
          border: Border.all(color: isDark ? superficieEscura : superficieClara, width: 2),
        ),
      );

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    // em tela cheia a barra de status some e padding.top vira 0, o que
    // colaria a barra de busca na borda de cima -- o minimo garante respiro
    // em tela cheia a barra de status some e padding.top vira 0. O minimo
    // aqui e so pra nao colar na borda -- ficava alto demais quando era 26,
    // porque sobrava o espaco que a barra de status ocupava antes
    final double recuoTopo = MediaQuery.of(context).padding.top;
    final double topOffset = (recuoTopo > 0 ? recuoTopo : 6) + 8;
    final bool podeAnunciar = _perfilAtual.perfilCompleto &&
        _perfilAtual.tipoUsuario.toLowerCase() == 'proprietario';

    // altura aproximada que o card do local buscado ocupa na base da tela --
    // usada pra levantar o FAB de localizacao e o botao de anunciar
    final double alturaCardLocal = _mostrandoCardLocal ? 152 : 0;

    // com extendBody: true o body vai ate a base da TELA, entao qualquer
    // `bottom:` daqui passa a medir do fim da tela e nao do topo da barra.
    //
    // Usa o valor REAL em vez de constante: com extendBody o Scaffold soma a
    // altura da barra ao padding.bottom do MediaQuery do body, justamente pra
    // o body poder se desviar dela. Chutar essa altura na mao deu errado duas
    // vezes -- primeiro contando a area segura em dobro, depois medindo a
    // barra por pixel (o que variou conforme o conteudo do mapa atras)
    final double acimaDaBarra = MediaQuery.of(context).padding.bottom;

    // sem isso o mapa fica pedindo permissao por conta propria e os botoes
    // que dependem da posicao nao teriam como se mostrar desligados
    final bool temLocalizacao = LocalizacaoService.instance.permitida;

    return Stack(
      children: [
        GoogleMap(
          onMapCreated: _onMapCreated,
          // o Flutter nao informa a CAUSA do movimento da camera (gesto do
          // usuario ou animacao nossa). A heuristica: se comecou a mover e
          // nao acabamos de pedir uma animacao, foi o dedo -- ai paramos de
          // seguir e mostramos o botao de recentralizar, em vez de disputar
          // o controle da camera com quem esta olhando o mapa
          onCameraMoveStarted: () {
            if (!_navegando || !_seguindoCamera) return;
            final desdeOAjuste =
                DateTime.now().difference(_ultimoAjusteCamera).inMilliseconds;
            if (desdeOAjuste > 1300) {
              setState(() => _seguindoCamera = false);
            }
          },
          initialCameraPosition: CameraPosition(target: posicaoInatel, zoom: 15.0),
          // so liga o ponto azul com permissao NOSSA na mao: com true o
          // proprio plugin do mapa abre o dialogo do sistema por fora, sem
          // explicar nada -- e e justamente a pergunta que a gente quer fazer
          // no nosso tempo, com o motivo na frente
          myLocationEnabled: temLocalizacao && !_navegando,
          myLocationButtonEnabled: false,
          // com extendBody o mapa passa por baixo da barra; esse padding
          // empurra o logo do Google e a atribuicao pra cima dela, o que a
          // licenca de uso da API exige que fiquem visiveis.
          // Soma o card do local quando ele esta aberto, senao ele cobre o
          // logo -- o padding tem que acompanhar TUDO que flutua na base
          // o alvo da camera fica no centro da area util. Durante a
          // navegacao um recuo grande no topo empurra esse centro pra baixo,
          // deixando mais mapa a frente visivel -- que e o que importa
          // enquanto se desloca
          padding: EdgeInsets.only(
            top: _navegando ? 260 : 0,
            // na navegacao a barra inferior some, mas entra o painel de
            // encerrar -- o logo do Google tem que ficar acima dele
            bottom: _navegando
                ? MediaQuery.of(context).padding.bottom + 96
                // o plugin ja poe uma margem propria em volta do logo; sem
                // o card, tirar 6 faz ele encostar na barra em vez de flutuar
                // solto no mapa, ainda sem ficar coberto por ela
                : acimaDaBarra + (_mostrandoCardLocal ? alturaCardLocal : -6),
          ),
          zoomControlsEnabled: false,
          // a bussola nativa aparecia no canto superior esquerdo, atras do
          // avatar do perfil, e a barrinha do Google Maps (rota/abrir no app)
          // surgia no canto inferior direito ao tocar num pin, atras do botao
          // de centralizar. O app ja tem botoes proprios pra essas funcoes
          compassEnabled: false,
          mapToolbarEnabled: false,
          markers: {
            // seta direcional -- substitui o ponto azul padrao durante a
            // navegacao (myLocationEnabled desliga logo abaixo)
            if (_navegando && _posicaoNav != null && _setaNav != null)
              Marker(
                markerId: const MarkerId('seta_navegacao'),
                position: LatLng(_posicaoNav!.latitude, _posicaoNav!.longitude),
                icon: _setaNav!,
                // rotation em graus de bussola. Como a camera tambem gira pelo
                // rumo, a seta acaba sempre apontando pro topo da tela
                rotation: _rumoSuave,
                anchor: const Offset(0.5, 0.5), // gira em torno do proprio centro
                flat: true, // deita no mapa: acompanha giro e inclinacao
                zIndexInt: 5,
              ),
            // o Inatel fica FORA de _marcadores de proposito: e ponto de
            // referencia fixo, entao nao pode sumir quando o usuario filtra
            // por preco, tag ou cidade
            ?_marcadorInatel,
            if (!_navegando) ..._marcadoresImobiliarias,
            if (!_navegando) ..._marcadoresLugares,
            // navegando, o mapa fica so com o trajeto, a seta e o destino.
            // Os pins de anuncios e o destaque da busca viram poluicao visual
            // exatamente quando o usuario tem menos tempo pra olhar a tela
            if (!_navegando) ..._marcadores,
            ..._marcadoresRota,
            if (!_navegando) ?_destaquePoiBusca,
          },
          polylines: {
            ..._rotas,
            if (!_navegando) ..._destaqueRuaBusca,
            if (!_navegando) ..._destaqueAreaBusca,
          },
          polygons: _navegando ? const {} : _preenchimentoAreaBusca,
          mapType: _modoMapaAtual == 'Satélite' ? MapType.satellite : MapType.normal,
          style: _estiloAtivo,
        ),

        if (!_navegando)
        Positioned(
          top: topOffset,
          left: 16,
          right: 16,
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
              // isola a camada: o painel de cima nao muda enquanto o mapa
              // arrasta, entao sem RepaintBoundary o Flutter pode redesenhar
              // rim/especular/sombra a cada frame do arraste de graca
              child: RepaintBoundary(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _buildGlassButton(
                        child: AvatarWidget(nome: _perfilAtual.nome, fotoUrl: _perfilAtual.fotoUrl, size: 44),
                        onTap: _mostrarPerfil,
                        badgeColor: _perfilAtual.perfilCompleto ? null : corErro,
                      ),
                      const SizedBox(width: 10),

                      Expanded(
                        child: GlassCard(
                          // era pilula; 22 deixa menos redondo sem virar caixa
                          radius: 22,
                          // UM painel de vidro so, com a busca e os controles
                          // dentro (igual a referencia) -- antes eram duas
                          // pecas separadas flutuando lado a lado
                          child: Row(
                            children: [
                              Expanded(
                                // com local escolhido e o campo sem foco,
                                // mostra um rotulo com reticencias em vez do
                                // TextField. Motivo: TextField nao tem
                                // overflow -- texto que nao cabe ele corta
                                // seco, e "Inatel - Instituto Nacional de
                                // Telecomunicacoes" virava "Inatel - Instituto
                                // Nac", parecendo que o nome era aquilo.
                                //
                                // Truncar a string do controller NAO serve:
                                // _atualizarMarcadoresFiltrados filtra os
                                // imoveis com contains() nesse mesmo texto, e
                                // com "..." no fim nenhum casaria -- os
                                // markers todos desapareceriam do mapa
                                child: (_localSelecionado != null && !_editandoBusca)
                                    ? _rotuloLocalNaBusca(isDark)
                                    : TextField(
                            controller: _buscaController,
                            focusNode: _buscaFocusNode,
                            // centraliza o texto na vertical. Sem isso o
                            // InputDecoration alinhava o conteudo pela
                            // baseline e o hint ficava ~3px acima do centro da
                            // pilula, desalinhado dos icones da direita --
                            // acontece quando ha prefixIcon e nenhum suffixIcon
                            textAlignVertical: TextAlignVertical.center,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black87,
                              fontSize: 15,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Buscar locais...',
                              hintStyle: TextStyle(
                                color: isDark ? Colors.white38 : Colors.black38,
                                fontWeight: FontWeight.w500,
                              ),
                              border: InputBorder.none,
                              prefixIcon: Icon(Icons.search_rounded, color: isDark ? Colors.white54 : Colors.black38, size: 20),
                              // o botao de filtros saiu de dentro do campo e
                              // foi pro controle da direita, junto da
                              // engrenagem -- so o "limpar" continua aqui,
                              // porque pertence ao texto digitado
                              suffixIcon: _buscaComTexto
                                  ? IconButton(
                                      icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 20),
                                      onPressed: () => _buscaController.clear(),
                                    )
                                  : null,
                              contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md - 1),
                            ),
                          ),
                              ),
                              _ajustesDentroDaBusca(isDark),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  // chip de "Cidades parceiras" retirado da UI a pedido
                  // (feature parada por enquanto). Os metodos continuam
                  // abaixo, marcados como nao usados -- e so religar aqui

                  // o painel aparece assim que ha o que dizer -- inclusive
                  // "estou procurando" e "nao achei". Sumir sem explicacao
                  // enquanto a busca online roda parecia busca quebrada
                  if (_buscaFocusNode.hasFocus &&
                      _buscaComTexto &&
                      (_sugestoes.isNotEmpty || _buscandoOnline || _semResultado))
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      constraints: const BoxConstraints(maxHeight: 260),
                      decoration: BoxDecoration(
                        color: isDark ? superficieEscura : superficieClara,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withAlpha(isDark ? 60 : 15), blurRadius: 16, offset: const Offset(0, 6)),
                        ],
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        // a ultima linha e o rodape de estado (procurando /
                        // nao achei), por isso o +1
                        itemCount: _sugestoes.length + (_rodapeBusca(isDark) == null ? 0 : 1),
                        separatorBuilder: (_, _) => Divider(
                          height: 1, indent: 56,
                          color: isDark ? Colors.white.withAlpha(10) : Colors.grey.withAlpha(20),
                        ),
                        itemBuilder: (context, index) {
                          if (index >= _sugestoes.length) {
                            return _rodapeBusca(isDark)!;
                          }
                          final sugestao = _sugestoes[index];
                          final IconData icone = switch (sugestao.tipo) {
                            TipoSugestao.cidade => Icons.location_city_rounded,
                            TipoSugestao.faculdade => Icons.school_rounded,
                            TipoSugestao.moradia => Icons.home_rounded,
                            TipoSugestao.endereco => Icons.signpost_outlined,
                          };
                          return ListTile(
                            dense: true,
                            leading: Icon(icone, color: corPrimaria),
                            title: Text(
                              sugestao.texto,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.bodyBold.copyWith(
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            // onde o lugar fica (cidade, estado) numa linha
                            // separada: antes vinha tudo grudado no titulo,
                            // numa linha so, e o nome do lugar se perdia
                            subtitle: sugestao.detalhe.isEmpty
                                ? null
                                : Text(
                                    sugestao.detalhe,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.caption.copyWith(
                                      color: isDark ? Colors.white38 : Colors.black45,
                                    ),
                                  ),
                            onTap: () => _selecionarSugestao(sugestao),
                          );
                        },
                      ),
                    ),
                ],
              ),
              ),
            ),
          ),
        ),

        // cartao com a distancia/duracao da rota pedida na tela de detalhes,
        // ou um spinner enquanto ela ainda ta sendo calculada
        if (!_navegando && (_carregandoRota || _rotaAtual != null))
          Positioned(
            top: topOffset + 68,
            left: 16,
            right: 16,
            child: _EntradaDeslizante(
              // desce de cima porque o card nasce colado no topo -- entrada na
              // direcao de onde o elemento "vem" explica a origem dele
              de: const Offset(0, -0.18),
              child: GlassCard(
              radius: 24,
              sombra: AppShadows.nivel3(isDark),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.lg - 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // navegando, o seletor de modal e o de alternativas saem:
                  // trocar de rota no meio do percurso nao faz sentido e eles
                  // roubam espaco de tela que a navegacao precisa
                  if (_rotaAtual != null && !_navegando) ...[
                    _seletorModoTransporte(isDark),
                    const SizedBox(height: 12),
                    Divider(height: 1, color: isDark ? Colors.white.withAlpha(10) : Colors.grey.withAlpha(20)),
                    const SizedBox(height: 12),
                    // so faz sentido oferecer escolha quando o Google mandou
                    // mais de um trajeto -- as vezes ele devolve um so
                    if (_rotaAtual!.opcoes.length > 1) ...[
                      _seletorAlternativas(isDark),
                      const SizedBox(height: 12),
                    ],
                  ],
                  _carregandoRota
                      ? Row(
                          children: [
                            const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: corPrimaria),
                            ),
                            const SizedBox(width: 12),
                            Text('Calculando rota...', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87)),
                          ],
                        )
                      : Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(gradient: gradientePrincipal, borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.alt_route_rounded, color: Colors.white, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Até ${_rotaAtual!.nomeDestino}',
                                    style: TextStyle(fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black87),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_rotaAtual!.selecionada.distanciaTexto} · ${_rotaAtual!.selecionada.duracaoTexto}',
                                    style: AppTextStyles.caption.copyWith(color: isDark ? Colors.white38 : Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            // "Ir" entra na navegacao; navegando, vira "Sair"
                            Pressionavel(
                              onTap: _navegando ? _encerrarNavegacao : _iniciarNavegacao,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.lg, vertical: AppSpacing.sm + 2),
                                decoration: BoxDecoration(
                                  gradient: _navegando ? null : gradientePrincipal,
                                  color: _navegando ? corErro : null,
                                  borderRadius: BorderRadius.circular(AppRadius.sm),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _navegando ? Icons.close_rounded : Icons.navigation_rounded,
                                      color: Colors.white,
                                      size: 17,
                                    ),
                                    const SizedBox(width: AppSpacing.xs + 2),
                                    Text(
                                      _navegando ? 'Sair' : 'Ir',
                                      style: AppTextStyles.captionBold.copyWith(color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (!_navegando)
                              IconButton(
                                onPressed: _limparRota,
                                icon: Icon(Icons.close_rounded, color: isDark ? Colors.white38 : Colors.grey),
                              ),
                          ],
                        ),
                ],
              ),
            ),
            ),
          ),

        // painel do modo navegacao -- substitui busca e card de rota
        if (_navegando) _painelNavegacao(isDark),

        // card do local buscado + botao de tracar rota ate ele
        if (_mostrandoCardLocal)
          Positioned(
            bottom: acimaDaBarra + AppSpacing.md,
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            // sobe de baixo, porque e na base que ele mora
            child: _EntradaDeslizante(
              de: const Offset(0, 0.22),
              child: _cardLocalBuscado(isDark),
            ),
          ),

        // botao pra focar na localizacao do usuario. Sai na navegacao: o
        // painel tem o proprio recentralizar e os dois colidiam no canto
        if (!_navegando)
        Positioned(
          // sobe se o botao de anunciar estiver visivel, e mais ainda se o
          // card do local buscado estiver ocupando a base da tela
          bottom: acimaDaBarra + alturaCardLocal + (podeAnunciar ? 84 : AppSpacing.md),
          right: 16,
          // era um FloatingActionButton solido -- virou vidro pra combinar com
          // as outras superficies flutuantes do mapa, e ganhou o retorno de
          // toque que o FAB do Material ja tinha e a gente perderia sem isso
          child: Pressionavel(
            onTap: _obterLocalizacaoReal,
            child: GlassCard(
              radius: 20,
              sombra: AppShadows.nivel2(isDark),
              child: SizedBox(
                width: 52,
                height: 52,
                child: Center(
                  // icone cortado quando nao ha permissao: o botao continua
                  // clicavel (abre a explicacao), mas dizendo de cara que a
                  // localizacao esta desligada em vez de fingir que funciona
                  child: Icon(
                    temLocalizacao
                        ? Icons.my_location_rounded
                        : Icons.location_disabled_rounded,
                    color: temLocalizacao
                        ? (isDark ? Colors.white : Colors.black87)
                        : (isDark ? Colors.white38 : Colors.black38),
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
        ),

        if (podeAnunciar && !_navegando)
          Positioned(
            bottom: acimaDaBarra + alturaCardLocal + AppSpacing.md,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                gradient: gradientePrincipal,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: corPrimaria.withAlpha(60),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const NovoAnuncioScreen()),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_home_rounded, color: Colors.white, size: 22),
                        SizedBox(width: 8),
                        Text(
                          'Anunciar',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// previa rapida do perfil (avatar, nome, selo de completo/incompleto) --
// a edicao de verdade agora mora toda em ConcluirPerfilScreen
class _PerfilPreview extends StatelessWidget {
  final Usuario perfil;
  final VoidCallback onConcluirPerfil;
  final VoidCallback onSair;
  final VoidCallback onVerNotificacoes;

  const _PerfilPreview({
    required this.perfil,
    required this.onConcluirPerfil,
    required this.onSair,
    required this.onVerNotificacoes,
  });

  String get _rotuloTipo {
    switch (perfil.tipoUsuario.toLowerCase()) {
      case 'proprietario':
        return 'Proprietário';
      case 'corretor':
        return perfil.subtipoCorretor == 'empresa' ? 'Corretor (Empresa)' : 'Corretor Autônomo';
      case 'estudante':
        return 'Estudante';
      default:
        return 'Tipo de conta não definido';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final corSelo = perfil.perfilCompleto ? corSucesso : corAtencao;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withAlpha(30) : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                AvatarWidget(
                  nome: perfil.nome.isNotEmpty ? perfil.nome : perfil.email,
                  fotoUrl: perfil.fotoUrl,
                  size: 72,
                  showOnlineIndicator: true,
                ),
                const SizedBox(height: 16),
                Text(
                  perfil.nome.isNotEmpty ? perfil.nome : 'Usuário Hive',
                  style: AppTextStyles.heading3.copyWith(color: isDark ? Colors.white : Colors.black87),
                ),
                const SizedBox(height: 4),
                Text(_rotuloTipo, style: AppTextStyles.captionBold.copyWith(color: corPrimaria)),
                const SizedBox(height: 4),
                Text(
                  perfil.email,
                  style: AppTextStyles.caption.copyWith(color: isDark ? Colors.white38 : Colors.grey),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: corSelo.withAlpha(25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    perfil.perfilCompleto ? 'Perfil completo' : 'Perfil incompleto',
                    style: TextStyle(color: corSelo, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          AnimatedGradientButton(
            label: perfil.perfilCompleto ? 'Editar Perfil' : 'Concluir Perfil',
            onTap: onConcluirPerfil,
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<int>(
            valueListenable: NotificacaoService.instance.naoLidas,
            builder: (_, naoLidas, _) => OutlinedButton.icon(
              onPressed: onVerNotificacoes,
              icon: Icon(Icons.notifications_none_rounded, color: isDark ? Colors.white : Colors.black87, size: 18),
              label: Text(
                naoLidas > 0 ? 'Notificações ($naoLidas)' : 'Notificações',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                side: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onSair,
            icon: const Icon(Icons.logout_rounded, color: corErro, size: 18),
            label: const Text('Sair da conta', style: TextStyle(color: corErro, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
// entrada de elemento flutuante: desliza da direcao de onde ele "vem" e
// aparece por fade ao mesmo tempo. Elemento que simplesmente pisca na tela
// nao explica de onde surgiu -- o deslize curto (uma fracao da altura) da
// essa leitura sem atrasar a interface.
//
// StatefulWidget e nao AnimatedOpacity solto porque precisa disparar uma vez
// na montagem; como os cards do mapa sao inseridos/removidos por `if` no
// Stack, cada aparicao monta um novo e roda a animacao de novo.
class _EntradaDeslizante extends StatefulWidget {
  final Widget child;
  final Offset de;

  const _EntradaDeslizante({required this.child, required this.de});

  @override
  State<_EntradaDeslizante> createState() => _EntradaDeslizanteState();
}

class _EntradaDeslizanteState extends State<_EntradaDeslizante>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.media,
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curva = CurvedAnimation(parent: _controller, curve: AppMotion.suave);
    return FadeTransition(
      opacity: curva,
      child: SlideTransition(
        position: Tween<Offset>(begin: widget.de, end: Offset.zero).animate(curva),
        child: widget.child,
      ),
    );
  }
}

// dona dos dois campos de preco da folha de filtros.
//
// Os TextEditingController nao podem ser descartados assim que o
// showModalBottomSheet retorna: a folha ainda esta descendo na tela e os
// TextField se reconstroem durante a animacao -- usar um controller ja
// descartado ali lanca "A TextEditingController was used after being
// disposed". Como widget, o descarte cai no dispose dela, que so roda quando
// a rota sai de vez
class _CamposDePreco extends StatefulWidget {
  final String minimoInicial;
  final String maximoInicial;
  final Widget Function(BuildContext, TextEditingController, TextEditingController) builder;

  const _CamposDePreco({
    required this.minimoInicial,
    required this.maximoInicial,
    required this.builder,
  });

  @override
  State<_CamposDePreco> createState() => _CamposDePrecoState();
}

class _CamposDePrecoState extends State<_CamposDePreco> {
  late final TextEditingController _minimo = TextEditingController(text: widget.minimoInicial);
  late final TextEditingController _maximo = TextEditingController(text: widget.maximoInicial);

  @override
  void dispose() {
    _minimo.dispose();
    _maximo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _minimo, _maximo);
}
