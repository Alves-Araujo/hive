import '../models/passo_guia.dart';
import '../models/usuario.dart';
import 'alvos_tutorial.dart';

// O guia roda DUAS vezes na vida de uma conta, e cada uma tem um recorte:
//
// 1) logo no primeiro login, com o cadastro ainda incompleto: so o que ja
//    funciona (mapa, busca, filtros, lista, caixa de entrada) e, no fim, o
//    caminho pra concluir o perfil. Ensinar a anunciar aqui seria mostrar um
//    botao que a pessoa nao tem.
//
// 2) quando o cadastro e concluido: o que acabou de abrir, conforme o tipo de
//    conta escolhido -- chat liberado, avaliacoes e, pra quem anuncia, o
//    painel e o botao de publicar.
//
// Os textos citam os rotulos de verdade da interface ("Anunciar", "Perto do
// imóvel", "Ir"). Mudou o rotulo de um botao, muda o passo junto.

// ---------------------------------------------------------------------------
// Parte 1: conta nova, perfil ainda incompleto
// ---------------------------------------------------------------------------
const List<PassoGuia> passosPrimeiroAcesso = [
  PassoGuia(
    titulo: 'Bem-vindo ao Hive',
    texto:
        'Aqui ficam as moradias, os eventos e as imobiliárias perto da sua '
        'faculdade. Vou mostrar onde fica cada coisa; é rápido e você pode '
        'sair quando quiser.',
  ),
  PassoGuia(
    titulo: 'O mapa é a tela principal',
    texto:
        'Cada pin é um anúncio: azul é moradia, roxo é evento. O mapa também '
        'mostra as imobiliárias e os lugares em volta, como mercado, farmácia '
        'e restaurante. Toque num pin para abrir a ficha.',
  ),
  PassoGuia(
    alvo: AlvoTutorial.busca,
    titulo: 'Procure um lugar',
    texto:
        'Digite uma cidade, faculdade, rua, bairro ou o nome de um anúncio. '
        'O mapa voa até lá e desenha o local.',
  ),
  PassoGuia(
    alvo: AlvoTutorial.filtros,
    titulo: 'Filtre a busca',
    texto:
        'Valor do aluguel, tipo de imóvel, características, contas inclusas e '
        'distância até a faculdade ou o mercado. Pode tocar e dar uma olhada: '
        'eu espero aqui.',
    abreOutraTela: true,
  ),
  PassoGuia(
    alvo: AlvoTutorial.configuracoes,
    titulo: 'Ajustes do mapa',
    texto:
        'Tema claro ou escuro, mapa normal ou satélite e a permissão de '
        'localização. Sair da conta também fica aqui.',
    abreOutraTela: true,
  ),
  PassoGuia(
    alvo: AlvoTutorial.minhaLocalizacao,
    titulo: 'Onde você está',
    texto:
        'Centraliza o mapa na sua posição. Se o ícone estiver cortado, é '
        'porque a localização ainda não foi liberada.',
  ),
  PassoGuia(
    alvo: AlvoTutorial.abaResumo,
    titulo: 'Toque em Resumo',
    texto: 'Os mesmos anúncios do mapa, agora em lista.',
    abaParaAbrir: 1,
  ),
  PassoGuia(
    alvo: AlvoTutorial.filtroResumo,
    titulo: 'Tudo, moradias ou eventos',
    texto:
        'Este seletor troca o que a lista mostra. Tocar num card abre a mesma '
        'ficha do mapa.',
  ),
  PassoGuia(
    alvo: AlvoTutorial.abaChat,
    titulo: 'Toque em Chat',
    texto: 'É aqui que ficam suas conversas com quem anuncia.',
    abaParaAbrir: 2,
  ),
  PassoGuia(
    titulo: 'Falta uma coisa',
    texto:
        'Para enviar mensagem, avaliar alguém ou publicar anúncio, o cadastro '
        'precisa estar completo. É a última parada deste guia.',
  ),
  PassoGuia(
    alvo: AlvoTutorial.abaMapa,
    titulo: 'Voltar para o mapa',
    texto: 'O perfil fica lá no canto de cima.',
    abaParaAbrir: 0,
  ),
  PassoGuia(
    alvo: AlvoTutorial.avatar,
    titulo: 'Conclua seu cadastro aqui',
    texto:
        'Toque no seu avatar e depois em "Concluir Perfil". Você escolhe o '
        'tipo de conta (estudante, proprietário ou corretor) e o app libera o '
        'resto. Quando terminar, eu volto para mostrar o que abriu.',
    abreOutraTela: true,
  ),
];

// ---------------------------------------------------------------------------
// Parte 2: cadastro concluído, conforme o tipo de conta
// ---------------------------------------------------------------------------

// chave usada pra lembrar que esta parte ja rodou (ver tutorial_visto.dart).
// O subtipo do corretor entra porque o guia dele e diferente: o de empresa
// espera a aprovacao da imobiliaria pra poder anunciar, e a conta master dela
// e quem da essa aprovacao
String chaveGuiaDoPerfil(Usuario perfil) {
  final tipo = perfil.tipoUsuario.toLowerCase();
  if (tipo == 'corretor') {
    if (perfil.ehAdminImobiliaria) return 'imobiliaria_admin';
    return perfil.subtipoCorretor == 'empresa'
        ? 'corretor_empresa'
        : 'corretor_autonomo';
  }
  return tipo.isEmpty ? 'sem_tipo' : tipo;
}

List<PassoGuia> passosDoPerfil(
  Usuario perfil, {
  // cadastro antigo: quem entra com o e-mail de uma imobiliaria responde pelos
  // corretores dela sem que isso apareca no perfil. Nao e um tipo de conta, e
  // uma situacao -- por isso vem de fora. Em cadastro novo o proprio perfil ja
  // diz (ehAdminImobiliaria)
  bool ehContaDaImobiliaria = false,
}) {
  final tipo = perfil.tipoUsuario.toLowerCase();
  final bool anuncia = tipo == 'proprietario' || tipo == 'corretor';
  final bool corretorDeEmpresa =
      tipo == 'corretor' && perfil.subtipoCorretor == 'empresa';
  final bool respondePelaImobiliaria =
      ehContaDaImobiliaria || perfil.ehAdminImobiliaria;
  final primeiroNome = perfil.nome.split(' ').first;

  return [
    PassoGuia(
      titulo: primeiroNome.isEmpty
          ? 'Cadastro concluído!'
          : 'Tudo certo, $primeiroNome!',
      texto: anuncia
          ? 'Seu cadastro está completo. Agora eu mostro o que abriu para '
                'quem anuncia.'
          : 'Seu cadastro está completo. Agora eu mostro o que abriu com ele.',
    ),
    const PassoGuia(
      alvo: AlvoTutorial.avatar,
      titulo: 'Seu perfil agora vale',
      texto:
          'Sua foto e seu nome aparecem para as outras pessoas; CPF, CNPJ e '
          'endereço ficam só para você. É por aqui também que chegam as '
          'notificações, e que você reabre este guia quando quiser.',
      abreOutraTela: true,
    ),
    const PassoGuia(
      alvo: AlvoTutorial.abaChat,
      titulo: 'Toque em Chat',
      texto:
          'A conversa está liberada: texto, foto e áudio. Mensagem nova acende '
          'a bolinha vermelha aqui na aba.',
      abaParaAbrir: 2,
    ),
    PassoGuia(
      titulo: 'A ficha do anúncio',
      texto: anuncia
          ? 'Tocar num pin abre fotos, preço, o que está incluso, as '
                'distâncias dos lugares em volta e quem anunciou. É essa mesma '
                'ficha que as pessoas vão ver do seu imóvel.'
          : 'Tocar num pin abre fotos, preço, o que está incluso e as '
                'distâncias dos lugares em volta. De lá dá para falar com quem '
                'anunciou, calcular a rota e usar o "Ir" para navegar até o '
                'imóvel.',
    ),
    const PassoGuia(
      titulo: 'Avaliações',
      texto:
          'Todo anunciante e toda imobiliária têm um perfil público com nota e '
          'comentários. Depois do atendimento, deixe a sua: é o que ajuda quem '
          'vier procurar depois.',
    ),
    if (corretorDeEmpresa && !perfil.podeAnunciar)
      const PassoGuia(
        titulo: 'Falta a imobiliária aprovar',
        texto:
            'Seu vínculo está pendente. Assim que alguém que responde pela '
            'imobiliária confirmar que você trabalha lá, o botão "Anunciar" '
            'aparece no mapa e a resposta chega nas suas notificações.',
      ),
    if (respondePelaImobiliaria)
      const PassoGuia(
        titulo: 'Você responde por uma imobiliária',
        texto:
            'Esta conta é a administradora de uma imobiliária, então os pedidos '
            'de vínculo dos corretores chegam aqui: a folha abre sozinha ao '
            'entrar. Aprove só quem trabalha aí. Logotipo, descrição e fotos do '
            'escritório ficam em "Editar imobiliária", no seu perfil.',
      ),
    if (anuncia) ...[
      const PassoGuia(
        alvo: AlvoTutorial.abaImoveis,
        titulo: 'Toque em Imóveis',
        texto:
            'É o painel dos seus anúncios. Tocar em um deles abre as três '
            'ações: ver a ficha como as outras pessoas veem, alterar ou '
            'apagar.',
        abaParaAbrir: 3,
      ),
      const PassoGuia(
        titulo: 'Responda quem te procura',
        texto:
            'Anúncio que passa cinco meses com mensagem sem resposta sai do '
            'mapa e da lista. O painel avisa antes, com o prazo no próprio '
            'card, e uma resposta no chat traz o anúncio de volta na hora.',
      ),
      PassoGuia(
        alvo: AlvoTutorial.abaMapa,
        titulo: 'Voltar para o mapa',
        texto: perfil.podeAnunciar
            ? 'É de lá que sai um anúncio novo.'
            : 'É de lá que sairá seu primeiro anúncio, assim que o vínculo '
                  'for aprovado.',
        abaParaAbrir: 0,
      ),
      if (perfil.podeAnunciar)
        const PassoGuia(
          alvo: AlvoTutorial.anunciar,
          titulo: 'Publique seu primeiro anúncio',
          texto:
              'O formulário começa pelas fotos e segue por título, endereço '
              '(o CEP preenche o resto), preço, tipo do imóvel, comprovantes '
              'e características. Você escolhe entre moradia e evento, e isso '
              'não muda depois de publicado.',
          abreOutraTela: true,
        ),
    ],
    PassoGuia(
      titulo: 'Pronto, é seu',
      texto: anuncia
          ? 'Qualquer dúvida, o guia inteiro volta pelo seu perfil, em "Ver '
                'tutorial".'
          : 'Comece pelo mapa, filtre pelo que importa para você e chame no '
                'chat quem tiver o lugar certo. Para rever este guia: seu '
                'perfil, em "Ver tutorial".',
    ),
  ];
}
