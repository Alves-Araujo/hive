// Testes das regras do firestore para as conversas.
//
// Estes testes existem por causa de um vazamento real: a regra era
// "allow read: if request.auth != null", entao qualquer pessoa logada lia a
// conversa de qualquer outra. O que garante a privacidade agora e o
// documento pai chats/{id} e o campo participantes dele -- e isso nao da pra
// conferir no aparelho, so aqui, chamando o firestore como um estranho faria.
//
// Rodar com:
//   npx firebase emulators:exec --only firestore --project moradias-inatel \
//     "node test/rules/chats.test.mjs"
// (a partir da pasta moradia_app)

import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, addDoc, collection, getDocs, query, where, serverTimestamp } from 'firebase/firestore';

const ANA = 'uidAna';
const BRUNO = 'uidBruno';     // dono do anuncio
const CARLA = 'uidCarla';     // estranho: nao participa de nada
const IMOVEL = 'imovel123';

// o id derivado dos participantes, em ordem -- o mesmo que gerarIdChat()
// monta no app (lib/models/chat.dart) e que idDerivado() remonta na regra
const ordenar = (a, b) => [a, b].sort();
const idChat = (imovelId, a, b) => {
  const [p0, p1] = ordenar(a, b);
  return `${imovelId === '' ? 'direto' : imovelId}_${p0}_${p1}`;
};

const CHAT_ANA_BRUNO = idChat(IMOVEL, ANA, BRUNO);
const CHAT_CARLA_BRUNO = idChat(IMOVEL, CARLA, BRUNO);
const CHAT_DIRETO = idChat('', ANA, BRUNO);

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

// perfilCompleto() na regra le usuarios/{uid}.perfilCompleto, e a conversa so
// abre pra quem completou o cadastro -- entao os dados de apoio entram com as
// regras desligadas, como o app ja teria gravado
async function prepararDados() {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    for (const uid of [ANA, BRUNO, CARLA]) {
      await setDoc(doc(db, 'usuarios', uid), { perfilCompleto: true });
    }
    // conversa da Ana com o dono do anuncio
    await setDoc(doc(db, 'chats', CHAT_ANA_BRUNO), {
      participantes: ordenar(ANA, BRUNO),
      imovelId: IMOVEL,
      imovelTitulo: 'Kitnet perto da facul',
      ultimaMensagem: 'Ainda esta disponivel?',
    });
    await addDoc(collection(db, 'chats', CHAT_ANA_BRUNO, 'mensagens'), {
      tipo: 'texto',
      texto: 'Ainda esta disponivel?',
      remetenteUid: ANA,
    });
    // conversa da Carla com o MESMO dono, no MESMO anuncio
    await setDoc(doc(db, 'chats', CHAT_CARLA_BRUNO), {
      participantes: ordenar(CARLA, BRUNO),
      imovelId: IMOVEL,
      imovelTitulo: 'Kitnet perto da facul',
      ultimaMensagem: 'Aceita negociar?',
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

  const anaDb = env.authenticatedContext(ANA).firestore();
  const brunoDb = env.authenticatedContext(BRUNO).firestore();
  const carlaDb = env.authenticatedContext(CARLA).firestore();
  const deslogadoDb = env.unauthenticatedContext().firestore();

  // --- o vazamento relatado ---------------------------------------------

  await verifica('estranho NAO le as mensagens de uma conversa alheia', async () => {
    await assertFails(getDocs(collection(carlaDb, 'chats', CHAT_ANA_BRUNO, 'mensagens')));
  });

  await verifica('estranho NAO le o documento da conversa alheia', async () => {
    await assertFails(getDoc(doc(carlaDb, 'chats', CHAT_ANA_BRUNO)));
  });

  await verifica('quem nao entrou na conta NAO le nada', async () => {
    await assertFails(getDocs(collection(deslogadoDb, 'chats', CHAT_ANA_BRUNO, 'mensagens')));
  });

  await verifica('a caixa de entrada so traz as minhas conversas', async () => {
    // e a consulta que a tela faz de verdade (ChatService.conversasDe)
    const minhas = await assertSucceeds(
      getDocs(query(collection(carlaDb, 'chats'), where('participantes', 'array-contains', CARLA))),
    );
    const ids = minhas.docs.map((d) => d.id);
    assert.deepEqual(ids, [CHAT_CARLA_BRUNO], `a Carla deveria ver so a conversa dela, veio: ${ids}`);
  });

  await verifica('listar a colecao de conversas sem filtro e negado', async () => {
    await assertFails(getDocs(collection(carlaDb, 'chats')));
  });

  await verifica('nao da pra listar as conversas de outra pessoa', async () => {
    await assertFails(
      getDocs(query(collection(carlaDb, 'chats'), where('participantes', 'array-contains', ANA))),
    );
  });

  // --- quem participa continua usando o app normalmente -------------------

  await verifica('participante le as mensagens da propria conversa', async () => {
    await assertSucceeds(getDocs(collection(anaDb, 'chats', CHAT_ANA_BRUNO, 'mensagens')));
  });

  await verifica('o dono le as duas conversas do anuncio, cada uma na sua', async () => {
    await assertSucceeds(getDocs(collection(brunoDb, 'chats', CHAT_ANA_BRUNO, 'mensagens')));
    await assertSucceeds(getDocs(collection(brunoDb, 'chats', CHAT_CARLA_BRUNO, 'mensagens')));
  });

  await verifica('participante manda mensagem', async () => {
    await assertSucceeds(
      addDoc(collection(anaDb, 'chats', CHAT_ANA_BRUNO, 'mensagens'), {
        tipo: 'texto',
        texto: 'Bom dia!',
        remetenteUid: ANA,
        timestamp: serverTimestamp(),
      }),
    );
  });

  await verifica('estranho NAO manda mensagem em conversa alheia', async () => {
    await assertFails(
      addDoc(collection(carlaDb, 'chats', CHAT_ANA_BRUNO, 'mensagens'), {
        tipo: 'texto',
        texto: 'oi',
        remetenteUid: CARLA,
        timestamp: serverTimestamp(),
      }),
    );
  });

  await verifica('ninguem assina mensagem com o uid de outra pessoa', async () => {
    await assertFails(
      addDoc(collection(anaDb, 'chats', CHAT_ANA_BRUNO, 'mensagens'), {
        tipo: 'texto',
        texto: 'mensagem forjada',
        remetenteUid: BRUNO,
        timestamp: serverTimestamp(),
      }),
    );
  });

  await verifica('mensagem enviada nao pode ser reescrita nem apagada', async () => {
    const existentes = await getDocs(collection(anaDb, 'chats', CHAT_ANA_BRUNO, 'mensagens'));
    const alvo = existentes.docs[0];
    await assertFails(
      setDoc(doc(anaDb, 'chats', CHAT_ANA_BRUNO, 'mensagens', alvo.id), { texto: 'outra coisa' }),
    );
  });

  // --- criar conversa ------------------------------------------------------

  await verifica('da pra comecar uma conversa nova', async () => {
    const novo = idChat('', ANA, CARLA);
    await assertSucceeds(
      setDoc(doc(anaDb, 'chats', novo), {
        participantes: ordenar(ANA, CARLA),
        ultimaMensagem: 'oi',
        atualizadoEm: serverTimestamp(),
      }),
    );
  });

  await verifica('NAO da pra criar conversa em que eu nao entro', async () => {
    const alheia = idChat('', BRUNO, CARLA);
    await assertFails(
      setDoc(doc(anaDb, 'chats', alheia), {
        participantes: ordenar(BRUNO, CARLA),
        atualizadoEm: serverTimestamp(),
      }),
    );
  });

  await verifica('NAO da pra criar conversa com id fora do formato derivado', async () => {
    // e o que trancaria de novo o historico antigo: o chat de anuncio tinha
    // o imovelId como id, e bastaria criar esse pai pra reabrir tudo
    await assertFails(
      setDoc(doc(carlaDb, 'chats', IMOVEL), {
        participantes: ordenar(CARLA, BRUNO),
        imovelId: IMOVEL,
        atualizadoEm: serverTimestamp(),
      }),
    );
  });

  await verifica('NAO da pra criar conversa com mais de duas pessoas', async () => {
    await assertFails(
      setDoc(doc(anaDb, 'chats', `direto_${ANA}_${BRUNO}_${CARLA}`), {
        participantes: [ANA, BRUNO, CARLA],
        atualizadoEm: serverTimestamp(),
      }),
    );
  });

  await verifica('NAO da pra entrar numa conversa trocando os participantes', async () => {
    await assertFails(
      setDoc(
        doc(carlaDb, 'chats', CHAT_ANA_BRUNO),
        { participantes: ordenar(CARLA, BRUNO) },
        { merge: true },
      ),
    );
  });

  await verifica('participante atualiza a previa da conversa', async () => {
    await assertSucceeds(
      setDoc(
        doc(anaDb, 'chats', CHAT_ANA_BRUNO),
        {
          participantes: ordenar(ANA, BRUNO),
          ultimaMensagem: 'Bom dia!',
          atualizadoEm: serverTimestamp(),
        },
        { merge: true },
      ),
    );
  });

  // --- perfil incompleto ---------------------------------------------------

  await verifica('quem nao completou o perfil nao manda mensagem', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'usuarios', ANA), { perfilCompleto: false });
    });
    await assertFails(
      addDoc(collection(anaDb, 'chats', CHAT_ANA_BRUNO, 'mensagens'), {
        tipo: 'texto',
        texto: 'oi',
        remetenteUid: ANA,
        timestamp: serverTimestamp(),
      }),
    );
    // mas continua LENDO a conversa em que ja esta
    await assertSucceeds(getDocs(collection(anaDb, 'chats', CHAT_ANA_BRUNO, 'mensagens')));
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
