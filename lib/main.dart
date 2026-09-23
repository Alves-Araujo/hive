import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// imports do firebase
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'models/notificacao.dart';
import 'models/passo_guia.dart';
import 'models/usuario.dart';
import 'screens/auth_gate.dart';
import 'screens/map_screen.dart';
import 'screens/notificacoes_screen.dart';
import 'screens/painel_screen.dart';
import 'screens/resumo_screen.dart';
import 'screens/chat_list_screen.dart';
import 'services/notificacao_service.dart';
import 'services/rota_service.dart';
import 'utils/alvos_tutorial.dart';
import 'utils/cor_foto.dart';
import 'utils/observador_rotas.dart';
import 'utils/passos_guia.dart';
import 'utils/tutorial_visto.dart';
import 'widgets/guia_interativo.dart';
import 'widgets/map_glass_surface.dart';
import 'widgets/abas_persistentes.dart';

// true enquanto o modo "Ir" esta ativo. A barra de navegacao inferior some
// nesse estado: navegacao e um modo que toma a tela, e trocar de aba no meio
// do percurso nao faz sentido -- a barra so rouba altura util do mapa
final ValueNotifier<bool> navegandoGlobal = ValueNotifier(false);

// controle do tema do app inteiro
final ValueNotifier<ThemeMode> temaGlobal = ValueNotifier(ThemeMode.system);

// perfil recem-salvo na tela de "concluir perfil".
//
// Quem abre aquela tela e o mapa, mas quem precisa saber do resultado e a
// TelaPrincipal: e ela que monta a barra de abas (a aba "Imóveis" so existe
// pra quem anuncia) e que roda a segunda parte do guia, que so faz sentido
// depois do tipo de conta escolhido
final ValueNotifier<Usuario?> perfilAtualizadoGlobal = ValueNotifier(null);

// pedido de rodar o guia de novo, vindo do "Ver tutorial" do perfil. Mesma
// divisao de tarefas: o mapa pede, a TelaPrincipal roda -- o guia acende os
// botoes da barra de abas e troca de aba, e quem manda nisso e ela
final ValueNotifier<PedidoDeGuia?> pedidoDeGuiaGlobal = ValueNotifier(null);


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

// o roxo "cheio" do evento, pro que e detalhe e nao superficie (icone de
// endereco, pilula de tag): nesses lugares o azul da marca aparecia no meio
// da ficha roxa como se fosse outro assunto
const corEvento = Color(0xFF6D3FA8);

// Superficies da ficha de EVENTO -- a mesma escada da familia azul
// (corFundoEscuro / corCardEscuro), so que na familia roxa. A ficha de evento
// abria azul-escura enquanto o pin, o cabecalho e o botao ja eram roxos: o
// fundo era a unica peca da tela falando outra lingua.
//
// Vale SO pra tela de detalhes de evento. O resto do app continua azul --
// evento e uma categoria dentro dele, nao um tema paralelo
const corSuperficieEventoEscura = Color(0xFF241733);
const corSuperficieEventoClara = Color(0xFFF3EEFA);

// um degrau acima de cada uma: card apoiado sobre a folha roxa
const corCardEventoEscura = Color(0xFF2F2145);
const corCardEventoClara = Color(0xFFE9DFF7);

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
    // o que o tutorial ja mostrou neste aparelho. Tambem antes da primeira
    // tela: a AuthGate escolhe entre boas-vindas e login ja no primeiro build
    iniciarTutorial(),
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
          title: 'Hive',
          debugShowCheckedModeBanner: false,
          // avisa o guia interativo quando uma folha ou tela sobe por cima do
          // app, pra ele sair da frente e voltar quando ela fechar
          navigatorObservers: [observadorDeRotas],
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

class _TelaPrincipalState extends State<TelaPrincipal> {
  int _indiceAtual = 0;
  late Usuario _perfil = widget.perfil;
  late final List<Widget> _telas;
  late final List<_ItemNav> _itensNav;
  late VoidCallback _rotaPendenteListener;

  // passos em andamento do guia interativo; nulo quando ele nao esta rodando
  List<PassoGuia>? _passosDoGuia;
  // qual das duas partes esta rodando, pra saber o que marcar como visto
  bool _guiaEhOPrimeiro = false;

  // painel de imoveis so aparece pra quem pode anunciar (proprietario/corretor)
  bool get _temPainel =>
      _perfil.tipoUsuario == 'proprietario' || _perfil.tipoUsuario == 'corretor';

  @override
  void initState() {
    super.initState();
    _telas = [
      CentroDoMapa(perfil: _perfil),
      TelaResumo(perfil: _perfil),
      const TelaListaChats(),
      if (_temPainel) PainelScreen(perfil: _perfil),
    ];
    // ordem das abas mantida (Mapa, Resumo, Chat, Painel); apenas o icone da
    // aba Resumo e o da aba Painel foram trocados entre si
    _itensNav = [
      const _ItemNav(icon: Icons.map_outlined, activeIcon: Icons.map_rounded, label: 'Mapa', alvo: AlvoTutorial.abaMapa),
      const _ItemNav(icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard_rounded, label: 'Resumo', alvo: AlvoTutorial.abaResumo),
      const _ItemNav(icon: Icons.chat_bubble_outline_rounded, activeIcon: Icons.chat_bubble_rounded, label: 'Chat', alvo: AlvoTutorial.abaChat),
      if (_temPainel)
        const _ItemNav(icon: Icons.home_outlined, activeIcon: Icons.home_rounded, label: 'Imóveis', alvo: AlvoTutorial.abaImoveis),
    ];

    perfilAtualizadoGlobal.addListener(_aoAtualizarPerfil);
    pedidoDeGuiaGlobal.addListener(_aoPedirGuia);

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

    NotificacaoService.instance.iniciar(_perfil.uid);
    NotificacaoService.instance.ultimaRecebida.addListener(_mostrarAvisoRecebido);

    _rodarGuiaSeForAHora();
  }

  // O guia roda DUAS vezes na vida de uma conta:
  //
  // 1) primeiro acesso, com o cadastro ainda incompleto -- so o que ja
  //    funciona, terminando no caminho pra concluir o perfil;
  // 2) quando o cadastro e concluido -- o que abriu, conforme o tipo de conta.
  //
  // Quem entra com o cadastro ja pronto (conta antiga, ou celular novo) cai
  // direto na segunda parte: a primeira so falaria de coisas que essa pessoa
  // ja passou
  void _rodarGuiaSeForAHora() {
    // depois do primeiro frame: o guia mede onde os botoes estao, e antes do
    // primeiro desenho nao existe posicao nenhuma pra medir
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _passosDoGuia != null) return;

      if (!_perfil.perfilCompleto) {
        if (!viuGuiaInicial) {
          _iniciarGuia(passosPrimeiroAcesso, ehOPrimeiro: true);
        }
        return;
      }

      if (!viuGuiaDoPerfil(chaveGuiaDoPerfil(_perfil))) {
        _iniciarGuia(passosDoPerfil(_perfil), ehOPrimeiro: false);
      }
    });
  }

  void _iniciarGuia(List<PassoGuia> passos, {required bool ehOPrimeiro}) {
    if (passos.isEmpty) return;
    setState(() {
      _passosDoGuia = passos;
      _guiaEhOPrimeiro = ehOPrimeiro;
    });
  }

  // vale tanto pra quem chegou ao fim quanto pra quem saiu no meio: quem
  // desistiu de um guia nao quer encontrar ele de novo no proximo login
  void _encerrarGuia() {
    if (_guiaEhOPrimeiro) {
      marcarGuiaInicialVisto();
    } else {
      marcarGuiaDoPerfilVisto(chaveGuiaDoPerfil(_perfil));
    }
    setState(() => _passosDoGuia = null);
  }

  // perfil salvo na tela de "concluir perfil" (ver perfilAtualizadoGlobal).
  // Alem de rodar a segunda parte do guia, e aqui que a aba "Imóveis" nasce
  // pra quem acabou de virar proprietario ou corretor -- antes ela so
  // aparecia na proxima vez que o app abria
  void _aoAtualizarPerfil() {
    final novo = perfilAtualizadoGlobal.value;
    if (novo == null || !mounted) return;
    perfilAtualizadoGlobal.value = null;

    final bool ganhouPainel = !_temPainel &&
        (novo.tipoUsuario == 'proprietario' || novo.tipoUsuario == 'corretor');

    setState(() {
      _perfil = novo;
      // o mapa e o chat continuam sendo as MESMAS instancias: recriar o mapa
      // recarrega a platform view e refaz as assinaturas dele
      _telas[1] = TelaResumo(perfil: novo);
      if (ganhouPainel) {
        _telas.add(PainelScreen(perfil: novo));
        _itensNav.add(const _ItemNav(
          icon: Icons.home_outlined,
          activeIcon: Icons.home_rounded,
          label: 'Imóveis',
          alvo: AlvoTutorial.abaImoveis,
        ));
      }
    });

    // A primeira parte do guia termina mandando concluir o cadastro. Quem
    // obedeceu na hora volta com ela ainda aberta por baixo -- e, enquanto
    // estiver aberta, a segunda parte nao comeca. Ela ja cumpriu o papel:
    // sai de cena (marcada como vista) e da lugar a segunda
    if (_passosDoGuia != null && _guiaEhOPrimeiro && novo.perfilCompleto) {
      _encerrarGuia();
    }

    _rodarGuiaSeForAHora();
  }

  void _aoPedirGuia() {
    final pedido = pedidoDeGuiaGlobal.value;
    if (pedido == null || !mounted) return;
    pedidoDeGuiaGlobal.value = null;

    setState(() => _indiceAtual = 0);
    _iniciarGuia(
      pedido.perfil.perfilCompleto
          ? passosDoPerfil(
              pedido.perfil,
              ehContaDaImobiliaria: pedido.ehContaDaImobiliaria,
            )
          : passosPrimeiroAcesso,
      ehOPrimeiro: !pedido.perfil.perfilCompleto,
    );
  }

  @override
  void dispose() {
    rotaCarregandoGlobal.removeListener(_rotaPendenteListener);
    perfilAtualizadoGlobal.removeListener(_aoAtualizarPerfil);
    pedidoDeGuiaGlobal.removeListener(_aoPedirGuia);
    NotificacaoService.instance.ultimaRecebida.removeListener(_mostrarAvisoRecebido);
    NotificacaoService.instance.parar();
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
    final passosDoGuia = _passosDoGuia;

    // o guia fica FORA do Scaffold, num Stack por cima dele: ele precisa
    // escurecer (e destravar com o furo) tambem a barra de abas, que nao mora
    // dentro do body
    return Stack(
      children: [
        _appPrincipal(isDark),
        if (passosDoGuia != null)
          Positioned.fill(
            child: GuiaInterativo(
              // a chave troca junto com o conjunto de passos: trocar de guia
              // sem reiniciar deixaria o contador no passo antigo
              key: ValueKey(passosDoGuia),
              passos: passosDoGuia,
              onTrocarAba: (indice) {
                if (indice < _telas.length && indice != _indiceAtual) {
                  setState(() => _indiceAtual = indice);
                }
              },
              onConcluir: _encerrarGuia,
            ),
          ),
      ],
    );
  }

  Widget _appPrincipal(bool isDark) {
    return Scaffold(
      // deixa o body passar POR BAIXO da barra inferior. Sem isso a barra
      // ocupa um slot proprio abaixo do body, e atras dos cantos arredondados
      // dela aparecia o backgroundColor do Scaffold em vez do mapa -- dava a
      // leitura de "forma redonda dentro de um quadrado" branco.
      // O mapa compensa com padding no rodape (le a altura real da barra pelo
      // padding.bottom do MediaQuery) pra o logo do Google nao ficar escondido
      extendBody: true,
      // Mantem a instancia do mapa entre abas. Recriar a platform view a
      // cada toque fazia o mapa recarregar e repetia suas assinaturas.
      body: AbasPersistentes(indice: _indiceAtual, telas: _telas),
      bottomNavigationBar: ValueListenableBuilder<bool>(
        valueListenable: navegandoGlobal,
        builder: (_, navegando, barra) =>
            navegando ? const SizedBox.shrink() : barra!,
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: MapGlassSurface(
            radius: 32,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                for (var i = 0; i < _itensNav.length; i++)
                  _buildNavItemEmpilhado(
                    i, _itensNav[i].icon, _itensNav[i].activeIcon,
                    _itensNav[i].label, _itensNav[i].alvo, isDark,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Pilula azul apenas no icone; rotulos e indicador mantem a aba legivel.
  Widget _buildNavItemEmpilhado(
      int index, IconData icon, IconData activeIcon, String label,
      AlvoTutorial alvo, bool isDark) {
    final bool isSelected = _indiceAtual == index;
    const Color corPilula = corPrimaria;
    final Color corAtiva = isDark ? const Color(0xFF3399FF) : corPrimaria;
    final Color corInativa = isDark
        ? const Color(0xFFA6BBD3)
        : const Color(0xFF5A7085);

    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_indiceAtual != index) setState(() => _indiceAtual = index);
        },
        behavior: HitTestBehavior.opaque,
        child: Column(
          // e por esta chave que o guia interativo sabe onde esta a aba pra
          // abrir o furo em cima dela (ver utils/alvos_tutorial.dart)
          key: chaveAlvo(alvo),
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 72,
              height: 38,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // A pilula e sua sombra ficam prontas numa camada propria.
                  // Anima apenas alpha: interpolar BoxShadow alterava raio e
                  // tamanho do brilho a cada frame, dando o efeito de encolher.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedOpacity(
                        opacity: isSelected ? 1 : 0,
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 120),
                        curve: Curves.easeOutCubic,
                        child: RepaintBoundary(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [corPrimaria2, corPrimaria],
                              ),
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: const Color(0xFF329CFF),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: corPrimaria2.withAlpha(isDark ? 100 : 48),
                                  blurRadius: 14,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Icon(
                    isSelected ? activeIcon : icon,
                    color: isSelected ? Colors.white : corInativa,
                    size: 23,
                  ),
                  // notificacoes gerais (moradia, evento, imobiliaria,
                  // avaliacao) vivem no avatar de perfil, que fica no Mapa --
                  // o ponto aqui avisa quem esta no Resumo, Chat ou Painel
                  // que tem novidade pra ver lá
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
                  // mensagem nova mora so aqui: some assim que a conversa dela
                  // e aberta, nao quando a pessoa so olha as notificacoes
                  if (index == 2)
                    Positioned(
                      top: 5,
                      right: 14,
                      child: ValueListenableBuilder<int>(
                        valueListenable: NotificacaoService.instance.mensagensNaoLidas,
                        builder: (_, mensagensNaoLidas, _) => mensagensNaoLidas == 0
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
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.label.copyWith(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? corAtiva : corInativa,
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
  // ponto que o guia interativo acende quando fala desta aba
  final AlvoTutorial alvo;
  const _ItemNav({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.alvo,
  });
}