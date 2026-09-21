import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:moradia_app/models/imovel.dart';
import 'package:moradia_app/services/busca_service.dart';

// A busca e a ferramenta central do app: e por ela que se chega em tudo.
// Testar pela tela custa um build de 4 minutos por tentativa e so cobre o
// caso que der pra digitar na hora -- aqui da pra fixar as formas de errar
// que ja apareceram de verdade e garantir que nenhuma volte.
void main() {
  final busca = BuscaService.instance;

  Imovel imovel({
    String titulo = 'República Estudantil Central',
    String bairro = 'Centro',
    String cidade = 'Santa Rita do Sapucaí',
    String tipoImovel = 'República',
    String endereco = 'Rua Dr. Delfino, 120 - Centro',
  }) =>
      Imovel(
        id: '1',
        titulo: titulo,
        descricao: '',
        preco: 650,
        posicao: const LatLng(-22.25, -45.70),
        tipo: TipoListing.moradia,
        tags: const [],
        endereco: endereco,
        fotos: const [],
        donoUid: 'x',
        cep: '',
        logradouro: '',
        numero: '',
        complemento: '',
        bairro: bairro,
        cidade: cidade,
        estado: 'MG',
        tipoImovel: tipoImovel,
        andar: '',
        comprovanteResidenciaUrl: '',
        iptuValor: 0,
        iptuComprovanteUrl: '',
        incluiLuz: false,
        incluiAgua: false,
        incluiWifi: false,
      );

  List<String> textos(String query, {List<Imovel>? imoveis}) =>
      busca.buscarSugestoes(query, imoveis ?? [imovel()]).map((s) => s.texto).toList();

  group('o que a pessoa digita chega no lugar certo', () {
    test('nome completo da cidade', () {
      expect(textos('Santa Rita do Sapucaí'), contains('Santa Rita do Sapucaí, MG'));
    });

    test('espaco sobrando no fim nao derruba o resultado', () {
      expect(textos('Santa Rita do Sapucaí '), contains('Santa Rita do Sapucaí, MG'));
      expect(textos('  santa   rita  '), contains('Santa Rita do Sapucaí, MG'));
    });

    test('palavras fora de ordem', () {
      expect(textos('sapucai santa'), contains('Santa Rita do Sapucaí, MG'));
      expect(textos('rita sapucai do santa'), contains('Santa Rita do Sapucaí, MG'));
    });

    test('sem acento e sem maiuscula', () {
      expect(textos('SANTA RITA'), contains('Santa Rita do Sapucaí, MG'));
      expect(textos('sapucai'), contains('Santa Rita do Sapucaí, MG'));
    });

    test('pedaco do comeco da palavra', () {
      expect(textos('sap'), contains('Santa Rita do Sapucaí, MG'));
      expect(textos('itaj'), contains('Itajubá, MG'));
    });

    test('erro de uma letra', () {
      expect(textos('sapucia'), contains('Santa Rita do Sapucaí, MG'));
      expect(textos('inatell'), contains('Inatel - Instituto Nacional de Telecomunicações'));
    });

    test('palavra do meio do nome, depois do hifen', () {
      expect(textos('instituto'), contains('Inatel - Instituto Nacional de Telecomunicações'));
      expect(textos('telecomunicacoes'), contains('Inatel - Instituto Nacional de Telecomunicações'));
    });

    test('nada a ver nao casa', () {
      expect(textos('xyzabc'), isEmpty);
      // uma letra trocada e perdao; a palavra inteira diferente nao
      expect(textos('florianopolis'), isEmpty);
    });
  });

  group('anuncios entram na busca pelos proprios campos', () {
    test('pelo titulo', () {
      expect(textos('republica'), contains('República Estudantil Central'));
    });

    test('pelo bairro e pelo tipo', () {
      expect(textos('centro'), contains('República Estudantil Central'));
      expect(textos('pensao', imoveis: [imovel(tipoImovel: 'Pensão', titulo: 'Casa da Dona Maria')]),
          contains('Casa da Dona Maria'));
    });

    test('titulo + bairro juntos, em qualquer ordem', () {
      expect(textos('centro republica'), contains('República Estudantil Central'));
    });
  });

  group('ordem dos resultados', () {
    test('quem casa no comeco do nome vem antes', () {
      final lista = busca.buscarSugestoes('santa', [
        imovel(titulo: 'Kitnet perto de Santa Rita', bairro: '', cidade: ''),
      ]);
      expect(lista.first.texto, 'Santa Rita do Sapucaí, MG');
    });

    test('cidade conhecida vem antes de anuncio que so menciona o nome', () {
      final lista = busca.buscarSugestoes('itajuba', [
        imovel(titulo: 'Quarto em Itajubá', bairro: '', cidade: 'Itajubá'),
      ]);
      expect(lista.first.texto, anyOf('Itajubá, MG', 'UNIFEI - Universidade Federal de Itajubá'));
    });
  });

  group('combina() -- usado pra manter resultado online na tela', () {
    test('segue valendo enquanto a pessoa digita mais letras', () {
      final p1 = busca.palavras('rua cop');
      expect(busca.combina('Rua Copacabana Mirante, São Lourenço', p1), isTrue);

      final p2 = busca.palavras('rua copacabana mirante');
      expect(busca.combina('Rua Copacabana Mirante, São Lourenço', p2), isTrue);
    });

    test('para de valer quando o texto vai pra outro lugar', () {
      final p = busca.palavras('rua guarani');
      expect(busca.combina('Rua Copacabana Mirante, São Lourenço', p), isFalse);
    });
  });
}
