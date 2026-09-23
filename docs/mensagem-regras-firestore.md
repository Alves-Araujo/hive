# Mensagem pro dono do Firebase (publicar as regras)

Copiar e colar. O arquivo alterado é `moradia_app/firestore.rules`.

---

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

Os testes das regras rodam no emulador, sem tocar em produção:

```
cd moradia_app
npx --prefix test/rules firebase emulators:exec --only firestore \
  --project moradias-inatel "node test/rules/cadastro.test.mjs"
npx --prefix test/rules firebase emulators:exec --only firestore \
  --project moradias-inatel "node test/rules/chats.test.mjs"
```

Aqui passaram 13/13 e 19/19. Me avisa quando publicar que eu confiro no app.
