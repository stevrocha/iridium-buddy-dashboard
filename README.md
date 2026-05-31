# iridium-buddy-dashboard

Dashboard UGC do cliente (Buddy Nutrition + Iridium Labs). Single-file estático, hospedado no **GitHub Pages**, atualizado **a cada 4 horas** (6x ao dia) por uma scheduled task que roda no Cowork.

## Como funciona em 30s

```
[Scheduled task no Cowork] ──a cada 4h──>  Supabase MCP (query)
                                                              │
                                                              ▼
                                              gera data/dashboard.json
                                                              │
                                                              ▼
                                              git commit + push em main
                                                              │
                                                              ▼
                                              GitHub Pages re-publica (~1 min)
                                                              │
                                                              ▼
                                              https://<user>.github.io/<repo>
```

Sem build, sem framework, sem backend. O dashboard mostra "Atualizado diariamente · DD/MM HH:MM" no header — quando o cliente abrir e a data parecer velha, é porque a task falhou (raro).

---

## 1. Subir pro GitHub (primeira vez)

No terminal, dentro da pasta `Iridium/`:

```bash
git init
git add .
git commit -m "primeira versao do dashboard UGC"
```

Cria o repo no GitHub (vazio, sem README/license, pode ser privado ou público) — sugiro nome `iridium-buddy-dashboard`. Depois:

```bash
git branch -M main
git remote add origin https://github.com/<SEU_USUARIO>/iridium-buddy-dashboard.git
git push -u origin main
```

---

## 2. Ligar o GitHub Pages (hospedagem grátis)

No GitHub, vá em **Settings → Pages**:

1. **Source**: `Deploy from a branch`
2. **Branch**: `main`, pasta `/ (root)`
3. Salvar.

Em ~1 minuto o site fica online em:

```
https://<SEU_USUARIO>.github.io/iridium-buddy-dashboard/
```

A versão Inbazz light fica em `/index_inbazz.html`. A dark fica em `/index.html`.

> **Repo privado + Pages**: GitHub Pages só funciona com repo **público no plano Free**. Pra repo privado, precisa do GitHub Pro/Team ou usar outro host (ver alternativas no fim).

### 2.1 (opcional) Domínio próprio

Settings → Pages → **Custom domain**: insira `dashboard.inbazz.com.br` (ou subdomínio que preferir). Crie um CNAME no DNS apontando pra `<seu_usuario>.github.io`. Habilite "Enforce HTTPS".

---

## 3. Configurar a scheduled task no Cowork (refresh a cada 24h)

A skill da task vive em `scheduled-task/SKILL.md`. Cron: `0 */4 * * *` (00/04/08/12/16/20 BRT, 6x por dia).

### 3.1 Gerar PAT do GitHub

1. GitHub → **Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token**
2. Nome: `iridium-dashboard-refresh`
3. Expiration: 1 ano (lembre de rotacionar)
4. Repository access: **Only select repositories → `iridium-buddy-dashboard`**
5. Repository permissions:
   - **Contents**: Read and write
6. Gerar → copiar o token (começa com `github_pat_...`)

### 3.2 Salvar o PAT no Cowork

Cria o arquivo `~/.claude/secrets/github_pat_iridium.md` na sua máquina com:

```
github_pat_xxxxxxxxxxxxxxxxxxxx
```

A SKILL.md da task lê esse arquivo na hora de fazer o commit.

### 3.3 Criar a scheduled task

No Cowork, peça pra eu (ou outro agente) criar a task:

> "Crie uma scheduled task lendo o SKILL.md em `~/Documents/Claude/Projects/Dashboard Buddy/Iridium/scheduled-task/SKILL.md`. Cron a cada 4 horas (`0 */4 * * *`)."

A task vai rodar todo dia, puxar dados do Supabase via MCP, montar o JSON e commitar em `main`. GitHub Pages re-publica em ~1 minuto.

---

## 4. Editar farmers e metas

Edite `data/farmers.json` no GitHub direto (ou local + push) sempre que:

**Adicionar novo farmer**: novo nome de tag (Roberto/Jessica criaram tag `pedro` no Supabase pra os creators dele) → adicionar `pedro` em `marcas.buddy.farmers_tags` e `pedro: "Pedro"` em `farmer_display_names`. Próximo run da task pega automaticamente.

**Mudar meta do mês**: editar `metas_mensais.buddy.2026-07: 90000` etc. Se faltar, o card mostra "Sem meta definida".

Toda edição em `main` re-publica o dashboard em ~1 min.

---

## 5. Layout do repo

```
index.html              ← versão dark (default no /)
index_inbazz.html       ← versão paleta Inbazz light
data/
  dashboard.json        ← snapshot diário (gerado pela task)
  farmers.json          ← lista canônica de farmers + metas (editado por você)
scheduled-task/
  SKILL.md              ← skill da task de refresh
amplify.yml             ← (legado AWS Amplify; pode ignorar se usar GitHub Pages)
README.md               ← este arquivo
```

---

## 6. Alternativas de host (se não quiser GitHub Pages)

| Host | Custo | Auto-deploy em push | Custom domain | Repo privado |
|---|---|---|---|---|
| **GitHub Pages** | grátis | sim | sim | só com Pro/Team |
| **Cloudflare Pages** | grátis | sim | sim | sim, no Free |
| **Vercel** | grátis (hobby) | sim | sim | sim |
| **AWS Amplify** | grátis (até 1k builds/mês) | sim | sim | sim |
| **Netlify** | grátis | sim | sim | sim |

Pra qualquer um, o fluxo é: conecta o repo, escolhe branch `main`, sem build step (single HTML estático). Ligar e esquecer.

---

## 7. Troubleshooting

**Dashboard sumiu / quebrou após push**: GitHub Pages às vezes leva 5min na primeira vez. Confira em Actions → última `pages build and deployment`.

**Data parou de atualizar**: a scheduled task não rodou ou falhou. Cheque os logs da task no Cowork.

**Dados não batem com o admin**: o `dashboard.json` mostra `meta.geradoEm`. Se for de ontem, espera o run das 10h. Se for de mais tempo, abrir um issue.

**Erro 404 em `/`**: GitHub Pages serve `index.html` por padrão — confira que ele tá na raiz e que Pages aponta pra `/ (root)`.
