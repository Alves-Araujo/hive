import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// imports do firebase
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'models/notificacao.dart';
import 'models/usuario.dart';
import 'screens/auth_gate.dart';
import 'screens/map_screen.dart';
import 'screens/notificacoes_screen.dart';
import 'screens/painel_screen.dart';
import 'screens/resumo_screen.dart';
import 'screens/chat_list_screen.dart';
import 'services/notificacao_service.dart';
import 'services/rota_service.dart';
import 'utils/cor_foto.dart';

// true enquanto o modo "Ir" esta ativo. A barra de navegacao inferior some
// nesse estado: navegacao e um modo que toma a tela, e trocar de aba no meio
// do percurso nao faz sentido -- a barra so rouba altura util do mapa
final ValueNotifier<bool> navegandoGlobal = ValueNotifier(false);

// controle do tema do app inteiro
final ValueNotifier<ThemeMode> temaGlobal = ValueNotifier(ThemeMode.system);


// posicao do inatel, usada como centro padrao do mapa e destino da rota --
// coordenada conferida na base do OpenStreetMap (o valor antigo era uma
// estimativa que caia fora do campus, ver busca_service.dart)
const LatLng posicaoInatel = LatLng(-22.2573047, -45.6958702);

// chave usada pra chamar a Directions API (calculo de rota) -- essa e a
// chave do app Android no Firebase (mesmo projeto moradias-inatel, ver
// firebase_options.dart), que e onde o billing foi habilitado. E diferente
// da chave que fica no AndroidManifest.xml (essa outra so serve pro SDK do
// mapa desenhar os tiles, nao precisa mudar)
const String googleMapsApiKey = 'AIzaSyDL0aaR1gdW-x3oiH4gxZVNMozISryp5CI';

// credenciais do ZegoCloud (chamadas de voz/video no chat)
const int zegoAppId = 969417110;
const String zegoAppSign = '158812f25b867a6135e44b4fe1c3ea5eda22dcbd7bd1b7cd4a073a66d980d167';

// cores principais
const corPrimaria = Color(0xFF00509E);
const corPrimaria2 = Color(0xFF007BFF);
const corDestaque = Color(0xFF00C6FF);

// Fundos e superficies -- UMA familia so, azulada, a mesma do mapa.
//
// Estes quatro nomes vem da primeira versao do app e eram roxo-pretos
// (#0A0A10, #16161F, #1E1E2A) e um branco lilas (#FAFAFE). Quando o mapa
// ganhou a paleta azul, o app passou a ter DUAS paletas escuras ao mesmo
// tempo: a tela de anuncio abria roxo-preta, o mapa azul-escuro, e a
// diferenca aparecia na troca de aba. Em vez de caçar as dezenas de usos um
// por um, os nomes antigos foram remendados pra dentro da familia azul --
// quem ja usava continua funcionando, agora na cor certa.
//
// A escada, do mais escuro pro mais claro: fundo de pagina, superficie
// padrao (= superficieEscura), superficie elevada (card sobre a pagina).
const corFundoEscuro = Color(0xFF0E1621);
const corCardEscuro = Color(0xFF16222E);
const corSuperficieEscura = Color(0xFF1B2A38);

// mesma ideia no claro: fundo de pagina um degrau acima da superficie
const corFundoClaro = Color(0xFFF7FAFD);

// superficies do vidro -- deliberadamente NAO sao branco puro nem cinza
// neutro: sobre o mapa (tons off-white/bege no claro, azulado no escuro) uma
// peca branca pura fica mais clara que tudo em volta e destoa. Estes tons
// frios acompanham o mapa e o azul do app
const superficieClara = Color(0xFFEFF3F8);
const superficieEscura = Color(0xFF16222E);

// cores pra feedback (sucesso, aviso, erro)
const corSucesso = Color(0xFF10B981);
const corAtencao = Color(0xFFF59E0B);
const corErro = Color(0xFFEF4444);

// gradientes usados nos botoes e cards
// gradiente da marca. UNICO -- antes existiam dois concorrentes: este, que
// ia de azul a ciano (#00B4DB), e um "gradientePrincipal" criado depois pro botao
// de rota porque o primeiro ficava berrante sobre a tela clara. Dois
// gradientes de marca e o caminho pra tela nenhuma combinar com a outra,
// entao o azul escuro virou o unico e os ~16 usos espalhados seguem ele.
const gradientePrincipal = LinearGradient(
  colors: [Color(0xFF12294A), Color(0xFF17456F), Color(0xFF1C5A8F)],
  begin: Alignment.centerLeft,
  end: Alignment.centerRight,
);

// gradiente de DESTAQUE DE PRECO -- e a unica coisa pra que ele serve.
//
// A regra que mantem o app coerente: gradientePrincipal em marca e acao
// (botoes, selos de icone, estado selecionado); gradienteSecundario SO em
// preco (cartao do resumo, ficha do imovel, badge do filtro). O ciano so
// funciona como destaque justamente por ser a unica cor viva da tela -- usar
// em botao, como estava no "ligar" do perfil publico, gasta esse contraste e
// faz o preco deixar de saltar.
const gradienteSecundario = LinearGradient(
  colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

// identidade dos EVENTOS -- as mesmas duas cores do pin de evento no mapa
// (ver TipoPin.evento em utils/pins_mapa.dart).
//
// Era ambar->vermelho enquanto o pin ja tinha virado roxo: o evento aparecia
// roxo no mapa e abria laranja na ficha, como se fossem dois assuntos. Se um
// dia a cor do evento mudar, tem que mudar NOS DOIS lugares.
const gradienteEvento = LinearGradient(
  colors: [Color(0xFF6D3FA8), Color(0xFF2F1A52)],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

// estilos de texto padronizados pra manter consistencia
class AppTextStyles {
  static const heading1 = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w800,
    letterSpacing: -1.2,
    height: 1.2,
  );

  static const heading2 = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.8,
    height: 1.3,
  );

  static const heading3 = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
    height: 1.3,
  );

  static const body = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    letterSpacing: 0,
    height: 1.5,
  );

  static const bodyBold = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.5,
  );

  static const caption = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
    height: 1.4,
  );

  static const captionBold = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    height: 1.4,
  );

  static const label = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
    height: 1.3,
  );
}


// escala de espacamento -- o app espalhava 6/8/12/14/16/20/24 quase na sorte,
// e espacamento irregular e o que mais faz um layout parecer improvisado
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}

// raios padronizados -- antes tinha 10, 12, 14, 16, 18, 20 e 24 misturados
// sem criterio, o que faz os cantos parecerem inconsistentes de perto
class AppRadius {
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;
}

// sombras em CAMADAS: uma curta e fechada pro contato com a superficie, mais
// uma longa e difusa pra sensacao de altura. O app usava uma sombra unica em
// tudo, e e justamente isso que achata os elementos e da a cara de "forma
// simples" -- objeto real projeta as duas ao mesmo tempo
class AppShadows {
  // repousando na superficie (chips, campos, botoes pequenos)
  static List<BoxShadow> nivel1(bool isDark) => [
        BoxShadow(
          color: Colors.black.withAlpha(isDark ? 70 : 10),
          blurRadius: 2,
          offset: const Offset(0, 1),
        ),
        BoxShadow(
          color: Colors.black.withAlpha(isDark ? 50 : 12),
          blurRadius: 8,
          offset: const Offset(0, 3),
        ),
      ];

  // flutuando (cards, paineis, barra de busca)
  static List<BoxShadow> nivel2(bool isDark) => [
        BoxShadow(
          color: Colors.black.withAlpha(isDark ? 80 : 12),
          blurRadius: 3,
          offset: const Offset(0, 1),
        ),
        BoxShadow(
          color: Colors.black.withAlpha(isDark ? 60 : 16),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];

  // acima de tudo (folhas, dialogos, FAB ativo)
  static List<BoxShadow> nivel3(bool isDark) => [
        BoxShadow(
          color: Colors.black.withAlpha(isDark ? 90 : 14),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
        BoxShadow(
          color: Colors.black.withAlpha(isDark ? 70 : 22),
          blurRadius: 36,
          offset: const Offset(0, 16),
        ),
      ];

  // brilho colorido pra elemento com gradiente da marca -- sombra preta em
  // cima de gradiente azul suja a cor; a sombra tingida mantem viva
  static List<BoxShadow> marca({double forca = 1}) => [
        BoxShadow(
          color: corPrimaria.withAlpha((70 * forca).round()),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ];
}

// tempos e curvas unicos pro app -- movimento com duracao diferente em cada
// tela parece defeito; padronizado parece intencional
class AppMotion {
  static const Duration rapida = Duration(milliseconds: 150);
  static const Duration media = Duration(milliseconds: 260);
  static const Duration lenta = Duration(milliseconds: 420);

  static const Curve suave = Curves.easeOutCubic;
  static const Curve saida = Curves.easeInCubic;
  // leve overshoot -- usar so em entrada de elemento, nunca em cor/tamanho
  // de algo que o dedo esta tocando (da sensacao de imprecisao)
  static const Curve entrada = Curves.easeOutBack;
}

// inicializa o firebase antes de rodar o app
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Future.wait([
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
    // cores salvas do anel do avatar -- carregadas antes da primeira tela
    // pra o anel ja abrir com a cor da foto
    iniciarCorFoto(),
  ]);

  // tela cheia: esconde a barra de status e a de navegacao do sistema.
  // "sticky" faz elas reaparecerem temporariamente ao deslizar da borda e
  // sumirem sozinhas depois, em vez de ficarem presas na tela
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  _ouvirPedidosDeRota();

  runApp(const MeuAppEstudantil());
}

// escuta em nivel de app (nao preso a nenhuma tela) os pedidos de rota
// feitos na tela de detalhes -- assim o calculo continua ate o fim mesmo se
// o usuario trocar de aba enquanto ele roda (ver comentario em rotaAtivaGlobal)
void _ouvirPedidosDeRota() {
  rotaPendenteGlobal.addListener(() {
    final pendente = rotaPendenteGlobal.value;
    if (pendente != null) {
      rotaPendenteGlobal.value = null;
      processarPedidoDeRota(pendente, googleMapsApiKey);
    }
  });
}

class MeuAppEstudantil extends StatelessWidget {
  const MeuAppEstudantil({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: temaGlobal,
      builder: (context, currentMode, _) {
        // ajustar status bar conforme o tema
        final isDark = currentMode == ThemeMode.dark ||
            (currentMode == ThemeMode.system &&
                MediaQuery.platformBrightnessOf(context) == Brightness.dark);

        SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: isDark ? corCardEscuro : Colors.white,
        ));

        return MaterialApp(
          title: 'Hive Moradias',
          debugShowCheckedModeBanner: false,
          locale: const Locale('pt', 'BR'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('pt', 'BR')],
          themeMode: currentMode,
          theme: ThemeData(
            brightness: Brightness.light,
            colorSchemeSeed: corPrimaria,
            useMaterial3: true,
            scaffoldBackgroundColor: corFundoClaro,
            textTheme: GoogleFonts.interTextTheme(),
            splashColor: corPrimaria.withAlpha(20),
            highlightColor: corPrimaria.withAlpha(10),
            dividerTheme: DividerThemeData(
              color: Colors.grey.withAlpha(25),
              thickness: 1,
            ),
            chipTheme: ChipThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Colors.transparent),
              ),
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            colorSchemeSeed: corPrimaria,
            useMaterial3: true,
            scaffoldBackgroundColor: corFundoEscuro,
            textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
            splashColor: corPrimaria.withAlpha(25),
            highlightColor: corPrimaria.withAlpha(15),
            dividerTheme: DividerThemeData(
              color: Colors.white.withAlpha(12),
              thickness: 1,
            ),
            chipTheme: ChipThemeData(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Colors.transparent),
              ),
            ),
          ),
          home: const AuthGate(),
        );
      },
    );
  }
}

class TelaPrincipal extends StatefulWidget {
  final Usuario perfil;
  const TelaPrincipal({super.key, required this.perfil});

  @override
  State<TelaPrincipal> createState() => _TelaPrincipalState();
}

class _TelaPrincipalState extends State<TelaPrincipal>
    with SingleTickerProviderStateMixin {
  int _indiceAtual = 0;
  late final List<Widget> _telas;
  late final List<_ItemNav> _itensNav;
  late AnimationController _navAnimController;
  late VoidCallback _rotaPendenteListener;

  // painel de imoveis so aparece pra quem pode anunciar (proprietario/corretor)
  bool get _temPainel =>
      widget.perfil.tipoUsuario == 'proprietario' || widget.perfil.tipoUsuario == 'corretor';

  @override
  void initState() {
    super.initState();
    _telas = [
      CentroDoMapa(perfil: widget.perfil),
      TelaResumo(perfil: widget.perfil),
      const TelaListaChats(),
      if (_temPainel) PainelScreen(perfil: widget.perfil),
    ];
    // ordem das abas mantida (Mapa, Resumo, Chat, Painel); apenas o icone da
    // aba Resumo e o da aba Painel foram trocados entre si
    _itensNav = [
      const _ItemNav(icon: Icons.map_outlined, activeIcon: Icons.map_rounded, label: 'Mapa'),
      const _ItemNav(icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard_rounded, label: 'Resumo'),
      const _ItemNav(icon: Icons.chat_bubble_outline_rounded, activeIcon: Icons.chat_bubble_rounded, label: 'Chat'),
      if (_temPainel)
        const _ItemNav(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Imóveis'),
    ];
    _navAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _navAnimController.forward();

    // a tela de detalhes pode ter sido aberta a partir da aba Resumo, mas a
    // rota so eh desenhada no mapa -- escuta rotaCarregandoGlobal (nao
    // rotaPendenteGlobal direto, que ja e consumido/zerado pelo listener de
    // app em _ouvirPedidosDeRota antes desse aqui rodar) e troca pra aba do
    // Mapa assim que uma busca de rota comeca
    _rotaPendenteListener = () {
      if (rotaCarregandoGlobal.value && mounted && _indiceAtual != 0) {
        setState(() => _indiceAtual = 0);
      }
    };
    rotaCarregandoGlobal.addListener(_rotaPendenteListener);

    NotificacaoService.instance.iniciar(widget.perfil.uid);
    NotificacaoService.instance.ultimaRecebida.addListener(_mostrarAvisoRecebido);
  }

  @override
  void dispose() {
    rotaCarregandoGlobal.removeListener(_rotaPendenteListener);
    NotificacaoService.instance.ultimaRecebida.removeListener(_mostrarAvisoRecebido);
    NotificacaoService.instance.parar();
    _navAnimController.dispose();
    super.dispose();
  }

  // aviso flutuante pra notificacao que chega com o app aberto -- aparece
  // por cima de qualquer tela, porque o ScaffoldMessenger e o do app todo
  void _mostrarAvisoRecebido() {
    final n = NotificacaoService.instance.ultimaRecebida.value;
    if (n == null || !mounted || navegandoGlobal.value) return;
    if (n.tipo == TipoNotificacao.novaMensagem && n.alvoId == NotificacaoService.instance.chatAberto) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF14304F),
        duration: const Duration(seconds: 5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
        content: Row(
          children: [
            Icon(iconeNotificacao(n.tipo), color: Colors.white, size: 20),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                  if (n.corpo.isNotEmpty)
                    Text(
                      n.corpo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white.withAlpha(190), fontSize: 13),
                    ),
                ],
              ),
            ),
          ],
        ),
        action: SnackBarAction(
          label: 'Ver',
          textColor: corDestaque,
          onPressed: () => abrirNotificacao(context, n),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      // deixa o body passar POR BAIXO da barra inferior. Sem isso a barra
      // ocupa um slot proprio abaixo do body, e atras dos cantos arredondados
      // dela aparecia o backgroundColor do Scaffold em vez do mapa -- dava a
      // leitura de "forma redonda dentro de um quadrado" branco.
      // O mapa compensa com padding no rodape (le a altura real da barra pelo
      // padding.bottom do MediaQuery) pra o logo do Google nao ficar escondido
      extendBody: true,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: IndexedStack(
          key: ValueKey(_indiceAtual),
          index: _indiceAtual,
          children: _telas,
        ),
      ),
      // sombra pra CIMA (offset negativo) fica no DecoratedBox de fora, porque
      // o ClipRect de dentro cortaria ela -- e sem essa sombra a barra de
      // vidro cola no conteudo e perde a leitura de estar por cima
      // isola a camada da barra tambem -- ela nao muda durante o arraste
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: navegandoGlobal,
        builder: (_, navegando, barra) =>
            navegando ? const SizedBox.shrink() : barra!,
        child: RepaintBoundary(
        child: DecoratedBox(
        decoration: BoxDecoration(
          // o raio TAMBEM aqui, nao so no ClipRRect: sem ele a sombra e
          // lancada de um retangulo e aparece como um canto quadrado atras da
          // quina arredondada, que era metade do efeito de "redondo dentro de
          // quadrado". Sombra tem que seguir a forma da peca
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 60 : 20),
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        // cantos de cima arredondados, igual a referencia -- e o que faz a
        // barra ler como painel apoiado sobre o mapa, nao como rodape colado
        child: ClipRRect(
          // 24 em vez de 28: menos redondo, como pedido, sem ficar quadrado
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          // sem BackdropFilter: sobre o GoogleMap (platform view) mesmo UM
          // filtro estoura o orcamento de frame -- a tabela de medicoes esta
          // no glass_card.dart. O vidro aqui e feito de pintura
          child: DecoratedBox(
              decoration: BoxDecoration(
                // quase opaca: sem blur, preenchimento fraco deixava os rotulos
                // do mapa atravessando e colidindo com "Resumo" e "Chat"
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.55, 1],
                  colors: isDark
                      ? [
                          // tom azulado e mais claro que a base do mapa
                          // escuro (#0f1620) -- com corCardEscuro (#16161F) a
                          // luminancia era quase igual a do mapa e a barra se
                          // dissolvia no fundo, sem separacao nenhuma
                          Color.alphaBlend(Colors.white.withAlpha(26), superficieEscura.withAlpha(248)),
                          superficieEscura.withAlpha(246),
                          Color.alphaBlend(corPrimaria.withAlpha(24), superficieEscura.withAlpha(248)),
                        ]
                      : [
                          // NAO branco puro: sobre o mapa (off-white e bege) a
                          // barra branca ficava mais clara que tudo e nao ornava
                          superficieClara.withAlpha(250),
                          superficieClara.withAlpha(244),
                          Color.alphaBlend(corPrimaria.withAlpha(16), superficieClara.withAlpha(247)),
                        ],
                ),
                border: Border(
                  // era alpha 252 com 1.4 de largura, ou seja, uma linha
                  // branca solida atravessando o topo da barra. Reduzido pra
                  // so separar a barra do mapa sem desenhar contorno
                  top: BorderSide(
                    color: isDark ? Colors.white.withAlpha(18) : Colors.white.withAlpha(52),
                    width: 1,
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: AppSpacing.sm,
                    right: AppSpacing.sm,
                    top: AppSpacing.md,
                    bottom: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      for (var i = 0; i < _itensNav.length; i++)
                        _buildNavItemEmpilhado(
                            i, _itensNav[i].icon, _itensNav[i].activeIcon, _itensNav[i].label, isDark),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  // item no padrao da referencia: pilula escura SO atras do icone, e o rotulo
  // sempre visivel embaixo. Manter o rotulo em todas as abas (e nao so na
  // ativa) e o que deixa a barra legivel de primeira -- icone sozinho obriga
  // o usuario a adivinhar, e era isso que a barra antiga fazia
  Widget _buildNavItemEmpilhado(
      int index, IconData icon, IconData activeIcon, String label, bool isDark) {
    final bool isSelected = _indiceAtual == index;

    // no escuro a pilula era BRANCA com icone escuro -- invertia a leitura do
    // modo claro e perdia a identidade azul do app. Agora usa um azul da
    // marca claro o bastante pra funcionar sobre fundo escuro, e o icone
    // segue branco nos dois temas
    final Color corPilula = isDark ? const Color(0xFF1E5E96) : const Color(0xFF14304F);
    // o rotulo precisa de um azul mais claro que a pilula pra ser legivel
    // sobre o fundo escuro da barra
    final Color corAtiva = isDark ? const Color(0xFF8FBEE8) : const Color(0xFF14304F);
    final Color corInativa = isDark ? const Color(0xFF6B7A88) : const Color(0xFF8A9691);

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _indiceAtual = index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: AppMotion.media,
              curve: AppMotion.suave,
              width: 58,
              height: 34,
              decoration: BoxDecoration(
                color: isSelected ? corPilula : Colors.transparent,
                borderRadius: BorderRadius.circular(15),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: corPilula.withAlpha(70),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ]
                    : null,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: AppMotion.rapida,
                    child: Icon(
                      isSelected ? activeIcon : icon,
                      key: ValueKey(isSelected),
                      color: isSelected ? Colors.white : corInativa,
                      size: 21,
                    ),
                  ),
                  // notificacoes agora vivem no avatar de perfil, que fica no
                  // Mapa -- o ponto aqui avisa quem esta no Resumo, Chat ou
                  // Painel que tem novidade pra ver lá
                  if (index == 0)
                    Positioned(
                      top: 5,
                      right: 14,
                      child: ValueListenableBuilder<int>(
                        valueListenable: NotificacaoService.instance.naoLidas,
                        builder: (_, naoLidas, _) => naoLidas == 0
                            ? const SizedBox.shrink()
                            : Container(
                                width: 9,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: corErro,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? corPilula : (isDark ? superficieEscura : superficieClara),
                                    width: 1.5,
                                  ),
                                ),
                              ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs + 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.label.copyWith(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? corAtiva : corInativa,
              ),
            ),
            // pontinho embaixo do rotulo ativo, igual a referencia -- marca a
            // aba atual sem precisar engordar a pilula
            const SizedBox(height: AppSpacing.xs),
            AnimatedContainer(
              duration: AppMotion.media,
              curve: AppMotion.suave,
              width: isSelected ? 4 : 0,
              height: isSelected ? 4 : 0,
              decoration: BoxDecoration(
                color: corPilula,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemNav {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _ItemNav({required this.icon, required this.activeIcon, required this.label});
}