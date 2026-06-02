# iridium-buddy-dashboard

Dashboard UGC do cliente (Buddy Nutrition + Iridium Labs). Single-file estático, **hospedado no Vercel**, atualizado **a cada 4 horas** (6x ao dia) por uma scheduled task que roda no Cowork.

**URL pública**: https://iridium-buddy-dashboard-git-main-srocha-inbazzcombs-projects.vercel.app

## Como funciona em 30s

```
[Scheduled task no Cowork] ──a cada 4h──>  Supabase MCP (queries)
                                                    │
                                                    ▼
                                  preserva historico, gera data/dashboard.json
                                                    │
                                                    ▼
                                          git commit + push em main
                                                    │
                                                    ▼
                                          Vercel re-publica (~30s)
                                                    │
                                                    ▼
                                       URL acima fica atualizada
```

Sem build, sem framework, sem backend. O dashboard mostra "Atualizado a cada 4h · DD/MM HH:MM" no header — quando o cliente abrir e a data parecer velha, é porque a task falhou (raro).

---

## 1. Estrutura

```
index.html              ← versão dark (default no /)
index_inbazz.html       ← versão paleta Inbazz light
data/
  dashboard.json        ← snapshot atual + histórico (gerado pela task)
  farmers.json          ← lista canônica de farmers + metas (editado por você)
scheduled-task/
  SKILL.md              ← skill da task de refresh
amplify.yml             ← legado (pode ignorar; Vercel é o host vivo)
README.md
```

---

## 2. Hospedagem (Vercel)

Já configurada e rodando. Projeto: `iridium-buddy-dashboard` no team `srocha-inbazzcombs-projects`.

**URLs:**
- Estável (sempre o último deploy de main): https://iridium-buddy-dashboard-git-main-srocha-inbazzcombs-projects.vercel.app
- Versão Inbazz light: adiciona `/index_inbazz.html`
- Dashboard Vercel: https://vercel.com/srocha-inbazzcombs-projects/iridium-buddy-dashboard

**Auto-deploy:** cada push em `main` faz Vercel reconstruir em ~30s. Não tem build step — é static hosting puro.

### 2.1 Servir pra outra organização (cliente)

Cloudflare Pages ou Vercel com Cloudflare Access oferecem autenticação grátis. Configuração de proteção fica em Vercel Project Settings → Deployment Protection.

### 2.2 (opcional) Domínio próprio

Vercel → Project Settings → Domains → adiciona `dashboard.<seu-dominio>.com.br`. Configurar CNAME no DNS apontando pra `cname.vercel-dns.com`.

---

## 3. Refresh automático (scheduled task)

A task `refresh-dashboard-iridium` roda no Cowork a cada 4h (cron `0 */4 * * *` em horário local BRT — 00, 04, 08, 12, 16, 20).

### 3.1 PAT do GitHub

Já gerado e salvo em `~/.claude/secrets/github_pat_iridium.md` (chmod 600). Quando expirar (~90d-1ano), gerar novo em https://github.com/settings/personal-access-tokens/new com escopo `Contents: write` no repo, substituir o arquivo.

### 3.2 Editar a task

Na sidebar do Cowork → **Scheduled** → `refresh-dashboard-iridium`. Pra ver/editar o prompt, abre o `SKILL.md` da task (path em `~/Claude/Scheduled/refresh-dashboard-iridium/SKILL.md`).

### 3.3 Run manual

Mesmo lugar (Scheduled), clica **Run now** na task. Útil pra:
- Pré-aprovar permissões (Supabase MCP, bash, git push)
- Forçar atualização imediata
- Testar mudança na SKILL.md

---

## 4. Editar farmers e metas

Edita `data/farmers.json` direto no GitHub web (botão ✏️) **OU** local + `git push`. Próximo run da task pega automaticamente.

**Adicionar farmer novo**: Roberto/Jessica criaram tag `pedro` no Supabase pra os creators dele? Adicione `pedro` em `marcas.buddy.farmers_tags` e `pedro: "Pedro"` em `farmer_display_names`. Pronto.

**Mudar meta do mês**: editar `metas_mensais.buddy["2026-07"] = 90000` etc. Se faltar a meta de um mês, o card mostra "Sem meta definida".

---

## 5. Filtro de mês (atual + histórico)

No header tem um **dropdown ao lado do seletor de marca**. Permite alternar entre:

- **Atual · {mês corrente}** — dado parcial do mês em andamento. Quando `diaAtual <= 3`, badges MoM mostram "início do mês" em vez de % absurdo.
- **{Mês anterior} (fechado)** — snapshot do mês fechado completo, com MoM real e badge "MÊS FECHADO · HISTÓRICO" no header.

O histórico é cumulativo: cada vez que o mês vira, a task arquiva o snapshot do mês fechado em `dashboard.json → historico[YYYY-MM]`. Sem perda de dado.

---

## 6. Alternativas de host (referência)

| Host | Custo | Repo privado | Auth nativa |
|---|---|---|---|
| **Vercel** (atual) | grátis | sim | só pago |
| Cloudflare Pages | grátis | sim | **Cloudflare Access grátis** |
| Netlify | grátis | sim | Identity (~50 users) |
| AWS Amplify | grátis no Free Tier | sim | basic auth |
| GitHub Pages | grátis | só Pro/Team | — |

Pra qualquer um: conecta o repo, branch `main`, sem build step.

---

## 7. Troubleshooting

**"undefined" em algum card**: campo do JSON foi renomeado pelo pipeline. Já temos helper que aceita `prospeccoes_total` OU `leads_no_mes`. Se aparecer outro `undefined`, abrir DevTools → Console → ver qual campo.

**Data parou de atualizar**: a scheduled task falhou. Checar logs em Cowork → Scheduled → último run.

**MoM "início do mês" persistente**: cutoff dispara só quando `activeMes === 'atual' && diaAtual <= 3`. Se persistir após dia 4, regenerar JSON via Run now.

**Dados não batem com o admin Inbazz**: ver `meta.geradoEm` (timestamp do último snapshot). Se for de horas atrás, espera próximo run; se muito antigo, abrir issue.

**Vercel 403/Forbidden**: deployment protection do team está ligado. Settings → Deployment Protection → desativar Standard Protection OU gerar Shareable Link.

**Filtro de mês não mostra histórico**: o `dashboard.json` não tem o bucket `historico`. Ocorre se a task rodou e sobrescreveu sem preservar. SKILL.md atual tem instrução explícita, mas se acontecer, recuperar do git history (`git show <commit>:data/dashboard.json`).
