# Mensagem pro dono do Firebase (apagar a imobiliária "Sodré")

Copiar e colar. É só apagar dois documentos no Firestore, não tem nada pra
publicar nem código envolvido.

---

Opa! Preciso apagar do Firestore do Hive (`moradias-inatel`) um cadastro de
teste de imobiliária que ficou no banco. São **dois documentos**, e nenhuma
conta de usuário consegue apagar pelas regras (não existe `allow delete` nesses
dois lugares), por isso estou te pedindo.

**Os dois documentos, com o caminho exato**

1. `imobiliarias/gWvhogDzmPZ0OWnj6MzG`
   É a imobiliária "Sodré" (CNPJ 93.352.787/0001-31, e-mail
   utra1221@gmail.com, endereço Rua Coronel João Euzébio, 438, Santa Rita do
   Sapucaí). Confere o nome antes de apagar: tem que estar escrito `Sodré` no
   campo `nome`.

2. `notificacoes/y8d2SWQIWDVzILzImWg0`
   É o aviso "Nova imobiliária: Sodré" que apareceu pra todo mundo quando ela
   foi cadastrada. Sem ele, fica um aviso no app que não abre nada.

**O que NÃO pode ser tocado**

- A outra imobiliária, `imobiliarias/sFKqIoPWqmufXPDdE3P1` ("Imobiliaria
  Silva"), fica como está. São só essas duas na coleção, então é fácil apagar a
  errada: apaga pelo **id**, não pela posição na lista.
- Nenhum anúncio (`imoveis`), nenhum perfil e nenhum outro aviso da coleção
  `notificacoes` (tem 18 lá, só aquele um sai).
- Não apagar a coleção inteira nem usar delete recursivo. São dois documentos
  soltos, um de cada vez.

**Pelo console (mais fácil)**

1. Firebase > Firestore Database > aba Dados.
2. Abre a coleção `imobiliarias`, clica no documento `gWvhogDzmPZ0OWnj6MzG`,
   confere que o `nome` é `Sodré` e usa o menu dos três pontinhos >
   "Excluir documento".
3. Abre a coleção `notificacoes`, clica no documento `y8d2SWQIWDVzILzImWg0`,
   confere que o `titulo` é `Nova imobiliária: Sodré` e exclui do mesmo jeito.

**Pelo terminal, se preferir**

```
firebase firestore:delete "imobiliarias/gWvhogDzmPZ0OWnj6MzG" --project moradias-inatel
firebase firestore:delete "notificacoes/y8d2SWQIWDVzILzImWg0" --project moradias-inatel
```

Ele pergunta "confirma?" em cada um, é só responder que sim. Sem `--recursive`
e sem `--all-collections`.

**Como conferir que deu certo**

No console, a coleção `imobiliarias` tem que ficar com **um** documento só
(a "Imobiliaria Silva"), e a `notificacoes` com **17**.

**Detalhes que talvez você queira saber**

- A imobiliária tinha coordenada, então ela aparecia como pin no mapa do app.
  O pin some sozinho assim que o documento for apagado, o app lê isso ao vivo.
- Tem um corretor (Rafael Yohanam) com pedido de vínculo pendente apontando pra
  essa imobiliária. O perfil dele **não** precisa ser mexido: o app trata o
  vínculo órfão numa boa (o campo aparece vazio e ele escolhe outra
  imobiliária na tela de perfil). Melhor deixar quieto do que editar o perfil
  de um usuário na mão.
- Isso aqui é independente da mensagem das regras (`mensagem-regras-firestore.md`).
  Se você ainda não publicou as regras, pode fazer as duas coisas na mesma
  sentada, mas uma não depende da outra.
