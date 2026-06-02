---
name: refresh-dashboard-iridium
description: Atualiza o dashboard de UGC da Inbazz (Buddy + Iridium). Roda a cada 4 horas (00/04/08/12/16/20 BRT).
schedule: "0 */4 * * *"
timezone: America/Sao_Paulo
---

# refresh-dashboard-iridium

Roda **a cada 4 horas**, todos os dias (00:00, 04:00, 08:00, 12:00, 16:00, 20:00 BRT). Pipeline diário com 6 snapshots. Lê dados do **Supabase MCP**, agrega por marca e farmer (mapping vem de tags em `influencer_stores.tags`, normalizadas via trim+lower), monta `dashboard.json` e commita em `main` do repo `stevrocha/iridium-buddy-dashboard`. **AWS Amplify** auto-publica em ~1 minuto.

## Marcas e store_ids

```
Buddy Nutrition  = 1dedd6dc-b11a-448b-9bb8-cf4865237bf8
Iridium Labs     = a688853e-24e2-4eb2-b2b9-e69545aeafc7
```

## ⚠️ Creator vs Afiliado — definido pelo grupo

Cada `influencer_stores.group_id` aponta pra um registro em `profile_groups`. A regra que separa **creator** (captura conteúdo + vendas) de **afiliado** (só vendas):

```sql
CASE
  WHEN lower(pg.name) LIKE '%afiliado%'
    OR lower(pg.description) LIKE '%não captura post%'
    OR lower(pg.description) LIKE '%nao captura post%'
  THEN 'afiliado'
  ELSE 'creator'
END
```

Os 4 grupos relevantes hoje: `Creator` (captura tudo), `Afiliado` (não captura post), `Vet Afiliado` (não captura), `Expert` (captura — perfis pagos). Sem flag = trata como creator.

Toda métrica do dashboard separa os 2 pools:
- `creators_total`, `creators_que_venderam`, `creators_que_postaram`, `creators_dormentes`, `faturamento_creators`, `pedidos_creators`
- `afiliados_total`, `afiliados_que_venderam`, `afiliados_dormentes`, `faturamento_afiliados`, `pedidos_afiliados`
- `faturamento_total` e `pedidos_total` = soma dos dois pools.

## Mapping farmer ← tag (do farmers.json)

Roberto e Jessica taggam cada `influencer_stores.tags` com o nome do farmer responsável. A scheduled task lê `data/farmers.json` do repo (`farmers_tags` por marca), normaliza (trim+lower) e cruza com as tags do Supabase.

**Buddy**: `brion`, `barbara`, `gabi` (display "Gabriella")
**Iridium**: `carol`, `guilherme`, `dario`

Creator com 2+ tags-farmer vai pro bucket `compartilhado`. Creator sem nenhuma tag-farmer cai no bucket `sem_farmer` — visível no ranking e demais visuais com estilo distinto (cinza, sem trofeu, label "Sem Farmer · pendente Roberto/Jessica"). Isso garante que o total da marca sempre fecha com a soma dos farmers.

## ⚠️ ESCOPO: SÓ CREATORS

Schema v4 — o dashboard mostra **apenas creators** (`profile_groups.tipo='creator'`, i.e. perfis que capturam conteúdo + vendem). **Afiliados não entram**. Toda agregação (totais marca, por farmer, sem_farmer, evolução diária, SDR) filtra por `tipo='creator'`. Removidos do JSON: `afiliados_total`, `afiliados_que_venderam`, `afiliados_dormentes`, `faturamento_afiliados`, `pedidos_afiliados`, `faturamento_creators`, `pedidos_creators`, `creators_pool`, `afiliados_pool`.

## Fluxo

### 1. Carregar mapping manual + metas

```
GET https://raw.githubusercontent.com/stevrocha/iridium-buddy-dashboard/main/data/farmers.json
```

Extrai `farmers_tags`, `farmer_display_names`, `metas_mensais` e `metas_sdr`.

### 2. Calcular janela temporal

```python
hoje = now BRT
mesRef = hoje.strftime("%Y-%m")
mesIni = primeiro_dia_do_mes
mesFim = primeiro_dia_do_proximo_mes
m1Ini  = mes_anterior_inicio
m1Fim  = mesIni
diasNoMes = monthrange(hoje.year, hoje.month)[1]
diaAtual = hoje.day
```

### 3. Master query — agregado por farmer × tipo (mês corrente)

Inclui classificação creator/afiliado via `profile_groups`.

```sql
WITH grupo_classif AS (
  SELECT id,
    CASE
      WHEN lower(name) LIKE '%afiliado%'
        OR lower(description) LIKE '%não captura post%'
        OR lower(description) LIKE '%nao captura post%'
      THEN 'afiliado' ELSE 'creator'
    END AS tipo
  FROM profile_groups WHERE deleted_at IS NULL
),
farmer_tags AS (
  SELECT '1dedd6dc-b11a-448b-9bb8-cf4865237bf8'::uuid AS store_id, unnest(ARRAY['brion','barbara','alice','gabi','doug']) AS farmer_tag
  UNION ALL
  SELECT 'a688853e-24e2-4eb2-b2b9-e69545aeafc7'::uuid AS store_id, unnest(ARRAY['carol','guilherme','vitoria']) AS farmer_tag
),
creator_farmers AS (
  SELECT ins.store_id, ins.influencer_id, ins.approved_at, ins.group_id,
    array_agg(DISTINCT ft.farmer_tag) AS farmer_tags
  FROM influencer_stores ins
  JOIN unnest(ins.tags) AS raw_tag ON true
  JOIN farmer_tags ft ON ft.store_id = ins.store_id AND ft.farmer_tag = lower(trim(raw_tag))
  WHERE ins.deleted_at IS NULL AND ins.removed_at IS NULL AND ins.status = 'approved'
  GROUP BY ins.store_id, ins.influencer_id, ins.approved_at, ins.group_id
),
buckets AS (
  SELECT cf.store_id, cf.influencer_id, cf.approved_at,
    COALESCE(gc.tipo,'creator') AS tipo,
    CASE WHEN array_length(cf.farmer_tags,1)=1 THEN cf.farmer_tags[1] ELSE 'compartilhado' END AS farmer_bucket
  FROM creator_farmers cf
  LEFT JOIN grupo_classif gc ON gc.id = cf.group_id
),
sales_mes AS (
  SELECT store_id, influencer_id, SUM(daily_valor_pago) AS receita, SUM(daily_total_vendas) AS pedidos
  FROM mv_creator_daily_sales
  WHERE sales_date >= '{MES_INI}' AND sales_date < '{MES_FIM}'
  GROUP BY store_id, influencer_id
),
posts_mes AS (
  SELECT DISTINCT store_id, influencer_id FROM mv_creator_daily_posts
  WHERE post_day >= '{MES_INI}' AND post_day < '{MES_FIM}' AND daily_total_posts > 0
)
SELECT b.store_id, b.farmer_bucket, b.tipo,
  COUNT(DISTINCT b.influencer_id) AS total,
  COUNT(DISTINCT CASE WHEN s.receita > 0 THEN b.influencer_id END) AS venderam,
  COUNT(DISTINCT p.influencer_id) AS postaram,
  COALESCE(SUM(s.receita), 0) AS faturamento,
  COALESCE(SUM(s.pedidos), 0) AS pedidos,
  COUNT(DISTINCT CASE WHEN b.approved_at >= '{MES_INI}' AND b.approved_at < '{MES_FIM}' THEN b.influencer_id END) AS leads_mes,
  COUNT(DISTINCT CASE WHEN b.approved_at < NOW() - INTERVAL '30 days' AND (s.receita IS NULL OR s.receita = 0) THEN b.influencer_id END) AS dormentes
FROM buckets b
LEFT JOIN sales_mes s ON s.store_id = b.store_id AND s.influencer_id = b.influencer_id
LEFT JOIN posts_mes p ON p.store_id = b.store_id AND p.influencer_id = b.influencer_id
GROUP BY b.store_id, b.farmer_bucket, b.tipo;
```

⚠️ `leads_mes` = `approved_at` dentro do mês corrente (mês de calendário, **não** janela rolante 30d). O label do front é "Prospecções **no mês**".

### 3b. Sem Farmer — approved sem nenhuma tag de farmer

Os perfis approved da marca que **não casam com nenhuma** das tags em `farmers_tags` ficam fora do master query da seção 3 (porque o `JOIN farmer_tags` filtra). Pra fechar o total da marca, roda essa segunda query por marca × tipo:

```sql
WITH farmer_tags AS (
  SELECT '1dedd6dc-...'::uuid AS store_id, unnest(ARRAY[...]) AS t
  UNION ALL
  SELECT 'a688853e-...'::uuid AS store_id, unnest(ARRAY[...]) AS t
),
sem_farmer AS (
  SELECT ins.*
  FROM influencer_stores ins
  WHERE ins.deleted_at IS NULL AND ins.removed_at IS NULL AND ins.status='approved'
    AND ins.store_id IN (...)
    AND NOT EXISTS (
      SELECT 1 FROM unnest(ins.tags) raw_tag
      JOIN farmer_tags ft ON ft.store_id = ins.store_id AND ft.t = lower(trim(raw_tag))
    )
)
-- agrega total/venderam/postaram/faturamento/pedidos/leads_mes/dormentes/faturamento_m1
-- por (store_id, tipo) usando os mesmos LEFT JOINs sales_mes/posts_mes/sales_m1
```

Esse bucket vira o farmer `{id:"sem_farmer", nome:"Sem Farmer", color:"#6B7280"}` no JSON, com `_sem_farmer:true`. No ranking, recebe `sem_farmer:true` e `trofeu:null` (não compete).

### 4. MoM — mesma query com janela M-1

Roda o mesmo CTE substituindo `'{MES_INI}'` e `'{MES_FIM}'` por `'{M1_INI}'` e `'{M1_FIM}'`. Pega só `faturamento`. Calcula `mom_pct = (mes - m1) / m1 * 100`. Se m1=0, `mom_pct = null` (representado como "novo" no front).

### 5. Totais da marca (incluindo creators sem farmer)

```sql
SELECT
  CASE store_id WHEN '1dedd6dc-...' THEN 'buddy' ELSE 'iridium' END AS marca_key,
  COUNT(DISTINCT a.influencer_id) AS creators_total,
  COUNT(DISTINCT CASE WHEN s.receita > 0 THEN a.influencer_id END) AS creators_venderam,
  COUNT(DISTINCT p.influencer_id) AS creators_postaram,
  COALESCE(SUM(s.receita),0) AS faturamento_total,
  COALESCE(SUM(s.pedidos),0) AS pedidos_total,
  COUNT(DISTINCT CASE WHEN a.approved_at >= NOW() - INTERVAL '30 days' THEN a.influencer_id END) AS leads_30d,
  COUNT(DISTINCT CASE WHEN a.approved_at < NOW() - INTERVAL '30 days' AND (s.receita IS NULL OR s.receita = 0) THEN a.influencer_id END) AS dormentes
FROM (
  SELECT store_id, influencer_id, approved_at FROM influencer_stores
  WHERE deleted_at IS NULL AND removed_at IS NULL AND status='approved'
    AND store_id IN ('1dedd6dc-...','a688853e-...')
) a
LEFT JOIN (
  SELECT store_id, influencer_id, SUM(daily_valor_pago) AS receita, SUM(daily_total_vendas) AS pedidos
  FROM mv_creator_daily_sales WHERE sales_date >= '{MES_INI}' AND sales_date < '{MES_FIM}'
  GROUP BY store_id, influencer_id
) s ON s.store_id = a.store_id AND s.influencer_id = a.influencer_id
LEFT JOIN (
  SELECT DISTINCT store_id, influencer_id FROM mv_creator_daily_posts
  WHERE post_day >= '{MES_INI}' AND post_day < '{MES_FIM}' AND daily_total_posts > 0
) p ON p.store_id = a.store_id AND p.influencer_id = a.influencer_id
GROUP BY a.store_id;
```

Ticket médio = `faturamento_total / pedidos_total`.

### 6. Conversão lead → 1ª venda

```sql
WITH leads AS (
  SELECT store_id, influencer_id, approved_at::date AS approved_dt
  FROM influencer_stores
  WHERE deleted_at IS NULL AND removed_at IS NULL AND status='approved'
    AND approved_at >= NOW() - INTERVAL '30 days'
    AND store_id IN ('1dedd6dc-...','a688853e-...')
),
first_sale AS (
  SELECT store_id, influencer_id, MIN(sales_date) AS primeira_venda
  FROM mv_creator_daily_sales WHERE daily_valor_pago > 0
  GROUP BY store_id, influencer_id
),
joined AS (
  SELECT l.store_id, l.approved_dt, fs.primeira_venda,
    CASE WHEN fs.primeira_venda IS NOT NULL AND fs.primeira_venda >= l.approved_dt
      THEN (fs.primeira_venda - l.approved_dt) ELSE NULL END AS dias_ate_venda
  FROM leads l LEFT JOIN first_sale fs ON fs.store_id = l.store_id AND fs.influencer_id = l.influencer_id
)
SELECT store_id,
  COUNT(*) AS leads_total,
  COUNT(dias_ate_venda) AS converteram,
  ROUND(AVG(dias_ate_venda)::numeric, 1) AS dias_medios
FROM joined GROUP BY store_id;
```

`conversao_pct = converteram / leads_total * 100`.

### 7. Evolução diária acumulada

```sql
SELECT store_id, sales_date,
  SUM(SUM(daily_valor_pago)) OVER (PARTITION BY store_id ORDER BY sales_date) AS acumulado
FROM mv_creator_daily_sales
WHERE sales_date >= '{MES_INI}' AND sales_date < '{MES_FIM}'
GROUP BY store_id, sales_date ORDER BY sales_date;
```

Preencher dias faltantes (sem venda) carregando o último valor acumulado.

### 8. Top 8 creators por farmer (Pareto)

```sql
-- usa o mesmo CTE creator_buckets + sales_mes da query 3
SELECT cb.store_id, cb.farmer_bucket, i.username, i.name, s.receita,
  ROW_NUMBER() OVER (PARTITION BY cb.store_id, cb.farmer_bucket ORDER BY s.receita DESC) AS rank
FROM creator_buckets cb
JOIN sales_mes s ON s.store_id=cb.store_id AND s.influencer_id=cb.influencer_id
LEFT JOIN influencers i ON i.id=cb.influencer_id
WHERE s.receita > 0;
-- filtra rank <= 8 em código
```

### 9. PRESERVAR HISTÓRICO ANTES DE MONTAR JSON NOVO ⚠️ **CRÍTICO**

Antes de gerar o JSON novo, **leia o `data/dashboard.json` atual do repo** (via raw GitHub ou clone local):

```
GET https://raw.githubusercontent.com/stevrocha/iridium-buddy-dashboard/main/data/dashboard.json
```

Extraia 2 coisas:
- `historico` (objeto com snapshots de meses passados — pode estar vazio na 1ª vez)
- `meta.mesReferencia` antigo (ex: `"2026-06"`)

**Lógica de preservação:**

1. **Se o mês virou** (`mes_antigo != mes_corrente`):
   - O JSON atual representa um mês recém-fechado. Mova `marcas` antigo pra `historico[mes_antigo]` com flag `_closed: true` em cada marca.
   - Comece a contagem do mês novo do zero.
2. **Se mesmo mês** (`mes_antigo == mes_corrente`):
   - Só preserve `historico` como veio (não acrescenta nada). Os dados de `marcas` são sobrescritos com o snapshot fresh.

**Sempre**: `historico` é cumulativo — NUNCA deletar entradas antigas dele.

```pseudocode
old_json = fetch(raw github dashboard.json)
historico = old_json.historico || {}

if old_json.meta.mesReferencia != mes_corrente:
  # Mês virou — congelar o mês anterior
  snapshot_marcas = deepcopy(old_json.marcas)
  for mk in snapshot_marcas:
    snapshot_marcas[mk]._closed = True
  historico[old_json.meta.mesReferencia] = snapshot_marcas

new_json.historico = historico   # SEMPRE inclui no novo JSON
```

### 10. Montar JSON

Schema completo em `../data/dashboard.json` (este repo). Campos:

- `marca.faturamento_m1`, `marca.mom_pct`
- `marca.creators_dormentes`, `marca.pedidos_total`, `marca.ticket_medio`
- `marca.farmers[].faturamento_m1`, `mom_pct`, `dormentes`, `pedidos`, `ticket_medio`, `top_creators`
- `marca.ranking_farmers` (array de `{posicao, id, nome, faturamento, mom_pct, trofeu}` — derivado, ordenando farmers por faturamento desc; trofeu: ouro/prata/bronze pras 3 primeiras)
- `marca.sdr.prospeccoes_total` ⚠️ **NOME CRÍTICO** (não `leads_no_mes`), `meta`, `convertidos`, `conversao_pct`, `dias_medios_1venda` — **leads do mês corrente**, não rolling 30d
- `marca.farmers[]` inclui bucket `sem_farmer` (id="sem_farmer") quando há creators sem tag — soma de farmers fecha o total da marca
- `marca.ranking_farmers[].sem_farmer = true` sinaliza o bucket sem tag (front renderiza sem trofeu e com aviso pra taggar)
- `creators_total` = creators approved (`tipo='creator'`) da marca
- `creators_que_venderam`, `creators_que_postaram`, `creators_dormentes` — todos pool creators
- `faturamento_total` e `pedidos_total` = só creators (afiliados fora do escopo)
- `historico` ← preservado da seção 9

Aplicar `farmer_display_names` do `farmers.json` no nome exibido (ex: `barbara` → `Bárbara`).

### 11. Commit via PAT

```
PUT /repos/stevrocha/iridium-buddy-dashboard/contents/data/dashboard.json
Authorization: Bearer <PAT>
{
  "message": "refresh dashboard <data>",
  "content": "<base64 do JSON>",
  "branch": "main",
  "sha": "<sha do arquivo atual>"
}
```

PAT em `~/.claude/secrets/github_pat_iridium.md`.

### 12. Logs e resilience

- Se uma marca falhar (timeout, query error), **mantém os dados antigos daquela marca** no JSON.
- Logar: tempo total, contagem de creators/farmers, IDs sem farmer (alerta pra Roberto/Jessica).
- Avisar se `farmers_tags` no farmers.json não casou com nenhuma tag real do banco (digitação errada).

## Validação após run

Abrir `https://<dominio-amplify>/data/dashboard.json` e checar:
- `meta.geradoEm` é do dia
- `marcas.buddy.faturamento_total > 0`
- `marcas.buddy.farmers[]` tem 3 entradas (brion, barbara, gabi)
- `marcas.iridium.farmers[]` tem 2 entradas (guilherme, carol — Vitoria pode aparecer ou não, depende de ter creator com a tag)
- `mom_pct` razoável (-50% a +100%)
- Conversão SDR entre 0 e 100%

## Notas

- Tags são plain text livre. Se Roberto/Jessica criarem tag nova (ex: novo farmer "Pedro"), basta adicionar `pedro` em `farmers.json → marcas.buddy.farmers_tags` + `farmer_display_names`. Próxima execução pega automaticamente.
- Variações de case (`Guilherme` vs `guilherme`) e espaços extras (`Guilherme `) são deduplicados via `trim+lower`.
- Tags como `prospect vic`, `PRP Junior`, `Creator`, `Embaixadores`, `Top Influencer`, `Vet Afiliado`, `Campanha Aberta`, etc. **não são farmers** — são status, categorias ou campanhas. Ignorar.


## ⚠️ Schema SDR — campo crítico
O frontend espera `sdr.prospeccoes_total` (não `sdr.leads_no_mes`). Sempre gere o JSON com o nome **`prospeccoes_total`**. PROSPECCOES_TOTAL_FIELD_NAME = "prospeccoes_total".
