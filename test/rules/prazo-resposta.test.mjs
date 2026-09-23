// Testes das regras do firestore para o prazo de resposta do anuncio.
//
// O anuncio que passa cinco meses com mensagem sem resposta sai do mapa (ver
// lib/utils/inatividade.dart). Quem LIGA esse relogio e o interessado, nao o
// dono -- ou seja, a regra precisa deixar alguem escrever um campo num
// anuncio alheio, que era exatamente o que nenhuma regra permitia ate agora.
// E o unico caminho desses no app inteiro, entao o que ele NAO deixa fazer
// tem que ser conferido de fora, chamando o firestore como um estranho faria.
//
// Rodar com:
//   npx firebase emulators:exec --only firestore --project moradias-inatel \
//     "node test/rules/prazo-resposta.test.mjs"
// (a partir da pasta moradia_app)

import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, serverTimestamp, deleteField, Timestamp } from 'firebase/firestore';

const ANA = 'uidAna';       // interessada: conversou sobre o anuncio
const BRUNO = 'uidBruno';   // dono do anuncio
const CARLA = 'uidCarla';   // estranha: nunca falou com o Bruno
const IMOVEL = 'imovel123';
const OUTRO_IMOVEL = 'imovel456';

const CAMPO = 'aguardandoRespostaDesde';

const ordenar = (a, b) => [a, b].sort();
const idChat = (imovelId, a, b) => {
  const [p0, p1] = ordenar(a, b);
  return `${imovelId === '' ? 'direto' : imovelId}_${p0}_${p1}`;
};

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

// estado inicial: dois anuncios do Bruno e uma conversa da Ana sobre o
// primeiro deles. A Carla existe, mas nunca abriu conversa nenhuma
async function prepararDados() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const uid of [ANA, BRUNO, CARLA]) {
      await setDoc(doc(db, 'usuarios', uid), { perfilCompleto: true });
    }
    for (const id of [IMOVEL, OUTRO_IMOVEL]) {
      await setDoc(doc(db, 'imoveis', id), {
        titulo: 'Kitnet perto da facul',
        donoUid: BRUNO,
        tipo: 'moradia',
        preco: 900,
      });
    }
    await setDoc(doc(db, 'chats', idChat(IMOVEL, ANA, BRUNO)), {
      participantes: ordenar(ANA, BRUNO),
      imovelId: IMOVEL,
      ultimaMensagem: 'Ainda esta disponivel?',
    });
  });
}

// devolve o anuncio ao estado "ninguem esperando", sem passar pelas regras
async function desligarRelogio(imovelId = IMOVEL) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), 'imoveis', imovelId), { [CAMPO]: deleteField() });
  });
}

async function ligarRelogio(quando, imovelId = IMOVEL) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await updateDoc(doc(ctx.firestore(), 'imoveis', imovelId), { [CAMPO]: quando });
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

  const anaDb = env.authenticatedContext(ANA).firestore();
  const brunoDb = env.authenticatedContext(BRUNO).firestore();
  const carlaDb = env.authenticatedContext(CARLA).firestore();
  const deslogadoDb = env.unauthenticatedContext().firestore();

  // --- o caminho que o app usa de verdade ---------------------------------

  await verifica('interessado liga o relogio do anuncio em que conversou', async () => {
    await desligarRelogio();
    await assertSucceeds(
      updateDoc(doc(anaDb, 'imoveis', IMOVEL), { [CAMPO]: serverTimestamp() }),
    );
    const salvo = await getDoc(doc(brunoDb, 'imoveis', IMOVEL));
    assert.ok(salvo.data()[CAMPO], 'a data deveria ter sido gravada');
  });

  await verifica('o dono desliga respondendo', async () => {
    await assertSucceeds(
      updateDoc(doc(brunoDb, 'imoveis', IMOVEL), { [CAMPO]: deleteField() }),
    );
    const salvo = await getDoc(doc(brunoDb, 'imoveis', IMOVEL));
    assert.equal(salvo.data()[CAMPO], undefined, 'o campo deveria ter sumido');
  });

  // --- o que a regra tem que barrar ---------------------------------------

  await verifica('estranho NAO liga o relogio de um anuncio com quem nunca falou', async () => {
    // e o ataque obvio: derrubar do mapa o anuncio de um concorrente sem
    // nunca ter mandado mensagem nenhuma pra ele
    await desligarRelogio();
    await assertFails(
      updateDoc(doc(carlaDb, 'imoveis', IMOVEL), { [CAMPO]: serverTimestamp() }),
    );
  });

  await verifica('conversar sobre UM anuncio nao libera os outros do mesmo dono', async () => {
    await desligarRelogio(OUTRO_IMOVEL);
    await assertFails(
      updateDoc(doc(anaDb, 'imoveis', OUTRO_IMOVEL), { [CAMPO]: serverTimestamp() }),
    );
  });

  await verifica('quem nao entrou na conta nao liga relogio nenhum', async () => {
    await desligarRelogio();
    await assertFails(
      updateDoc(doc(deslogadoDb, 'imoveis', IMOVEL), { [CAMPO]: serverTimestamp() }),
    );
  });

  await verifica('a data tem que ser a do servidor, nao uma escolhida', async () => {
    // com data escolhida, a interessada poria "cinco meses atras" e o anuncio
    // sairia do mapa no mesmo instante
    await desligarRelogio();
    const cincoMesesAtras = Timestamp.fromMillis(Date.now() - 200 * 24 * 60 * 60 * 1000);
    await assertFails(
      updateDoc(doc(anaDb, 'imoveis', IMOVEL), { [CAMPO]: cincoMesesAtras }),
    );
  });

  await verifica('so liga o que esta desligado: o prazo conta da primeira mensagem', async () => {
    // insistir nao pode adiar o proprio prazo -- e o relogio ja ligado e
    // justamente a prova de que ninguem respondeu desde entao
    await ligarRelogio(Timestamp.fromMillis(Date.now() - 100 * 24 * 60 * 60 * 1000));
    await assertFails(
      updateDoc(doc(anaDb, 'imoveis', IMOVEL), { [CAMPO]: serverTimestamp() }),
    );
  });

  await verifica('o interessado NAO desliga o proprio relogio', async () => {
    // desligar e dizer "fui respondida"; quem responde e o dono
    await assertFails(
      updateDoc(doc(anaDb, 'imoveis', IMOVEL), { [CAMPO]: deleteField() }),
    );
  });

  await verifica('o interessado NAO muda mais nada do anuncio junto', async () => {
    await desligarRelogio();
    await assertFails(
      updateDoc(doc(anaDb, 'imoveis', IMOVEL), {
        [CAMPO]: serverTimestamp(),
        preco: 1,
      }),
    );
    await assertFails(updateDoc(doc(anaDb, 'imoveis', IMOVEL), { titulo: 'sequestrado' }));
  });

  await verifica('o dono continua editando e apagando so o anuncio dele', async () => {
    await assertSucceeds(updateDoc(doc(brunoDb, 'imoveis', IMOVEL), { preco: 1000 }));
    await assertFails(updateDoc(doc(anaDb, 'imoveis', OUTRO_IMOVEL), { preco: 1000 }));
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
