import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart' show TravelMode;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'concluir_perfil_screen.dart';
import 'detalhes_imovel_screen.dart';
import 'novo_anuncio_screen.dart';
import '../main.dart';
import '../models/imovel.dart';
import '../models/filtro_state.dart';
import '../models/usuario.dart';
import '../services/auth_service.dart';
import '../services/busca_service.dart';
import '../services/imobiliaria_service.dart';
import '../services/rota_service.dart';
import '../services/usuario_service.dart';
import '../utils/localizacao.dart';
import '../utils/moderacao.dart';
import '../widgets/avatar_widget.dart';
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
  List<SugestaoBusca> _sugestoes = [];

  String _modoMapaAtual = 'Normal';

  late Usuario _perfilAtual;

  String _estiloMapaEscuro = '';
  String _estiloMapaLimpo = '';
  String? _estiloAtivo;

  final FiltroState _filtroState = FiltroState();

  Set<Marker> _marcadores = {};
  bool _buscaComTexto = false;

  // destaque visual do resultado de busca selecionado -- rua vira linha
  // solida, bairro/regiao vira contorno tracejado SEM preenchimento (igual o
  // Google Maps mostra), ponto de interesse vira marker
  Set<Polyline> _destaqueRuaBusca = {};
  Set<Polyline> _destaqueAreaBusca = {};
  Marker? _destaquePoiBusca;

  // ultimo resultado de busca escolhido -- fica guardado pra oferecer o
  // "Traçar rota" ate ele (igual o Google Maps, que mostra o botao de rotas
  // no card do local depois que voce seleciona um ponto da busca)
  SugestaoBusca? _localSelecionado;
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
  late VoidCallback _cidadeFiltroListener;
  late VoidCallback _rotaAtivaListener;
  late VoidCallback _rotaCarregandoListener;
  late VoidCallback _rotaErroListener;

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
    _obterLocalizacaoReal(); // ja dispara a busca do gps ao abrir a tela
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

    FirebaseFirestore.instance.collection('imoveis').snapshots().listen((snapshot) {
      if (mounted) {
        setState(() {
          _imoveisDoBanco = snapshot.docs
              .map((doc) => Imovel.fromMap(doc.data(), doc.id))
              .toList();
        });
        _atualizarMarcadoresFiltrados();
      }
    });

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
      if (mounted) _atualizarMarcadoresFiltrados();
    };
    _filtroState.addListener(_filtroListener);

    _cidadeFiltroListener = () {
      if (mounted) _atualizarMarcadoresFiltrados();
    };
    cidadeFiltroGlobal.addListener(_cidadeFiltroListener);

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
      if (mounted) setState(() => _carregandoRota = rotaCarregandoGlobal.value);
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

    _buscaController.addListener(() {
      setState(() {
        _buscaComTexto = _buscaController.text.isNotEmpty;
        if (!_buscaComTexto) _limparDestaqueBusca();
      });
      _atualizarMarcadoresFiltrados();

      // debounce so pras sugestoes -- evita recalcular a lista a cada tecla
      _debounceSugestoes?.cancel();
      _debounceSugestoes = Timer(const Duration(milliseconds: 400), () async {
        if (!mounted) return;
        final termo = _buscaController.text;

        // sugestoes locais (imoveis + lista fixa de faculdades/cidades
        // conhecidas) aparecem na hora, sem depender de internet
        setState(() {
          _sugestoes = BuscaService.instance.buscarSugestoes(termo, _imoveisDoBanco);
        });

        // se ja achou uma instituicao conhecida (Inatel, UNIFEI, FAI, UNIVÁS...)
        // na lista fixa, nao busca online pra essa mesma consulta -- evita que
        // um bairro/regiao homonimo do Nominatim apareca do lado do pin certo
        // e a pessoa acabe clicando no lugar errado
        final achouInstituicaoConhecida = _sugestoes.any((s) => s.tipo == TipoSugestao.faculdade);
        if (achouInstituicaoConhecida) return;

        // ruas, bairros e cidades de verdade vem depois, via busca online --
        // soma na lista sem duplicar, e so aplica se o texto nao mudou nesse meio tempo
        final locaisOnline = await BuscaService.instance.buscarLocaisOnline(termo);
        if (!mounted || _buscaController.text != termo || locaisOnline.isEmpty) return;
        setState(() {
          final jaTem = _sugestoes.map((s) => normalizarNome(s.texto)).toSet();
          for (final local in locaisOnline) {
            if (jaTem.add(normalizarNome(local.texto))) _sugestoes.add(local);
          }
        });
      });
    });

    _buscaFocusNode.addListener(() => setState(() {}));
  }

  // pede permissao de localizacao e centraliza o mapa no gps
  Future<void> _obterLocalizacaoReal() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high)
    );

    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(position.latitude, position.longitude),
            zoom: 16.0,
          ),
        ),
      );
    }
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
      backgroundColor: isDark ? corCardEscuro : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
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
    _destaquePoiBusca = null;
    _localSelecionado = null;
  }

  // ao escolher um resultado, desenha o destaque certo pro tipo de local
  // (igual o Google Maps faz: rua pintada, bairro delimitado, POI com pin) e
  // enquadra a camera no que foi desenhado
  void _selecionarSugestao(SugestaoBusca sugestao) {
    _buscaController.text = sugestao.texto;
    _buscaFocusNode.unfocus();
    setState(() {
      _sugestoes = [];
      _limparDestaqueBusca();
      _localSelecionado = sugestao;

      switch (sugestao.tipoGeometria) {
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
          // igual o Google Maps mostra pra bairro/regiao: so o contorno
          // tracejado, sem nenhum preenchimento -- por isso e um Polyline
          // fechado (o Polygon do plugin nao suporta traco pontilhado) com
          // as pontas iguais, nao um Polygon com fillColor
          _destaqueAreaBusca = {
            Polyline(
              polylineId: const PolylineId('destaque_busca'),
              points: sugestao.pontosGeometria,
              color: const Color(0xFFE53935),
              width: 4,
              patterns: [PatternItem.dash(20), PatternItem.gap(12)],
            ),
          };
        case TipoGeometria.ponto:
          _destaquePoiBusca = Marker(
            markerId: const MarkerId('destaque_busca'),
            position: sugestao.destino,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
            infoWindow: InfoWindow(title: sugestao.texto),
          );
      }
    });

    if (sugestao.pontosGeometria.length > 1) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngBounds(RotaService.calcularBounds(sugestao.pontosGeometria), 60),
      );
    } else {
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(sugestao.destino, 16));
    }
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
    cidadeFiltroGlobal.removeListener(_cidadeFiltroListener);
    rotaAtivaGlobal.removeListener(_rotaAtivaListener);
    rotaCarregandoGlobal.removeListener(_rotaCarregandoListener);
    rotaErroGlobal.removeListener(_rotaErroListener);
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

  void _atualizarMarcadoresFiltrados() {
    final textoBusca = _buscaController.text.toLowerCase().trim();

    final imovelFiltrados = _imoveisDoBanco.where((item) {
      if (textoBusca.isNotEmpty) {
        final combinado = '${item.titulo} ${item.descricao}'.toLowerCase();
        if (!combinado.contains(textoBusca)) return false;
      }
      // evento nao tem preco de aluguel, entao pula so o filtro de preco
      if (item.tipo != TipoListing.evento && item.preco > _filtroState.precoMaximo) {
        return false;
      }
      if (_filtroState.tagsSelecionadas.isNotEmpty) {
        final temTodasAsTags = _filtroState.tagsSelecionadas
            .every((tag) => item.tags.contains(tag));
        if (!temTodasAsTags) return false;
      }
      if (cidadeFiltroGlobal.value != null && item.cidade != cidadeFiltroGlobal.value) {
        return false;
      }
      return true;
    }).toList();

    setState(() {
      _marcadores = imovelFiltrados.map((item) {
        final bool isEvento = item.tipo == TipoListing.evento;
        return Marker(
          markerId: MarkerId(item.id),
          position: item.posicao,
          icon: BitmapDescriptor.defaultMarkerWithHue(
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
      return;
    }
    // desenha todas as alternativas: as nao escolhidas em cinza e por baixo
    // (zIndex menor), clicaveis pra virar a ativa; a escolhida em destaque por
    // cima. consumeTapEvents evita que o toque atravesse a linha e caia no
    // mapa (que fecha paineis/limpa selecao)
    _rotas = {
      for (var i = 0; i < ativa.opcoes.length; i++)
        if (i != ativa.indiceSelecionado)
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
    _marcadoresRota = {
      Marker(
        markerId: const MarkerId('rota_origem'),
        position: ativa.origem,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
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

    if (rotaNova) {
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
    if (local == null || _buscandoOrigemRota) return;

    setState(() => _buscandoOrigemRota = true);
    LatLng? origem;
    try {
      origem = await obterLocalizacaoAtual();
    } catch (e) {
      origem = null;
    }
    if (!mounted) return;
    setState(() => _buscandoOrigemRota = false);

    if (origem == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não conseguimos acessar sua localização atual.'),
          backgroundColor: corErro,
        ),
      );
      return;
    }

    // mantem o modal que o usuario ja tinha escolhido no seletor, com o mesmo
    // desvio de "moto" que _trocarModoTransporte faz (nao existe na API classica)
    final modoParaApi =
        _modoTransporteUi == TravelMode.twoWheeler ? TravelMode.driving : _modoTransporteUi;

    rotaPendenteGlobal.value = RotaPendente(
      origem: origem,
      destino: local.destino,
      nomeDestino: local.texto,
      modo: modoParaApi,
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

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
      decoration: BoxDecoration(
        color: isDark ? corCardEscuro : Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(isDark ? 60 : 15), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(gradient: gradientePrincipal, borderRadius: BorderRadius.circular(10)),
                child: Icon(icone, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  local.texto,
                  style: TextStyle(fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black87),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
    _obterLocalizacaoReal();
  }

  // chip fixo na barra superior -- so navega a camera ate a cidade parceira
  // escolhida, nunca oculta/filtra imovel nenhum (isso e trabalho do filtro
  // de cidade que fica dentro da folha de Filtros, uma funcao separada)
  Widget _buildSeletorCidadeGlobal(bool isDark) {
    return GestureDetector(
      onTap: _abrirSeletorCidadeGlobal,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isDark ? corCardEscuro : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isDark ? Colors.white.withAlpha(15) : Colors.grey.withAlpha(40)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.explore_outlined, size: 15, color: isDark ? Colors.white54 : Colors.grey),
            const SizedBox(width: 6),
            Text(
              'Cidades parceiras',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black87),
            ),
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: isDark ? Colors.white54 : Colors.grey),
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
      backgroundColor: isDark ? corCardEscuro : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
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

  void _mostrarFiltros() {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    double precoTemp = _filtroState.precoMaximo;
    List<String> tagsTemp = List.from(_filtroState.tagsSelecionadas);
    String? cidadeTemp = cidadeFiltroGlobal.value;

    // mesma lista fixa de cidades parceiras usada no chip de cima -- so essas
    // 4 opcoes (+ "todas"), sem misturar com o resto da lista de busca
    final cidadesDisponiveis = cidadesParceiras.map((c) => c.texto).toList()..sort();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? corCardEscuro : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 24, right: 24, top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
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
                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Filtros de Busca',
                        style: AppTextStyles.heading3.copyWith(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          setModalState(() {
                            precoTemp = 3000;
                            tagsTemp.clear();
                            cidadeTemp = null;
                          });
                        },
                        icon: Icon(Icons.refresh_rounded, size: 16, color: isDark ? Colors.white38 : Colors.grey),
                        label: Text('Limpar', style: TextStyle(color: isDark ? Colors.white38 : Colors.grey)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  Text(
                    'Cidade / Região',
                    style: AppTextStyles.captionBold.copyWith(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    initialValue: cidadeTemp,
                    isExpanded: true,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                    dropdownColor: isDark ? corSuperficieEscura : Colors.white,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: isDark ? Colors.white.withAlpha(5) : Colors.grey.withAlpha(8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Todas as cidades')),
                      ...cidadesDisponiveis.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                    ],
                    onChanged: (val) => setModalState(() => cidadeTemp = val),
                  ),
                  const SizedBox(height: 20),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withAlpha(5) : Colors.grey.withAlpha(8),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Preço Máximo',
                              style: AppTextStyles.captionBold.copyWith(
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                gradient: gradienteSecundario,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'R\$ ${precoTemp.toInt()}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: corPrimaria,
                            inactiveTrackColor: isDark ? Colors.white.withAlpha(15) : Colors.grey.withAlpha(30),
                            thumbColor: corPrimaria,
                            overlayColor: corPrimaria.withAlpha(20),
                            trackHeight: 4,
                          ),
                          child: Slider(
                            value: precoTemp,
                            min: 300,
                            max: 3000,
                            divisions: 27,
                            onChanged: (valor) {
                              setModalState(() => precoTemp = valor);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  Text(
                    'Características do Imóvel',
                    style: AppTextStyles.captionBold.copyWith(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: tagsDisponiveis.map((tag) {
                      bool selecionado = tagsTemp.contains(tag);
                      return GestureDetector(
                        onTap: () {
                          setModalState(() {
                            if (selecionado) {
                              tagsTemp.remove(tag);
                            } else {
                              tagsTemp.add(tag);
                            }
                          });
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: selecionado ? gradientePrincipal : null,
                            color: selecionado
                                ? null
                                : (isDark ? Colors.white.withAlpha(10) : Colors.grey.withAlpha(18)),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: selecionado
                                ? [
                              BoxShadow(
                                color: corPrimaria.withAlpha(30),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                                : [],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (selecionado) ...[
                                const Icon(Icons.check_rounded, size: 14, color: Colors.white),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                tag,
                                style: TextStyle(
                                  color: selecionado ? Colors.white : (isDark ? Colors.white60 : Colors.black87),
                                  fontSize: 13,
                                  fontWeight: selecionado ? FontWeight.w600 : FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 28),

                  AnimatedGradientButton(
                    label: 'Mostrar Resultados',
                    icon: Icons.search_rounded,
                    onTap: () {
                      _filtroState.aplicarEstado(preco: precoTemp, tags: tagsTemp);
                      cidadeFiltroGlobal.value = cidadeTemp;

                      Navigator.pop(context);
                      final qtd = tagsTemp.length + (precoTemp < 3000 ? 1 : 0) + (cidadeTemp != null ? 1 : 0);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                              const SizedBox(width: 10),
                              Text(qtd > 0
                                  ? '$qtd filtro(s) aplicado(s) no mapa!'
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
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _mostrarPerfil() {
    bool isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? corCardEscuro : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
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
        backgroundColor: isDark ? corCardEscuro : Colors.white,
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
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
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              child: Container(
                color: isDark ? corCardEscuro : Colors.white,
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
                      color: isDark ? Colors.white.withAlpha(5) : Colors.grey.withAlpha(8),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: gradientePrincipal,
                          borderRadius: BorderRadius.circular(10),
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
                        borderRadius: BorderRadius.circular(12),
                        dropdownColor: isDark ? corSuperficieEscura : Colors.white,
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

  Widget _buildGlassButton({
    required Widget child,
    required VoidCallback onTap,
    Color? badgeColor,
  }) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: isDark ? Colors.black.withAlpha(50) : corPrimaria.withAlpha(20),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isDark ? corCardEscuro : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? Colors.white.withAlpha(12) : Colors.white,
                  width: 2,
                ),
              ),
              child: Center(child: child),
            ),
          ),
          if (badgeColor != null)
            Positioned(
              right: 2,
              top: 2,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: isDark ? corCardEscuro : Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    final double topOffset = MediaQuery.of(context).padding.top + 10;
    final bool podeAnunciar = _perfilAtual.perfilCompleto &&
        _perfilAtual.tipoUsuario.toLowerCase() == 'proprietario';

    // altura aproximada que o card do local buscado ocupa na base da tela --
    // usada pra levantar o FAB de localizacao e o botao de anunciar
    final double alturaCardLocal = _mostrandoCardLocal ? 152 : 0;

    return Stack(
      children: [
        GoogleMap(
          onMapCreated: _onMapCreated,
          initialCameraPosition: CameraPosition(target: posicaoInatel, zoom: 15.0),
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          markers: {
            ..._marcadores,
            ..._marcadoresRota,
            ?_destaquePoiBusca,
          },
          polylines: {..._rotas, ..._destaqueRuaBusca, ..._destaqueAreaBusca},
          mapType: _modoMapaAtual == 'Satélite' ? MapType.satellite : MapType.normal,
          style: _estiloAtivo,
        ),

        Positioned(
          top: topOffset,
          left: 16,
          right: 16,
          child: FadeTransition(
            opacity: _fadeAnim,
            child: SlideTransition(
              position: _slideAnim,
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
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDark ? corCardEscuro : Colors.white,
                            borderRadius: BorderRadius.circular(30),
                            border: Border.all(
                              color: isDark ? Colors.white.withAlpha(12) : Colors.white,
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: isDark ? Colors.black.withAlpha(50) : corPrimaria.withAlpha(20),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _buscaController,
                            focusNode: _buscaFocusNode,
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
                              prefixIcon: const Icon(Icons.search_rounded, color: corPrimaria, size: 22),
                              suffixIcon: _buscaComTexto
                                  ? IconButton(
                                icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 20),
                                onPressed: () => _buscaController.clear(),
                              )
                                  : IconButton(
                                icon: Badge(
                                  isLabelVisible: _filtroState.temFiltrosAtivos,
                                  smallSize: 8,
                                  backgroundColor: corPrimaria,
                                  child: const Icon(Icons.tune_rounded, color: corPrimaria, size: 22),
                                ),
                                onPressed: _mostrarFiltros,
                              ),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _buildGlassButton(
                        child: Icon(Icons.settings_rounded, color: isDark ? Colors.white : Colors.black87, size: 22),
                        onTap: _mostrarConfiguracoes,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildSeletorCidadeGlobal(isDark),

                  if (_sugestoes.isNotEmpty && _buscaFocusNode.hasFocus)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      constraints: const BoxConstraints(maxHeight: 260),
                      decoration: BoxDecoration(
                        color: isDark ? corCardEscuro : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withAlpha(isDark ? 60 : 15), blurRadius: 16, offset: const Offset(0, 6)),
                        ],
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _sugestoes.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1, indent: 56,
                          color: isDark ? Colors.white.withAlpha(10) : Colors.grey.withAlpha(20),
                        ),
                        itemBuilder: (context, index) {
                          final sugestao = _sugestoes[index];
                          final IconData icone = switch (sugestao.tipo) {
                            TipoSugestao.cidade => Icons.location_city_rounded,
                            TipoSugestao.faculdade => Icons.school_rounded,
                            TipoSugestao.moradia => Icons.home_rounded,
                            TipoSugestao.endereco => Icons.signpost_outlined,
                          };
                          return ListTile(
                            leading: Icon(icone, color: corPrimaria),
                            title: Text(
                              sugestao.texto,
                              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
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

        // cartao com a distancia/duracao da rota pedida na tela de detalhes,
        // ou um spinner enquanto ela ainda ta sendo calculada
        if (_carregandoRota || _rotaAtual != null)
          Positioned(
            top: topOffset + 68,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? corCardEscuro : Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(color: Colors.black.withAlpha(isDark ? 60 : 15), blurRadius: 16, offset: const Offset(0, 6)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_rotaAtual != null) ...[
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

        // card do local buscado + botao de tracar rota ate ele
        if (_mostrandoCardLocal)
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: _cardLocalBuscado(isDark),
          ),

        // botao pra focar na localizacao do usuario
        Positioned(
          // sobe se o botao de anunciar estiver visivel, e mais ainda se o
          // card do local buscado estiver ocupando a base da tela
          bottom: alturaCardLocal + (podeAnunciar ? 84 : 20),
          right: 16,
          child: FloatingActionButton(
            heroTag: 'btnLocation',
            mini: true,
            backgroundColor: isDark ? corCardEscuro : Colors.white,
            onPressed: _obterLocalizacaoReal,
            child: Icon(Icons.my_location_rounded, color: isDark ? Colors.white : Colors.black87),
          ),
        ),

        if (podeAnunciar)
          Positioned(
            bottom: alturaCardLocal + 20,
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

  const _PerfilPreview({required this.perfil, required this.onConcluirPerfil, required this.onSair});

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