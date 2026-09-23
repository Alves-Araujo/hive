// Testes das regras do firestore para o que o relatorio de bugs pediu pra
// travar no BACKEND, e nao so na tela:
//
// - a categoria do anuncio (moradia/evento) nao muda depois de publicado
// - tipo de conta (e subtipo do corretor) nao muda depois do cadastro
// - so quem responde pela imobiliaria aprova/recusa um corretor dela
// - imobiliaria so nasce COM DONO (donoUid), e o dono e quem esta cadastrando
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
import { doc, setDoc, updateDoc, deleteField } from 'firebase/firestore';

const DONO = 'uidDono';           // publicou o anuncio
const ESTRANHO = 'uidEstranho';
const CORRETOR = 'uidCorretor';   // pediu vinculo com a imobiliaria
const IMOBILIARIA = 'imob1';
const IMOBILIARIA_SEM_EMAIL = 'imob2';
const EMAIL_IMOBILIARIA = 'contato@imobiliaria.com';
const ANUNCIO = 'anuncio1';

// a conta master de uma imobiliaria cadastrada do jeito novo: o uid dela esta
// gravado em donoUid, e e SO isso que prova que ela responde pela empresa -- o
// e-mail do cadastro e outro, de proposito, pra separar os dois criterios
const MASTER = 'uidMaster';
const EMAIL_MASTER = 'master@pessoal.com';
const IMOBILIARIA_COM_DONO = 'imob3';
const CORRETOR_DA_COM_DONO = 'uidCorretor2';

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
      papelImobiliaria: 'equipe',
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

    // cadastro antigo, gravado antes de existir emailBusca: ninguem responde
    // por ele, entao ninguem edita (conta sem e-mail no token nao pode casar
    // com o campo vazio)
    await setDoc(doc(db, 'imobiliarias', IMOBILIARIA_SEM_EMAIL), {
      nome: 'Imobiliária Sem Dono',
    });

    // cadastro novo: tem dono. O e-mail gravado nao e o da conta master, pra
    // deixar claro que quem manda aqui e o donoUid, sozinho
    await setDoc(doc(db, 'imobiliarias', IMOBILIARIA_COM_DONO), {
      donoUid: MASTER,
      nome: 'Imobiliária da Master',
      cnpj: '11.222.333/0001-44',
      cnpjBusca: '11222333000144',
      emailBusca: 'outro@endereco.com',
      emailVerificado: true,
    });

    await setDoc(doc(db, 'perfisPublicos', CORRETOR), {
      nome: 'Corretor Silva',
      tipoUsuario: 'corretor',
      subtipoCorretor: 'empresa',
      papelImobiliaria: 'equipe',
      imobiliariaId: IMOBILIARIA,
      vinculoConfirmado: false,
      vinculoRecusado: false,
    });

    await setDoc(doc(db, 'perfisPublicos', CORRETOR_DA_COM_DONO), {
      nome: 'Corretora Souza',
      tipoUsuario: 'corretor',
      subtipoCorretor: 'empresa',
      papelImobiliaria: 'equipe',
      imobiliariaId: IMOBILIARIA_COM_DONO,
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

  // a conta master de IMOBILIARIA_COM_DONO -- o e-mail dela nao e o que esta
  // gravado no cadastro, entao so o donoUid responde por ela aqui
  const masterDb = env
    .authenticatedContext(MASTER, {
      email: EMAIL_MASTER,
      email_verified: true,
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

  // --- a imobiliaria edita o proprio cadastro ------------------------------
  //
  // Antes nao havia caminho nenhum: trocar o nome da empresa exigia abrir
  // outra conta, e os corretores ja vinculados continuavam no cadastro velho

  await verifica('a imobiliaria edita o proprio nome, descricao e telefone', async () => {
    await assertSucceeds(
      updateDoc(doc(imobiliariaDb, 'imobiliarias', IMOBILIARIA), {
        nome: 'Imobiliária Central Ltda',
        nomeBusca: 'imobiliaria central ltda',
        descricao: 'Aluguel de kitnets perto do campus',
        telefone: '(35) 99999-0000',
      }),
    );
  });

  await verifica('e tambem a galeria de fotos do escritorio', async () => {
    await assertSucceeds(
      updateDoc(doc(imobiliariaDb, 'imobiliarias', IMOBILIARIA), {
        fotos: ['https://i.ibb.co/escritorio1.jpg', 'https://i.ibb.co/escritorio2.jpg'],
      }),
    );
  });

  await verifica('e tambem a foto, o endereco e a coordenada do pin', async () => {
    await assertSucceeds(
      updateDoc(doc(imobiliariaDb, 'imobiliarias', IMOBILIARIA), {
        fotoUrl: 'https://i.ibb.co/foto.jpg',
        endereco: 'Rua Nova, 100, Centro, Santa Rita do Sapucaí - MG',
        latitude: -22.25,
        longitude: -45.7,
      }),
    );
  });

  // Os dois de cima mandam um pedaco do formulario por vez; a tela manda o
  // bloco INTEIRO num update so (ImobiliariaService.atualizarPerfil), inclusive
  // quando nada mudou de valor. E esse payload que precisa passar -- foi o que
  // voltou com permission-denied no aparelho enquanto as regras nao subiram
  await verifica('o payload inteiro da tela passa de uma vez', async () => {
    await assertSucceeds(
      updateDoc(doc(imobiliariaDb, 'imobiliarias', IMOBILIARIA), {
        nome: 'Imobiliária Central Ltda',
        nomeBusca: 'imobiliaria central ltda',
        descricao: 'Aluguel de kitnets perto do campus',
        telefone: '(35) 99999-0000',
        fotoUrl: 'https://i.ibb.co/foto.jpg',
        fotos: ['https://i.ibb.co/escritorio1.jpg'],
        endereco: 'Rua Nova, 100, Centro, Santa Rita do Sapucaí - MG',
      }),
    );
  });

  // endereco novo que o geocoder nao reconhece: a tela APAGA a coordenada (sai
  // do mapa ate ser corrigido) em vez de deixar o pin no escritorio antigo
  await verifica('endereco novo sem coordenada apaga o pin', async () => {
    await assertSucceeds(
      updateDoc(doc(imobiliariaDb, 'imobiliarias', IMOBILIARIA), {
        nome: 'Imobiliária Central Ltda',
        nomeBusca: 'imobiliaria central ltda',
        descricao: 'Aluguel de kitnets perto do campus',
        telefone: '(35) 99999-0000',
        fotoUrl: 'https://i.ibb.co/foto.jpg',
        endereco: 'Endereço que o geocoder não reconhece',
        latitude: deleteField(),
        longitude: deleteField(),
      }),
    );
  });

  await verifica('quem nao e a imobiliaria NAO edita o cadastro dela', async () => {
    await assertFails(
      updateDoc(doc(estranhoDb, 'imobiliarias', IMOBILIARIA), {
        nome: 'Imobiliária do Estranho',
      }),
    );
  });

  await verifica('com o e-mail dela mas sem confirmar, tambem NAO edita', async () => {
    await assertFails(
      updateDoc(doc(semConfirmarDb, 'imobiliarias', IMOBILIARIA), {
        nome: 'Imobiliária Sequestrada',
      }),
    );
  });

  await verifica('a imobiliaria NAO troca o proprio CNPJ', async () => {
    await assertFails(
      updateDoc(doc(imobiliariaDb, 'imobiliarias', IMOBILIARIA), {
        cnpj: '12.345.678/0001-99',
        cnpjBusca: '12345678000199',
      }),
    );
  });

  await verifica('a imobiliaria NAO troca o e-mail que responde por ela', async () => {
    await assertFails(
      updateDoc(doc(imobiliariaDb, 'imobiliarias', IMOBILIARIA), {
        email: 'outro@dominio.com',
        emailBusca: 'outro@dominio.com',
      }),
    );
  });

  await verifica('editar o cadastro NAO e porta pra se marcar como verificada', async () => {
    await assertFails(
      updateDoc(doc(imobiliariaDb, 'imobiliarias', IMOBILIARIA), {
        nome: 'Imobiliária Central',
        emailVerificado: true,
      }),
    );
  });

  await verifica('a imobiliaria NAO fica sem nome', async () => {
    await assertFails(
      updateDoc(doc(imobiliariaDb, 'imobiliarias', IMOBILIARIA), { nome: '   ' }),
    );
  });

  // conta sem e-mail no token (login por telefone, anonimo) contra cadastro
  // antigo sem emailBusca: os dois lados vazios NAO podem casar
  await verifica('cadastro sem emailBusca nao e editavel por conta sem e-mail', async () => {
    await assertFails(
      updateDoc(doc(estranhoDb, 'imobiliarias', IMOBILIARIA_SEM_EMAIL), {
        nome: 'Tomada de Assalto',
      }),
    );
  });

  // --- a imobiliaria nasce com dono ---------------------------------------
  //
  // O buraco que isto fecha: antes bastava estar logado pra criar, e o e-mail
  // gravado era o DA EMPRESA, digitado no formulario por um corretor qualquer.
  // Como quem mandava na imobiliaria era deduzido desse e-mail, o cadastro
  // nascia sem ninguem por ele -- nem quem criou editava ou aprovava corretor

  await verifica('a conta master cadastra a imobiliaria dela', async () => {
    await assertSucceeds(
      setDoc(doc(masterDb, 'imobiliarias', 'imobNova'), {
        donoUid: MASTER,
        nome: 'Imobiliária Nova',
        nomeBusca: 'imobiliaria nova',
        cnpj: '99.888.777/0001-66',
        cnpjBusca: '99888777000166',
        email: EMAIL_MASTER,
        emailBusca: EMAIL_MASTER,
        emailVerificado: true,
        telefone: '(35) 98888-0000',
        endereco: 'Rua da Sede, 10, Centro, Itajubá - MG',
      }),
    );
  });

  // o payload exato da tela: ela cria com emailVerificado false e liga a
  // confirmacao num update separado, pra passar tambem pela regra que esta
  // publicada hoje (que so aceita create nao confirmado). Os dois passos
  // precisam continuar valendo com a regra nova
  await verifica('o cadastro em dois passos da tela passa inteiro', async () => {
    await assertSucceeds(
      setDoc(doc(masterDb, 'imobiliarias', 'imobDoisPassos'), {
        donoUid: MASTER,
        nome: 'Imobiliária em Dois Passos',
        nomeBusca: 'imobiliaria em dois passos',
        cnpj: '55.444.333/0001-22',
        cnpjBusca: '55444333000122',
        email: EMAIL_MASTER,
        emailBusca: EMAIL_MASTER,
        emailVerificado: false,
        telefone: '(35) 96666-0000',
        endereco: 'Rua da Sede, 30, Centro, Itajubá - MG',
        latitude: -22.25,
        longitude: -45.7,
      }),
    );
    await assertSucceeds(
      updateDoc(doc(masterDb, 'imobiliarias', 'imobDoisPassos'), {
        emailVerificado: true,
      }),
    );
  });

  await verifica('imobiliaria NAO nasce sem dono (o jeito antigo)', async () => {
    await assertFails(
      setDoc(doc(masterDb, 'imobiliarias', 'imobOrfa'), {
        nome: 'Imobiliária Fantasma',
        cnpjBusca: '00111222000133',
        emailBusca: 'contato@fantasma.com',
        emailVerificado: false,
      }),
    );
  });

  await verifica('ninguem cadastra imobiliaria em nome de outra conta', async () => {
    await assertFails(
      setDoc(doc(masterDb, 'imobiliarias', 'imobDeOutro'), {
        donoUid: ESTRANHO,
        nome: 'Imobiliária do Estranho',
        emailBusca: EMAIL_MASTER,
        emailVerificado: false,
      }),
    );
  });

  await verifica('o e-mail do cadastro tem que ser o da propria conta', async () => {
    await assertFails(
      setDoc(doc(masterDb, 'imobiliarias', 'imobComEmailDaEmpresa'), {
        donoUid: MASTER,
        nome: 'Imobiliária Central',
        emailBusca: 'contato@empresa.com',
        emailVerificado: false,
      }),
    );
  });

  await verifica('sem o e-mail confirmado, a imobiliaria nasce pendente', async () => {
    await assertSucceeds(
      setDoc(doc(semConfirmarDb, 'imobiliarias', 'imobPendente'), {
        donoUid: 'uidNaoConfirmado',
        nome: 'Imobiliária Pendente',
        emailBusca: EMAIL_IMOBILIARIA,
        emailVerificado: false,
      }),
    );
  });

  await verifica('e NAO nasce ja confirmada', async () => {
    await assertFails(
      setDoc(doc(semConfirmarDb, 'imobiliarias', 'imobAutoConfirmada'), {
        donoUid: 'uidNaoConfirmado',
        nome: 'Imobiliária Esperta',
        emailBusca: EMAIL_IMOBILIARIA,
        emailVerificado: true,
      }),
    );
  });

  await verifica('a imobiliaria NAO nasce sem nome', async () => {
    await assertFails(
      setDoc(doc(masterDb, 'imobiliarias', 'imobSemNome'), {
        donoUid: MASTER,
        nome: '   ',
        emailBusca: EMAIL_MASTER,
        emailVerificado: false,
      }),
    );
  });

  // --- o dono manda na imobiliaria dele ------------------------------------
  //
  // O e-mail gravado em IMOBILIARIA_COM_DONO e outro: quem responde por ela
  // aqui e o donoUid, sozinho

  await verifica('a conta master edita o cadastro da imobiliaria dela', async () => {
    await assertSucceeds(
      updateDoc(doc(masterDb, 'imobiliarias', IMOBILIARIA_COM_DONO), {
        nome: 'Imobiliária da Master Ltda',
        nomeBusca: 'imobiliaria da master ltda',
        telefone: '(35) 97777-0000',
        endereco: 'Rua Nova da Sede, 20, Centro, Itajubá - MG',
      }),
    );
  });

  await verifica('a conta master aprova o corretor da imobiliaria dela', async () => {
    await assertSucceeds(
      setDoc(
        doc(masterDb, 'perfisPublicos', CORRETOR_DA_COM_DONO),
        { vinculoConfirmado: true },
        { merge: true },
      ),
    );
  });

  await verifica('a conta master NAO aprova corretor de OUTRA imobiliaria', async () => {
    await assertFails(
      setDoc(
        doc(masterDb, 'perfisPublicos', CORRETOR),
        { vinculoConfirmado: true },
        { merge: true },
      ),
    );
  });

  await verifica('quem nao e o dono NAO edita a imobiliaria com dono', async () => {
    await assertFails(
      updateDoc(doc(estranhoDb, 'imobiliarias', IMOBILIARIA_COM_DONO), {
        nome: 'Imobiliária Sequestrada',
      }),
    );
  });

  await verifica('a conta master NAO passa a imobiliaria pra outra conta', async () => {
    await assertFails(
      updateDoc(doc(masterDb, 'imobiliarias', IMOBILIARIA_COM_DONO), {
        donoUid: ESTRANHO,
      }),
    );
  });

  // --- papel na imobiliaria ------------------------------------------------
  //
  // Mesma regra do CPF: vale campo a campo, so trava o que ja esta gravado. Em
  // cadastro antigo (papel vazio) ainda da pra preencher -- e nao muda nada,
  // porque quem manda numa imobiliaria e o donoUid dela, nao este campo

  await verifica('corretor da equipe NAO se promove a admin depois do cadastro', async () => {
    await assertFails(
      updateDoc(doc(corretorDb, 'usuarios', CORRETOR), {
        papelImobiliaria: 'admin',
      }),
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
