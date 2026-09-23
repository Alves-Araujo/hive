# Mensagem pro dono do Firebase (publicar as regras)

Copiar e colar. O arquivo alterado é `moradia_app/firestore.rules`.

---

## Mensagem atual: imobiliária edita o próprio cadastro

Opa! Mexi no `firestore.rules` de novo, dessa vez pra destravar a edição do
cadastro da imobiliária. Quando puder, publica:

```
cd moradia_app
firebase deploy --only firestore:rules --project moradias-inatel
```

O problema: a conta que entra com o e-mail da imobiliária (a que aprova os
corretores) não conseguia mudar nada do cadastro dela, nem o nome. As regras só
deixavam mexer em `emailVerificado` e em `endereco/latitude/longitude`. Na
prática, corrigir o nome da empresa exigia abrir outra conta, e os corretores já
vinculados continuavam apontando pro cadastro velho.

O que mudou em `match /imobiliarias`:

- entrou a função `souAImobiliaria()`: e-mail do login **confirmado** e igual ao
  `emailBusca` do documento. É o mesmo critério que já valia pra aprovar
  corretor, agora escrito uma vez só e usado nos dois lugares;
- novo caminho de `update` pra essa conta, limitado a `nome`, `nomeBusca`,
  `descricao`, `telefone`, `fotoUrl`, `endereco`, `latitude` e `longitude`
  (`descricao` e `telefone` são campos novos, preenchidos na tela nova);
- ficam de fora, de propósito: `cnpj`/`cnpjBusca` (é a chave que evita cadastro
  duplicado), `email`/`emailBusca` (trocar entregaria a imobiliária, e os
  corretores dela, pra outra conta) e `emailVerificado` (só a confirmação liga);
- o nome não pode ficar vazio.

A função também passou a ler o token por `get()` com padrão: login sem e-mail
(telefone, anônimo) derrubava a avaliação da regra, e um cadastro antigo sem
`emailBusca` casaria com o e-mail vazio dessas contas.

Os testes das regras rodam no emulador, sem tocar em produção:

```
cd moradia_app
npx --prefix test/rules firebase emulators:exec --only firestore \
  --project moradias-inatel "node test/rules/cadastro.test.mjs"
npx --prefix test/rules firebase emulators:exec --only firestore \
  --project moradias-inatel "node test/rules/chats.test.mjs"
```

Aqui passaram 22/22 e 19/19. Enquanto as regras não subirem, o botão "Editar
dados da imobiliária" abre a tela normalmente, mas salvar volta com
`permission-denied`. Me avisa quando publicar que eu confiro no celular.

---

## Mensagem anterior (já publicada)

Opa! Mexi no `firestore.rules` pra fechar três coisas que o relatório de bugs
pediu e que não dava pra resolver só na tela. Quando puder, publica:

```
cd moradia_app
firebase deploy --only firestore:rules --project moradias-inatel
```

O que mudou:

1. **Anúncio não troca de categoria.** No `match /imoveis`, o `update` agora
   exige que o campo `tipo` continue o mesmo. Antes dava pra transformar uma
   moradia em evento (e vice-versa) e o documento ficava com os campos do tipo
   antigo sobrando.

2. **Tipo de conta é imutável depois do cadastro.** A função
   `documentosPreservados()` virou `cadastroPreservado()` e passou a proteger
   `tipoUsuario` e `subtipoCorretor` junto com CPF/CNPJ, para quem já tem
   `perfilCompleto: true`. Sem isso, um corretor de empresa podia virar
   "autônomo" e escapar da aprovação da imobiliária.

3. **Vínculo de corretor com imobiliária.** Em `match /perfisPublicos`:
   - quem entra com o e-mail (confirmado) da imobiliária pode aprovar
     (`vinculoConfirmado`) **ou recusar** (`vinculoRecusado`) um corretor, um
     campo por vez;
   - o próprio corretor **não** consegue mais ligar esses campos no perfil
     dele. Isso era um furo: bastava escrever `vinculoConfirmado: true` no
     próprio `perfisPublicos` pra se auto-aprovar e sair anunciando pela
     imobiliária. Desligar continua liberado, que é o que acontece quando ele
     troca de imobiliária.
</content>
