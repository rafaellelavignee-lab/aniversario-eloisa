# 🦋 Plataforma 15 Anos da Eloisa — Guia Completo

---

## 1. Análise da Arquitetura Atual

O sistema original é um único `index.html` que:
- Armazena tudo em um único objeto JSON (`state`) em uma tabela `festas` com id=1
- Carece de autenticação — qualquer pessoa com a URL tem acesso total
- Salva fotos como Base64 dentro do JSON do Supabase (ineficiente e com limite de tamanho)
- Faz polling a cada 2 segundos para sincronização entre abas/dispositivos
- Não possui separação de perfis de usuário nem permissões

---

## 2. Problemas Identificados

| Problema | Impacto |
|----------|---------|
| Sem autenticação | Qualquer pessoa acessa o painel |
| Tudo em JSON único | Conflitos ao editar simultaneamente |
| Fotos em Base64 | Limite de ~1MB por foto, performance ruim |
| Sem RSVP | Confirmação manual por WhatsApp |
| Sem controle de usuários | Impossível saber quem adicionou o quê |
| Polling a cada 2s | Queries desnecessárias no Supabase |

---

## 3. Arquitetura Nova

### Arquivos entregues

```
eloisa-plataforma/
├── setup.sql        → SQL completo (tabelas, RLS, Storage, triggers)
├── login.html       → Página de autenticação
├── index.html       → Painel administrativo completo
├── rsvp.html        → Confirmação pública de presença
└── convite.html     → Convite público dos convidados
```

### Fluxo de acesso

```
Administrador/Colaborador → login.html → index.html
Convidado (RSVP)          → rsvp.html?token=TOKEN
Convidado (Convite)       → convite.html?token=TOKEN
```

---

## 4. Estrutura Final do Banco de Dados

### configuracoes
| Campo | Tipo | Descrição |
|-------|------|-----------|
| id | INTEGER | Sempre 1 (singleton) |
| data_festa | DATE | Data do evento |
| local_festa | TEXT | Nome do espaço |
| horario | TEXT | Ex: "19h às 00h" |
| tema | TEXT | Tema da festa |
| mensagem_especial | TEXT | Aparece no convite |
| foto_principal_url | TEXT | URL da foto de capa |

### usuarios
| Campo | Tipo | Descrição |
|-------|------|-----------|
| id | UUID | FK para auth.users |
| nome | TEXT | Nome de exibição |
| email | TEXT | E-mail único |
| tipo | TEXT | 'admin' ou 'colaborador' |
| criado_em | TIMESTAMPTZ | Data de cadastro |

### convidados
| Campo | Tipo | Descrição |
|-------|------|-----------|
| id | UUID | Gerado automaticamente |
| nome | TEXT | Nome do convidado |
| status | TEXT | confirmado / aguardando / cancelado |
| criado_por | TEXT | Nome do usuário que cadastrou |
| criado_por_id | UUID | ID do usuário que cadastrou |
| criado_em | TIMESTAMPTZ | Data de cadastro |
| token_rsvp | TEXT | Token único para link de RSVP |
| resposta_rsvp | TEXT | 'confirmado' ou 'recusado' |
| data_resposta | TIMESTAMPTZ | Quando o convidado respondeu |

### checklists
| Campo | Tipo | Descrição |
|-------|------|-----------|
| id | UUID | Gerado automaticamente |
| tipo | TEXT | food / decor / music / looks / vendors / tasks |
| texto | TEXT | Descrição do item |
| concluido | BOOLEAN | Status |
| criado_em | TIMESTAMPTZ | Data |

### orcamentos
| Campo | Tipo | Descrição |
|-------|------|-----------|
| id | UUID | Gerado automaticamente |
| nome | TEXT | Nome do item |
| valor | NUMERIC | Valor em R$ |
| categoria | TEXT | Ex: Decoração, Buffet |
| responsavel | TEXT | Nome do responsável |
| status | TEXT | 'pendente' ou 'pago' |

### presentes
| Campo | Tipo | Descrição |
|-------|------|-----------|
| id | UUID | Gerado automaticamente |
| nome | TEXT | Nome do presente |
| descricao | TEXT | Breve descrição |
| imagem_url | TEXT | URL no Supabase Storage |
| link_compra | TEXT | Link externo de compra |
| reservado | BOOLEAN | Se já foi escolhido |
| reservado_por | TEXT | Nome (sem revelar publicamente) |

### fotos
| Campo | Tipo | Descrição |
|-------|------|-----------|
| id | UUID | Gerado automaticamente |
| titulo | TEXT | Título opcional |
| legenda | TEXT | Legenda opcional |
| url | TEXT | URL no Supabase Storage |
| bucket | TEXT | Nome do bucket usado |
| visibilidade | TEXT | 'public' ou 'private' |
| criado_por | UUID | FK para auth.users |
| criado_em | TIMESTAMPTZ | Data de upload |

### notas / playlist
Tabelas singleton (id=1) com campos de texto simples.

---

## 5. RLS — Matriz de Permissões

| Tabela | Público | Colaborador | Admin |
|--------|---------|-------------|-------|
| configuracoes | Leitura | Leitura | Total |
| usuarios | — | Leitura | Total |
| convidados | Via token | Total | Total |
| checklists | — | Total | Total |
| orcamentos | — | Total | Total |
| presentes | Leitura + Reserva | Total | Total |
| fotos (public) | Leitura | Total | Total |
| fotos (private) | — | Total | Total |
| notas | — | Total | Total |
| playlist | Leitura | Total | Total |

---

## 6. Supabase Storage

| Bucket | Público | Tamanho máx | Uso |
|--------|---------|-------------|-----|
| fotos-publicas | ✅ Sim | 5 MB | Fotos do convite |
| fotos-privadas | ❌ Não | 5 MB | Fotos internas |
| presentes | ✅ Sim | 3 MB | Imagens dos presentes |

---

## 7. Funções de Banco (SECURITY DEFINER)

### `responder_rsvp(token, resposta)`
Permite que o convidado confirme presença sem estar autenticado.
Chamada via: `_sb.rpc('responder_rsvp', { p_token, p_resposta })`

### `reservar_presente(id, nome)`
Permite que o convidado reserve um presente sem estar autenticado.
Chamada via: `_sb.rpc('reservar_presente', { p_id, p_nome })`

### `get_user_tipo(uid)`
Usada pelas políticas RLS para verificar se o usuário é admin.

---

## 8. Funcionalidades Implementadas

### login.html
- Login com e-mail e senha
- Recuperação de senha por e-mail
- Redirecionamento automático se já logado
- Mensagens de erro em português
- Design idêntico ao painel

### index.html (Painel Admin)
- **Auth guard:** redireciona para login.html se sem sessão
- **Navegação por abas:** Dashboard, Convidados, Checklist, Orçamento, Presentes, Galeria, Playlist, Config, Usuários
- **Dashboard:** 9 indicadores + countdown + barra de progresso
- **Convidados:** filtros por status/responsável, link RSVP copiável, histórico de quem adicionou
- **Checklist:** 6 categorias com opções rápidas
- **Orçamento:** categorias, responsável, status pago/pendente, totais
- **Presentes:** cards com upload de imagem, link de compra, reserva
- **Galeria:** upload para Supabase Storage, lightbox, visibilidade pública/privada
- **Playlist:** Spotify + YouTube + Deezer
- **Config:** dados da festa + notas com autosave (2s debounce)
- **Usuários (admin):** criar, listar, alterar tipo, excluir

### rsvp.html
- Acesso por `?token=TOKEN` sem autenticação
- Detecta resposta anterior e exibe mensagem adequada
- Chama RPC `responder_rsvp` para update seguro
- 5 estados visuais: loading, erro, formulário, já respondeu, confirmado, recusado

### convite.html
- Acesso por `?token=TOKEN` sem autenticação
- Mostra dados da festa, countdown em tempo real
- Lista de presentes com botão de reserva
- Galeria de fotos públicas
- Links de playlist
- Botão de confirmação de presença

---

## 9. Passo a Passo de Implantação

### Etapa 1 — Supabase (1 vez)

1. Acesse https://supabase.com → seu projeto
2. Vá em **SQL Editor**
3. Cole e execute o conteúdo de `setup.sql`
4. Vá em **Authentication → Providers → Email** → confirme que está habilitado
5. Vá em **Authentication → Settings** → desative "Confirm email" se quiser teste rápido

### Etapa 2 — Criar primeiro usuário Admin

No SQL Editor, execute:
```sql
-- 1. Crie o usuário pelo painel: Authentication → Users → Add User
-- 2. Depois execute para torná-lo admin:
UPDATE usuarios SET tipo = 'admin' WHERE email = 'seu@email.com';
```

### Etapa 3 — Verificar chave Supabase

A chave atual nos arquivos começa com `sb_publishable_...`. Confirme em:
**Settings → API → Project API keys → anon/public**

Se o formato for `eyJ...`, atualize os 5 arquivos HTML na constante `SUPABASE_ANON_KEY`.

### Etapa 4 — Deploy

Opção A — Vercel (recomendado):
```bash
# Suba os 5 arquivos HTML para um repositório GitHub
# Conecte ao Vercel → New Project → importe o repo
# Deploy automático em cada push
```

Opção B — Netlify:
```bash
# Arraste a pasta eloisa-plataforma para netlify.com/drop
```

Opção C — GitHub Pages:
```bash
git init
git add .
git commit -m "plataforma eloisa 15 anos"
git remote add origin https://github.com/SEU_USUARIO/eloisa-15
git push -u origin main
# Ative Pages em Settings → Pages
```

### Etapa 5 — Testar

1. Acesse `login.html` → entre com o admin
2. Configure a data da festa em **⚙️ Config**
3. Adicione um convidado → copie o link RSVP → teste em aba anônima
4. Adicione um presente → acesse `convite.html?token=TOKEN` → reserve

---

## 10. Links por Contexto

| Página | URL | Quem acessa |
|--------|-----|-------------|
| Login | `/login.html` | Admin e Colaborador |
| Painel | `/index.html` | Admin e Colaborador (com sessão) |
| RSVP | `/rsvp.html?token=TOKEN` | Convidado (link enviado por WhatsApp) |
| Convite | `/convite.html?token=TOKEN` | Convidado (link enviado por WhatsApp) |

O TOKEN de cada convidado aparece na lista do painel ao clicar em 🔗.

---

## 11. Observações Técnicas

- **Chave Supabase:** o formato `sb_publishable_...` pode ser um novo padrão da Supabase (pós-2024). Se der erro, confirme no Dashboard.
- **Criação de usuários pelo painel de Usuários:** usa `signUp` para criar a conta no Auth + o trigger cria automaticamente o perfil na tabela `usuarios`. Após criação, o usuário precisa fazer login pela primeira vez.
- **Fotos privadas:** o bucket é privado, mas a URL retornada pode ser pública se a política não estiver aplicada. Confirme as policies do Storage no Dashboard.
- **Reserva de presentes:** usa RPC com SECURITY DEFINER — o público não consegue fazer UPDATE direto, apenas chamar a função com os parâmetros esperados.
- **RSVP:** mesma proteção via RPC — a função só atualiza `resposta_rsvp` e `data_resposta`, não permite alterar outros campos.
