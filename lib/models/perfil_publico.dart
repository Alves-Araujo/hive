import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/texto.dart';

// versao "publica" do Usuario -- so os dados que qualquer pessoa logada pode
// ver (nome, foto, tipo de conta...), sem CPF/CNPJ/endereco/telefone/etc.
// Guardada numa colecao separada (perfisPublicos) pra nao expor dado sensivel
// pra quem le o perfil de outra pessoa (busca, chat, avaliacoes...)
class PerfilPublico {
  final String uid;
  final String nome;
  final String nomeBusca;
  final String fotoUrl;
  final String tipoUsuario;
  final String subtipoCorretor;

  // 'admin' na conta master da imobiliaria, 'equipe' em quem pediu vinculo --
  // ver Usuario.papelImobiliaria. Precisa estar aqui porque e esta colecao que
  // a imobiliaria le pra montar a lista de pedidos: sem o papel, a propria
  // conta master apareceria na lista esperando que alguem a aprovasse
  final String papelImobiliaria;

  final String cidade;
  final String imobiliariaId;

  // resposta da imobiliaria ao pedido de vinculo. Moram aqui, e nao em
  // "usuarios", porque quem responde e outra pessoa -- e o perfil do corretor
  // so ele mesmo escreve
  final bool vinculoConfirmado;
  final bool vinculoRecusado;
  final DateTime? ultimoAcesso;

  PerfilPublico({
    required this.uid,
    required this.nome,
    this.nomeBusca = '',
    this.fotoUrl = '',
    this.tipoUsuario = '',
    this.subtipoCorretor = '',
    this.papelImobiliaria = '',
    this.cidade = '',
    this.imobiliariaId = '',
    this.vinculoConfirmado = false,
    this.vinculoRecusado = false,
    this.ultimoAcesso,
  });

  // a conta master da imobiliaria (ver Usuario.ehAdminImobiliaria)
  bool get ehAdminImobiliaria => papelImobiliaria == 'admin';

  // pedido de vinculo esperando resposta da imobiliaria
  bool get vinculoPendente =>
      imobiliariaId.isNotEmpty &&
      !ehAdminImobiliaria &&
      !vinculoConfirmado &&
      !vinculoRecusado;

  factory PerfilPublico.fromMap(Map<String, dynamic> map, String uid) {
    return PerfilPublico(
      uid: uid,
      nome: normalizarTracosOuVazio(map['nome']),
      nomeBusca: map['nomeBusca'] ?? '',
      fotoUrl: map['fotoUrl'] ?? '',
      tipoUsuario: map['tipoUsuario'] ?? '',
      subtipoCorretor: map['subtipoCorretor'] ?? '',
      papelImobiliaria: map['papelImobiliaria'] ?? '',
      cidade: map['cidade'] ?? '',
      imobiliariaId: map['imobiliariaId'] ?? '',
      vinculoConfirmado: map['vinculoConfirmado'] ?? false,
      vinculoRecusado: map['vinculoRecusado'] ?? false,
      ultimoAcesso: (map['ultimoAcesso'] as Timestamp?)?.toDate(),
    );
  }
}
