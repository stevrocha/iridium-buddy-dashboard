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

## Mapping farmer ← tag (do farmers.json)

Roberto e Jessica taggam cada `influencer_stores.tags` com o nome do farmer responsável. A scheduled task lê `data/farmers.json` do repo (`farmers_tags` por marca), normaliza (trim+lower) e cruza com as tags do Supabase.

**Buddy**: `brion`, `barbara`, `alice`, `gabi`, `doug`
**Iridium**: `carol`, `guilherme`, `vitoria`

Creator com 2+ tags-farmer vai pro bucket `compartilhado`. Creator sem nenhuma tag-farmer entra no total da marca mas **não aparece na agregação por farmer** (loga aviso).

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

### 3. Master query — agregado por farmer (mês corrente)

Substituir `{FARMER_TAGS}` na CTE inicial pelas tags da marca.

```sql
WITH farmer_tags AS (
  SELECT '1dedd6dc-b11a-448b-9bb8-cf4865237bf8'::uuid AS store_id, unnest(ARRAY['brion','barbara','alice','gabi','doug']) AS farmer_tag
  UNION ALL
  SELECT 'a688853e-24e2-4eb2-b2b9-e69545aeafc7'::uuid AS store_id, unnest(ARRAY['carol','guilherme','vitoria']) AS farmer_tag
),
creator_farmers AS (
  SELECT ins.store_id, ins.influencer_id, ins.approved_at,
    array_agg(DISTINCT ft.farmer_tag) AS farmer_tags
  FROM influencer_stores ins
  JOIN unnest(ins.tags) AS raw_tag ON true
  JOIN farmer_tags ft ON ft.store_id = ins.store_id AND ft.farmer_tag = lower(trim(raw_tag))
  WHERE ins.deleted_at IS NULL AND ins.removed_at IS NULL AND ins.status = 'approved'
  GROUP BY ins.store_id, ins.influencer_id, ins.approved_at
),
creator_buckets AS (
  SELECT store_id, influencer_id, approved_at,
    CASE WHEN array_length(farmer_tags, 1) = 1 THEN farmer_tags[1] ELSE 'compartilhado' END AS farmer_bucket
  FROM creator_farmers
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
SELECT cb.store_id, cb.farmer_bucket,
  COUNT(DISTINCT cb.influencer_id) AS creators_total,
  COUNT(DISTINCT CASE WHEN s.receita > 0 THEN cb.influencer_id END) AS creators_venderam,
  COUNT(DISTINCT p.influencer_id) AS creators_postaram,
  COALESCE(SUM(s.receita), 0) AS faturamento,
  COALESCE(SUM(s.pedidos), 0) AS pedidos,
  COUNT(DISTINCT CASE WHEN cb.approved_at >= NOW() - INTERVAL '30 days' THEN cb.influencer_id END) AS leads_30d,
  COUNT(DISTINCT CASE WHEN cb.approved_at < NOW() - INTERVAL '30 days' AND (s.receita IS NULL OR s.receita = 0) THEN cb.influencer_id END) AS dormentes
FROM creator_buckets cb
LEFT JOIN sales_mes s ON s.store_id = cb.store_id AND s.influencer_id = cb.influencer_id
LEFT JOIN posts_mes p ON p.store_id = cb.store_id AND p.influencer_id = cb.influencer_id
GROUP BY cb.store_id, cb.farmer_bucket;
```

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
- `marca.sdr.prospeccoes_total` ⚠️ **NOME CRÍTICO** (não `leads_no_mes`), `meta`, `convertidos`, `conversao_pct`, `dias_medios_1venda`
- `creators_total` = TODOS os approved da marca (não só os com farmer)
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
