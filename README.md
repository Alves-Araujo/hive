<p align="center">
  <img src="./assets/banner.svg" width="100%" alt="Hive" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-0D1117?style=for-the-badge&logo=flutter&logoColor=02569B" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-0D1117?style=for-the-badge&logo=dart&logoColor=0175C2" alt="Dart" />
  <img src="https://img.shields.io/badge/Firebase-0D1117?style=for-the-badge&logo=firebase&logoColor=FFCA28" alt="Firebase" />
  <img src="https://img.shields.io/badge/Google_Maps-0D1117?style=for-the-badge&logo=googlemaps&logoColor=4285F4" alt="Google Maps" />
  <img src="https://img.shields.io/badge/Android-0D1117?style=for-the-badge&logo=android&logoColor=3DDC84" alt="Android" />
</p>

O **Hive** resolve um problema concreto de cidade universitária: encontrar moradia perto da faculdade é lento, espalhado por grupos de WhatsApp e sem garantia nenhuma de quem está do outro lado. O app reúne isso num mapa, com perfis distintos para cada lado da negociação e comunicação direta dentro da própria plataforma.

---

## ✨ Funcionalidades

**Busca e descoberta**
- Mapa interativo com os imóveis disponíveis na região
- Geolocalização do usuário e cálculo de rota até o imóvel
- Busca por endereço com geocodificação
- Modo escuro dedicado do mapa, independente do tema geral do app

**Perfis e confiança**
- Três tipos de conta — estudante, proprietário e corretor — cada um com fluxos próprios
- Login por e-mail/senha ou conta Google
- Sistema de avaliações entre usuários e de imobiliárias
- Vínculo verificado entre corretor e imobiliária
- Anúncio liberado apenas para quem completou o perfil

**Comunicação**
- Chat por imóvel, entre interessado e anunciante
- Envio de fotos e **mensagens de áudio** dentro da conversa
- **Chamada de voz e vídeo** integrada

---

## 🏗️ Arquitetura

O código é organizado por responsabilidade, não por tela:

```
lib/
├── main.dart              # ponto de entrada e inicialização do Firebase
├── firebase_options.dart  # configuração gerada pelo FlutterFire CLI
├── models/                # entidades do domínio (usuário, imóvel, avaliação...)
├── screens/               # telas, uma por fluxo de usuário
├── services/              # acesso a Firestore, Storage, Auth e APIs externas
├── widgets/               # componentes reutilizáveis de interface
└── utils/                 # formatadores, validadores e helpers
```

A regra que mantém isso limpo: **tela não fala com o Firebase direto** — sempre passa por `services/`. Trocar a fonte de dados não obriga a mexer na interface.

---

## 🔒 Segurança

As permissões ficam nas regras do Firebase, versionadas junto com o código em `firestore.rules` e `storage.rules`:

- Dados sensíveis (CPF, endereço, telefone) só são lidos e escritos pelo próprio dono
- Perfil público separado do privado, para busca e chat não exporem dado pessoal
- Anúncio só pode ser criado por quem completou o perfil, e só o dono edita ou apaga
- Avaliação não pode ser publicada em nome de outra pessoa
- Upload no chat limitado a 32 MB por arquivo

---

## 🚀 Tecnologias

| Camada | Ferramentas |
|---|---|
| App | Flutter 3.11+ · Dart |
| Autenticação | Firebase Auth · Google Sign-In |
| Banco de dados | Cloud Firestore |
| Arquivos | Firebase Storage |
| Mapas | Google Maps · Geocoding · Geolocator · Polyline Points |
| Mídia | Image Picker · Record · AudioPlayers |
| Chamadas | ZEGOCLOUD UIKit |
| Plataforma | Android |

---

## 🛠️ Como executar

**Pré-requisitos:** Flutter 3.11 ou superior e um projeto Firebase próprio.

**1.** Clone o repositório:

```bash
git clone https://github.com/Alves-Araujo/hive.git
cd hive
```

**2.** Instale as dependências:

```bash
flutter pub get
```

**3.** Configure seu próprio Firebase — as credenciais deste repositório apontam para o projeto original:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

**4.** Adicione sua chave da API do Google Maps em `android/app/src/main/AndroidManifest.xml`.

**5.** Publique as regras de segurança no seu projeto:

```bash
firebase deploy --only firestore:rules,storage:rules
```

**6.** Rode o app:

```bash
flutter run
```

---

## 📌 Status

Em desenvolvimento ativo. Rodando em **Android**; a build para iOS ainda não foi configurada (falta a chave do Maps no AppDelegate e o `GoogleService-Info.plist`). A estrutura de monitorias já está preparada nas regras, mas ainda não foi implementada na interface.

---
