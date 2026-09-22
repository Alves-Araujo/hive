import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moradia_app/utils/moeda.dart';

// A mascara de moeda existe porque preco e IPTU aceitavam qualquer texto e o
// anuncio acabava salvo com R$ 0,00 (ver MoedaInputFormatter). O que importa
// e o par formatar/ler: o que aparece no campo e o que vai pro Firestore tem
// que ser o mesmo numero.
void main() {
  // simula a digitacao tecla por tecla, como o campo faz de verdade
  String digitar(String teclas) {
    const mascara = MoedaInputFormatter();
    var valor = TextEditingValue.empty;
    for (final tecla in teclas.split('')) {
      final novo = TextEditingValue(
        text: valor.text + tecla,
        selection: TextSelection.collapsed(offset: valor.text.length + 1),
      );
      valor = mascara.formatEditUpdate(valor, novo);
    }
    return valor.text;
  }

  group('MoedaInputFormatter', () {
    test('o valor cresce da direita pra esquerda, como em caixa eletronico', () {
      expect(digitar('1'), '0,01');
      expect(digitar('12'), '0,12');
      expect(digitar('120'), '1,20');
      expect(digitar('1200'), '12,00');
      expect(digitar('120000'), '1.200,00');
    });

    test('letra e simbolo nao entram no campo', () {
      expect(digitar('abc'), '');
      expect(digitar('1a2b0c0'), '12,00');
      // colar "R$ 150,00" deixa so os digitos, na mesma leitura de centavos
      expect(digitar('R\$ 150,00'), '150,00');
    });

    test('campo vazio (e so zeros) nao vira 0,00 preso', () {
      expect(digitar(''), '');
      expect(digitar('000'), '');
      expect(digitar('0005'), '0,05');
    });

    test('para de crescer depois de 11 digitos', () {
      expect(digitar('12345678901'), '123.456.789,01');
      // o que vier depois e ignorado, em vez de estourar a largura do campo
      expect(digitar('123456789012345'), '123.456.789,01');
    });
  });

  group('ida e volta do campo', () {
    test('o que o campo mostra e o que vai pro banco', () {
      expect(valorDoCampo(digitar('120000')), 1200.0);
      expect(valorDoCampo(digitar('89990')), 899.90);
      expect(valorDoCampo(''), 0);
    });

    test('valor salvo volta pro campo no mesmo formato (edicao de anuncio)', () {
      expect(formatarValorEmCampo(1200), '1.200,00');
      expect(formatarValorEmCampo(899.9), '899,90');
      // nada gravado = campo vazio, e nao "0,00"
      expect(formatarValorEmCampo(0), '');
    });
  });
}
