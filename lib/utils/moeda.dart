import 'package:flutter/services.dart';

// ponto no milhar, sem separar o que ainda nao chegou a mil
String _comSeparadorDeMilhar(String inteiro) {
  final comPontos = StringBuffer();
  for (var i = 0; i < inteiro.length; i++) {
    final posicaoDaDireita = inteiro.length - i;
    if (i > 0 && posicaoDaDireita % 3 == 0) comPontos.write('.');
    comPontos.write(inteiro[i]);
  }
  return comPontos.toString();
}

// formata um valor em reais no padrao brasileiro "R$1.200,00" (ponto no
// milhar, virgula nos centavos) -- sem depender do pacote intl so pra isso
String formatarPreco(double valor) {
  final inteiro = valor.truncate().abs();
  final centavos = ((valor - valor.truncate()) * 100).round().abs();
  final sinal = valor < 0 ? '-' : '';
  return 'R\$$sinal${_comSeparadorDeMilhar(inteiro.toString())},'
      '${centavos.toString().padLeft(2, '0')}';
}

// preco de anuncio pra exibicao. Zero vira "Gratuito": so evento pode ser
// gravado sem valor (o formulario exige valor na moradia), e "R$0,00" num
// evento parece campo que ninguem preencheu, nao entrada franca
String formatarPrecoOuGratuito(double valor) =>
    valor > 0 ? formatarPreco(valor) : 'Gratuito';

// o MESMO formato, sem o "R$" -- e o que vai DENTRO do campo de texto, ja que
// ali o cifrao fica no prefixo da decoracao. Usado pra preencher o campo na
// edicao de um anuncio ja salvo
String formatarValorEmCampo(double valor) =>
    valor == 0 ? '' : formatarPreco(valor).replaceFirst('R\$', '');

// le de volta o que o campo mascarado mostra. Como a mascara trata o que foi
// digitado como CENTAVOS, "1.234,56" tem os mesmos digitos que 123456 -- e
// dividir por 100 devolve o valor certo sem depender de onde caiu a virgula
double valorDoCampo(String texto) {
  final digitos = texto.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitos.isEmpty) return 0;
  return (int.tryParse(digitos) ?? 0) / 100;
}

// Mascara de moeda dos campos de dinheiro (preco do anuncio, valor do IPTU).
//
// Existe porque esses campos aceitavam letra e simbolo: o texto ia cru pro
// double.tryParse, que devolvia null, e o anuncio era salvo com R$ 0,00 sem
// ninguem perceber. Aqui NAO ha como digitar o que nao e digito -- o resto e
// descartado antes de virar texto, o que tambem cobre colar da area de
// transferencia e teclado fisico, que o teclado numerico sozinho nao cobre.
//
// O valor cresce da direita pra esquerda, como em caixa eletronico: digitar
// "1", "2", "0", "0" mostra 0,01 -> 0,12 -> 1,20 -> 12,00
class MoedaInputFormatter extends TextInputFormatter {
  const MoedaInputFormatter();

  // 11 digitos = ate 999.999.999,99. Passar disso nao e valor de aluguel nem
  // de IPTU, e o campo estouraria a largura
  static const int _maximoDeDigitos = 11;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue anterior, TextEditingValue novo) {
    final digitos = novo.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitos.isEmpty) return const TextEditingValue();

    // apagou tudo e digitou so zeros: nao vira "0,00" preso no campo
    final semZerosAEsquerda = digitos.replaceFirst(RegExp(r'^0+'), '');
    if (semZerosAEsquerda.isEmpty) return const TextEditingValue();

    final limitados = semZerosAEsquerda.length > _maximoDeDigitos
        ? semZerosAEsquerda.substring(0, _maximoDeDigitos)
        : semZerosAEsquerda;

    final texto = formatarValorEmCampo((int.parse(limitados)) / 100);
    // cursor sempre no fim: com a mascara reescrevendo o texto inteiro a cada
    // tecla, deixar o cursor onde estava o jogaria no meio dos pontos
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}
