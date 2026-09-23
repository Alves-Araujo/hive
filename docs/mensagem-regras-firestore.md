# Mensagem pro dono do Firebase (publicar as regras)

Copiar e colar. O arquivo alterado é `moradia_app/firestore.rules`.

---

## Mensagem atual: duas coisas pra publicar (uma delas está quebrando no app)

Opa! Mexi no `firestore.rules` do Hive de novo e preciso que você publique. São
uns 5 minutos, o passo a passo tá no fim. Dessa vez são **duas** mudanças, e a
primeira já está dando erro pra quem usa o app.

**1. A imobiliária não consegue salvar o próprio cadastro (é o urgente)**

Salvar em "Dados da Imobiliária" volta com
`[cloud_firestore/permission-denied]`. A regra que libera essa edição já está no
`firestore.rules` do repositório e passa nos testes do emulador, mas **ainda não
subiu pro projeto** - enquanto não subir, o botão abre a tela e o salvar falha
sempre. Não tem nada pra consertar no app: é só publicar.

O que essa regra faz, em `match /imobiliarias`:

- entrou a função `souAImobiliaria()`: e-mail do login **confirmado** e igual ao
  `emailBusca` do documento. É o mesmo critério que já valia pra aprovar
  corretor, agora escrito uma vez só e usado nos dois lugares;
- novo caminho de `update` pra essa conta, limitado a `nome`, `nomeBusca`,
  `descricao`, `telefone`, `fotoUrl`, `fotos`, `endereco`, `latitude` e
  `longitude` (`descricao`, `telefone` e `fotos` são campos novos, preenchidos
  na tela nova). `fotoUrl` é o logotipo, que já existia; `fotos` é a galeria do
  escritório que aparece quando alguém toca no pin da imobiliária no mapa, do
  mesmo jeito que já acontece com farmácia e mercado;
- ficam de fora, de propósito: `cnpj`/`cnpjBusca` (é a chave que evita cadastro
  duplicado), `email`/`emailBusca` (trocar entregaria a imobiliária, e os
  corretores dela, pra outra conta) e `emailVerificado` (só a confirmação liga);
- o nome não pode ficar vazio.

A função lê o token por `get()` com padrão: login sem e-mail (telefone, anônimo)
derrubava a avaliação da regra, e um cadastro antigo sem `emailBusca` casaria
com o e-mail vazio dessas contas.

**2. Anúncio sem resposta sai do mapa**

Moradia anunciada, gente mandando mensagem e ninguém respondendo: o anúncio fica
no mapa pra sempre ocupando o lugar de quem responde, e quem procura moradia
gasta o tempo dele mandando mensagem pro vazio.

Agora o anúncio tem um campo novo, `aguardandoRespostaDesde`. A mensagem de um
interessado liga esse relógio, qualquer resposta do dono desliga. Cinco meses
com o relógio ligado e o anúncio some do mapa e da lista - e volta na hora em
que o dono responder. O dono vê o prazo no painel "Meus Imóveis" desde um mês
antes de sumir. É tudo calculado na hora da leitura, porque a gente não tem
Cloud Functions pra virar chave nenhuma na hora certa.

O detalhe que exige mexer nas regras: quem liga o relógio é o **interessado**,
não o dono. Ou seja, alguém escrevendo num anúncio que não é dele - o único
caso assim no app inteiro. Por isso a regra nova é bem fechada (as travas estão
listadas no fim, caso queira revisar antes de publicar).

**Passo a passo**

1. Pega a versão nova do código (`git pull` no repositório do Hive). O arquivo
   que mudou é `moradia_app/firestore.rules`. Se for mais fácil, eu te mando o
   arquivo e você só substitui.

2. Entra na pasta do app:

```
cd moradia_app
```

3. Se você não tiver o firebase-tools instalado:

```
npm install -g firebase-tools
```

   (ou usa `npx firebase` no lugar de `firebase` nos comandos abaixo)

4. Entra na conta dona do projeto:

```
firebase login
```

5. **Opcional, mas recomendado:** roda os testes das regras no emulador. Não
   encosta em produção, só precisa de Java instalado:

```
cd test/rules && npm install && cd ../..
firebase emulators:exec --only firestore --project moradias-inatel \
  "node test/rules/cadastro.test.mjs && node test/rules/prazo-resposta.test.mjs \
   && node test/rules/chats.test.mjs"
```

   Tem que aparecer `25/25`, `10/10` e `19/19 passaram` - aqui rodei os três. O
   `cadastro.test.mjs` é o que cobre a edição da imobiliária, inclusive com o
   payload exato que a tela manda.

6. Publica **só** as regras do Firestore:

```
firebase deploy --only firestore:rules --project moradias-inatel
```

7. Confere no console: Firebase > Firestore Database > aba Regras. A data da
   última publicação tem que ser de agora, e as regras publicadas têm que ter:
   - a função `souAImobiliaria()` dentro de `match /imobiliarias`, e **três**
     `allow update` nesse bloco (é a parte 1, a que está quebrando agora);
   - **dois** `allow update` no bloco `match /imoveis` (é a parte 2).

8. Me avisa que eu testo no celular.

**Importante**

- Não precisa criar índice, migrar dado nem mexer no `storage.rules`. Anúncio
  antigo simplesmente não tem o campo novo, e não ter já significa "ninguém
  esperando resposta".
- Publica com `--only firestore:rules` mesmo. Sem isso o deploy pode mexer em
  outras partes do projeto.
- Se der `permission denied` no deploy, é a conta: precisa ser Editor ou
  Proprietário do projeto `moradias-inatel`. Confere com
  `firebase projects:list`.
- Enquanto não publicar: a parte 2 só não faz efeito (o relógio nunca liga e
  nenhum anúncio sai do mapa, nada quebra), mas a parte 1 continua quebrada -
  salvar em "Dados da Imobiliária" volta com `permission-denied` toda vez,
  inclusive pra mandar as fotos do escritório.

**As travas da regra nova do anúncio** (pra revisar antes, se quiser)

Em `match /imoveis` entrou um segundo caminho de `update`. Quem não é dono do
anúncio só consegue escrever se:

- mudar **só** o campo `aguardandoRespostaDesde`;
- a data for a do **servidor** (`request.time`) - senão daria pra gravar "cinco
  meses atrás" e derrubar o anúncio de um concorrente na hora;
- o campo estiver **desligado** - o prazo conta da primeira mensagem sem
  resposta, e reescrever só serviria pra adiar o próprio prazo;
- quem escreve **tiver conversa aberta naquele anúncio**, provado pelo
  `exists()` do chat (o id dele já é derivado dos dois uids + o imovelId). Sem
  isso, qualquer um derrubaria qualquer anúncio.

Desligar o relógio continua sendo coisa só do dono, pela regra de update que já
existia. Tudo isso tem teste próprio no `prazo-resposta.test.mjs`, inclusive os
ataques (estranho tentando derrubar anúncio alheio, data forjada, mudar o preço
junto).

---

## Mensagem anterior (já publicada): três correções do relatório de bugs

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
