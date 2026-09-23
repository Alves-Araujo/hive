// Testes das regras do firestore para o que o relatorio de bugs pediu pra
// travar no BACKEND, e nao so na tela:
//
// - a categoria do anuncio (moradia/evento) nao muda depois de publicado
// - tipo de conta (e subtipo do corretor) nao muda depois do cadastro
// - so quem entra com o e-mail da imobiliaria aprova/recusa um corretor dela
//
// Nada disso da pra conferir no aparelho: a tela ja bloqueia os campos, e o
// que estes testes chamam e o Firestore direto, como faria quem contorna o app.
//
// Rodar com:
//   npx firebase emulators:exec --only firestore --project moradias-inatel \
//     "node test/rules/cadastro.test.mjs"
// (a partir da pasta moradia_app)

import { readFileSync } from 'node:fs';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { doc, setDoc, updateDoc } from 'firebase/firestore';

const DONO = 'uidDono';           // publicou o anuncio
const ESTRANHO = 'uidEstranho';
const CORRETOR = 'uidCorretor';   // pediu vinculo com a imobiliaria
const IMOBILIARIA = 'imob1';
const EMAIL_IMOBILIARIA = 'contato@imobiliaria.com';
const ANUNCIO = 'anuncio1';

let env;
const resultados = [];

async function verifica(descricao, fn) {
  try {
    await fn();
    resultados.push({ descricao, ok: true });
  } catch (erro) {
    resultados.push({ descricao, ok: false, erro });
  }
}

// o estado que o app ja teria gravado, com as regras desligadas
async function prepararDados() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();

    await setDoc(doc(db, 'usuarios', DONO), {
      perfilCompleto: true,
      tipoUsuario: 'proprietario',
      subtipoCorretor: '',
      nome: 'Dona Maria',
      cpf: '11111111111',
    });
    await setDoc(doc(db, 'usuarios', CORRETOR), {
      perfilCompleto: true,
      tipoUsuario: 'corretor',
      subtipoCorretor: 'empresa',
      nome: 'Corretor Silva',
      imobiliariaId: IMOBILIARIA,
    });
    // conta que ainda nao finalizou o cadastro: nela o tipo AINDA pode ser escolhido
    await setDoc(doc(db, 'usuarios', ESTRANHO), {
      perfilCompleto: false,
      tipoUsuario: '',
      nome: 'Novato',
    });

    await setDoc(doc(db, 'imoveis', ANUNCIO), {
      donoUid: DONO,
      tipo: 'moradia',
      titulo: 'Kitnet perto da facul',
      preco: 900,
    });

    await setDoc(doc(db, 'imobiliarias', IMOBILIARIA), {
      nome: 'Imobiliária Central',
      emailBusca: EMAIL_IMOBILIARIA,
      emailVerificado: false,
    });

    await setDoc(doc(db, 'perfisPublicos', CORRETOR), {
      nome: 'Corretor Silva',
      tipoUsuario: 'corretor',
      subtipoCorretor: 'empresa',
      imobiliariaId: IMOBILIARIA,
      vinculoConfirmado: false,
      vinculoRecusado: false,
    });
  });
}

async function main() {
  env = await initializeTestEnvironment({
    projectId: 'moradias-inatel',
    firestore: {
      rules: readFileSync('firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
  await env.clearFirestore();
  await prepararDados();

  const donoDb = env.authenticatedContext(DONO).firestore();
  const estranhoDb = env.authenticatedContext(ESTRANHO).firestore();
  const corretorDb = env.authenticatedContext(CORRETOR).firestore();

  // quem entra com o e-mail da imobiliaria, ja confirmado
  const imobiliariaDb = env
    .authenticatedContext('uidAdminImob', {
      email: EMAIL_IMOBILIARIA,
      email_verified: true,
    })
    .firestore();

  // o mesmo e-mail, mas sem confirmar: nao prova nada
  const semConfirmarDb = env
    .authenticatedContext('uidNaoConfirmado', {
      email: EMAIL_IMOBILIARIA,
      email_verified: false,
    })
    .firestore();

  // --- categoria do anuncio (moradia <-> evento) ---------------------------

  await verifica('o dono edita o anuncio sem mexer na categoria', async () => {
    await assertSucceeds(
      updateDoc(doc(donoDb, 'imoveis', ANUNCIO), { preco: 950, tipo: 'moradia' }),
    );
  });

  await verifica('o dono NAO transforma a moradia dele em evento', async () => {
    await assertFails(updateDoc(doc(donoDb, 'imoveis', ANUNCIO), { tipo: 'evento' }));
  });

  await verifica('nem apagando o campo tipo no update', async () => {
    await assertFails(
      setDoc(doc(donoDb, 'imoveis', ANUNCIO), { donoUid: DONO, titulo: 'sem tipo' }),
    );
  });

  await verifica('estranho continua sem editar anuncio alheio', async () => {
    await assertFails(updateDoc(doc(estranhoDb, 'imoveis', ANUNCIO), { preco: 1 }));
  });

  // --- tipo de conta -------------------------------------------------------

  await verifica('cadastro finalizado NAO troca de tipo de conta', async () => {
    await assertFails(
      updateDoc(doc(donoDb, 'usuarios', DONO), { tipoUsuario: 'estudante' }),
    );
  });

  await verifica('corretor de empresa NAO vira autonomo pra fugir da aprovacao', async () => {
    await assertFails(
      updateDoc(doc(corretorDb, 'usuarios', CORRETOR), { subtipoCorretor: 'autonomo' }),
    );
  });

  await verifica('o resto do perfil continua editavel', async () => {
    await assertSucceeds(
      updateDoc(doc(donoDb, 'usuarios', DONO), { nome: 'Maria Aparecida' }),
    );
  });

  await verifica('quem ainda nao finalizou escolhe o tipo normalmente', async () => {
    await assertSucceeds(
      updateDoc(doc(estranhoDb, 'usuarios', ESTRANHO), {
        tipoUsuario: 'estudante',
        perfilCompleto: true,
      }),
    );
  });

  // --- aprovacao do vinculo ------------------------------------------------

  await verifica('o proprio corretor NAO aprova o vinculo dele', async () => {
    await assertFails(
      setDoc(
        doc(corretorDb, 'perfisPublicos', CORRETOR),
        { vinculoConfirmado: true },
        { merge: true },
      ),
    );
  });

  await verifica('quem nao confirmou o e-mail da imobiliaria NAO aprova', async () => {
    await assertFails(
      setDoc(
        doc(semConfirmarDb, 'perfisPublicos', CORRETOR),
        { vinculoConfirmado: true },
        { merge: true },
      ),
    );
  });

  await verifica('quem entra com o e-mail da imobiliaria recusa o vinculo', async () => {
    await assertSucceeds(
      setDoc(
        doc(imobiliariaDb, 'perfisPublicos', CORRETOR),
        { vinculoRecusado: true },
        { merge: true },
      ),
    );
  });

  await verifica('quem entra com o e-mail da imobiliaria aprova o vinculo', async () => {
    await assertSucceeds(
      setDoc(
        doc(imobiliariaDb, 'perfisPublicos', CORRETOR),
        { vinculoConfirmado: true },
        { merge: true },
      ),
    );
  });

  await verifica('aprovar NAO e porta pra reescrever o resto do perfil', async () => {
    await assertFails(
      setDoc(
        doc(imobiliariaDb, 'perfisPublicos', CORRETOR),
        { vinculoConfirmado: true, nome: 'Outro Nome' },
        { merge: true },
      ),
    );
  });

  await env.cleanup();

  const falhas = resultados.filter((r) => !r.ok);
  for (const r of resultados) {
    console.log(`${r.ok ? '  ok  ' : ' FALHA'}  ${r.descricao}`);
    if (!r.ok) console.log(`        ${r.erro.message.split('\n')[0]}`);
  }
  console.log(`\n${resultados.length - falhas.length}/${resultados.length} passaram`);
  process.exit(falhas.length === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
