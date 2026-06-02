-- =============================================================
-- Iridium Labs · Dashboard Metabase — queries SQL
-- =============================================================
-- Fonte: Supabase Postgres (conexão direta no Metabase)
-- store_id Iridium: a688853e-24e2-4eb2-b2b9-e69545aeafc7
--
-- Variável compartilhada (declarar em cada Question):
--   ref_month  · Tipo: Date · Required: yes
--   No dashboard, criar 1 filtro Date apontando pra essa variável.
--
-- Farmers Iridium: carol, guilherme, vitoria
-- =============================================================


-- -------------------------------------------------------------
-- Q1 · Big Numbers da Marca
-- -------------------------------------------------------------
WITH params AS (
  SELECT
    date_trunc('month', {{ref_month}}::date)                          AS mes_ini,
    date_trunc('month', {{ref_month}}::date) + INTERVAL '1 month'     AS mes_fim,
    date_trunc('month', {{ref_month}}::date) - INTERVAL '1 month'     AS m1_ini,
    date_trunc('month', {{ref_month}}::date)                          AS m1_fim
),
approved AS (
  SELECT store_id, influencer_id, approved_at
  FROM influencer_stores
  WHERE deleted_at IS NULL AND removed_at IS NULL AND status='approved'
    AND store_id = 'a688853e-24e2-4eb2-b2b9-e69545aeafc7'
),
sales_mes AS (
  SELECT s.store_id, s.influencer_id,
         SUM(s.daily_valor_pago)  AS receita,
         SUM(s.daily_total_vendas) AS pedidos
  FROM mv_creator_daily_sales s, params p
  WHERE s.sales_date >= p.mes_ini AND s.sales_date < p.mes_fim
    AND s.store_id = 'a688853e-24e2-4eb2-b2b9-e69545aeafc7'
  GROUP BY s.store_id, s.influencer_id
),
sales_m1 AS (
  SELECT s.store_id, s.influencer_id, SUM(s.daily_valor_pago) AS receita_m1
  FROM mv_creator_daily_sales s, params p
  WHERE s.sales_date >= p.m1_ini AND s.sales_date < p.m1_fim
    AND s.store_id = 'a688853e-24e2-4eb2-b2b9-e69545aeafc7'
  GROUP BY s.store_id, s.influencer_id
),
posts_mes AS (
  SELECT DISTINCT pp.store_id, pp.influencer_id
  FROM mv_creator_daily_posts pp, params p
  WHERE pp.post_day >= p.mes_ini AND pp.post_day < p.mes_fim
    AND pp.daily_total_posts > 0
    AND pp.store_id = 'a688853e-24e2-4eb2-b2b9-e69545aeafc7'
)
SELECT
  COUNT(DISTINCT a.influencer_id)                                                                  AS creators_total,
  COUNT(DISTINCT CASE WHEN sm.receita > 0 THEN a.influencer_id END)                                AS creators_venderam,
  COUNT(DISTINCT pm.influencer_id)                                                                 AS creators_postaram,
  COUNT(DISTINCT CASE
        WHEN a.approved_at < NOW() - INTERVAL '30 days' AND (sm.receita IS NULL OR sm.receita = 0)
        THEN a.influencer_id END)                                                                  AS creators_dormentes,
  COUNT(DISTINCT CASE WHEN a.approved_at >= NOW() - INTERVAL '30 days' THEN a.influencer_id END)   AS leads_30d,
  COALESCE(SUM(sm.receita), 0)::numeric(14,2)                                                      AS faturamento_total,
  COALESCE(SUM(sm.pedidos), 0)                                                                     AS pedidos_total,
  CASE WHEN COALESCE(SUM(sm.pedidos),0) > 0
       THEN ROUND((COALESCE(SUM(sm.receita),0) / SUM(sm.pedidos))::numeric, 2)
       ELSE NULL END                                                                               AS ticket_medio,
  COALESCE(SUM(s1.receita_m1), 0)::numeric(14,2)                                                   AS faturamento_m1,
  CASE WHEN COALESCE(SUM(s1.receita_m1),0) > 0
       THEN ROUND(((COALESCE(SUM(sm.receita),0) - SUM(s1.receita_m1)) / SUM(s1.receita_m1) * 100)::numeric, 1)
       ELSE NULL END                                                                               AS mom_pct
FROM approved a
LEFT JOIN sales_mes sm ON sm.store_id = a.store_id AND sm.influencer_id = a.influencer_id
LEFT JOIN sales_m1  s1 ON s1.store_id = a.store_id AND s1.influencer_id = a.influencer_id
LEFT JOIN posts_mes pm ON pm.store_id = a.store_id AND pm.influencer_id = a.influencer_id;


-- -------------------------------------------------------------
-- Q2 · Evolução diária acumulada (meta linear · ajustar 70000 se necessário)
-- -------------------------------------------------------------
WITH params AS (
  SELECT
    date_trunc('month', {{ref_month}}::date) AS mes_ini,
    date_trunc('month', {{ref_month}}::date) + INTERVAL '1 month' AS mes_fim
),
dias AS (
  SELECT generate_series(p.mes_ini::date,
                         (p.mes_fim - INTERVAL '1 day')::date,
                         INTERVAL '1 day')::date AS dia_d
  FROM params p
),
diario AS (
  SELECT s.sales_date, SUM(s.daily_valor_pago) AS receita_dia
  FROM mv_creator_daily_sales s, params p
  WHERE s.sales_date >= p.mes_ini AND s.sales_date < p.mes_fim
    AND s.store_id = 'a688853e-24e2-4eb2-b2b9-e69545aeafc7'
  GROUP BY s.sales_date
)
SELECT
  d.dia_d                                          AS dia,
  EXTRACT(DAY FROM d.dia_d)::int                   AS num_dia,
  SUM(COALESCE(di.receita_dia, 0))
    OVER (ORDER BY d.dia_d
          ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)::numeric(14,2)
                                                   AS realizado_acumulado,
  ROUND((70000.0 * EXTRACT(DAY FROM d.dia_d)
         / EXTRACT(DAY FROM (DATE_TRUNC('month', d.dia_d) + INTERVAL '1 month - 1 day'))
        )::numeric, 2)                             AS meta_acumulada
FROM dias d
LEFT JOIN diario di ON di.sales_date = d.dia_d
ORDER BY d.dia_d;


-- -------------------------------------------------------------
-- Q3 · Ranking de farmers (mês corrente + MoM)
-- -------------------------------------------------------------
WITH params AS (
  SELECT
    date_trunc('month', {{ref_month}}::date) AS mes_ini,
    date_trunc('month', {{ref_month}}::date) + INTERVAL '1 month' AS mes_fim,
    date_trunc('month', {{ref_month}}::date) - INTERVAL '1 month' AS m1_ini,
    date_trunc('month', {{ref_month}}::date) AS m1_fim
),
farmer_tags AS (
  SELECT unnest(ARRAY['carol','guilherme','vitoria']) AS farmer_tag
),
display AS (
  SELECT * FROM (VALUES
    ('carol','Carol'), ('guilherme','Guilherme'), ('vitoria','Vitória'),
    ('compartilhado','Compartilhado')
  ) AS d(farmer_tag, display_name)
),
creator_farmers AS (
  SELECT ins.influencer_id, ins.approved_at,
         array_agg(DISTINCT ft.farmer_tag) AS farmer_tags
  FROM influencer_stores ins
  JOIN unnest(ins.tags) AS raw_tag ON TRUE
  JOIN farmer_tags ft ON ft.farmer_tag = lower(trim(raw_tag))
  WHERE ins.deleted_at IS NULL AND ins.removed_at IS NULL AND ins.status='approved'
    AND ins.store_id = 'a688853e-24e2-4eb2-b2b9-e69545aeafc7'
  GROUP BY ins.influencer_id, ins.approved_at
),
creator_buckets AS (
  SELECT influencer_id, approved_at,
         CASE WHEN array_length(farmer_tags,1) = 1 THEN farmer_tags[1]
              ELSE 'compartilhado' END AS bucket
  FROM creator_farmers
),
sales_mes AS (
  SELECT s.influencer_id,
         SUM(s.daily_valor_pago)  AS receita,
         SUM(s.daily_total_vendas) AS pedidos
  FROM mv_creator_daily_sales s, params p
  WHERE s.sales_date >= p.mes_ini AND s.sales_date < p.mes_fim
    AND s.store_id = 'a688853e-24e2-4eb2-b2b9-e69545aeafc7'
  GROUP BY s.influencer_id
),
sales_m1 AS (
  SELECT s.influencer_id, SUM(s.daily_valor_pago) AS receita_m1
  FROM mv_creator_daily_sales s, params p
  WHERE s.sales_date >= p.m1_ini AND s.sales_date < p.m1_fim
    AND s.store_id = 'a688853e-24e2-4eb2-b2b9-e69545aeafc7'
  GROUP BY s.influencer_id
),
posts_mes AS (
  SELECT DISTINCT pp.influencer_id
  FROM mv_creator_daily_posts pp, params p
  WHERE pp.post_day >= p.mes_ini AND pp.post_day < p.mes_fim
    AND pp.daily_total_posts > 0
    AND pp.store_id = 'a688853e-24e2-4eb2-b2b9-e69545aeafc7'
)
SELECT
  COALESCE(d.display_name, cb.bucket)                                                       AS farmer,
  cb.bucket                                                                                 AS farmer_id,
  COUNT(DISTINCT cb.influencer_id)                                                          AS creators_total,
  COUNT(DISTINCT CASE WHEN sm.receita > 0 THEN cb.influencer_id END)                        AS creators_venderam,
  COUNT(DISTINCT pm.influencer_id)                                                          AS creators_postaram,
  COUNT(DISTINCT CASE WHEN cb.approved_at >= NOW() - INTERVAL '30 days'
                      THEN cb.influencer_id END)                                            AS leads_30d,
  COUNT(DISTINCT CASE WHEN cb.approved_at < NOW() - INTERVAL '30 days'
                        AND (sm.receita IS NULL OR sm.receita = 0)
                      THEN cb.influencer_id END)                                            AS dormentes,
  COALESCE(SUM(sm.receita), 0)::numeric(14,2)                                               AS faturamento,
  COALESCE(SUM(sm.pedidos), 0)                                                              AS pedidos,
  COALESCE(SUM(s1.receita_m1), 0)::numeric(14,2)                                            AS faturamento_m1,
  CASE WHEN COALESCE(SUM(s1.receita_m1),0) > 0
       THEN ROUND(((COALESCE(SUM(sm.receita),0) - SUM(s1.receita_m1)) / SUM(s1.receita_m1) * 100)::numeric, 1)
       ELSE NULL END                                                                        AS mom_pct,
  CASE WHEN COALESCE(SUM(sm.pedidos),0) > 0
       THEN ROUND((COALESCE(SUM(sm.receita),0) / SUM(sm.pedidos))::numeric, 2)
       ELSE NULL END                                                                        AS ticket_medio,
  RANK() OVER (ORDER BY COALESCE(SUM(sm.receita),0) DESC)                                   AS posicao
FROM creator_buckets cb
LEFT JOIN sales_mes sm ON sm.influencer_id = cb.influencer_id
LEFT JOIN sales_m1  s1 ON s1.influencer_id = cb.influencer_id
LEFT JOIN posts_mes pm ON pm.influencer_id = cb.influencer_id
LEFT JOIN display d ON d.farmer_tag = cb.bucket
GROUP BY cb.bucket, d.display_name
ORDER BY faturamento DESC;


-- -------------------------------------------------------------
-- Q4 · Conversão SDR (janela rolante 30d, não usa {{ref_month}})
-- -------------------------------------------------------------
WITH leads AS (
  SELECT influencer_id, approved_at::date AS approved_dt
  FROM influencer_stores
  WHERE deleted_at IS NULL AND removed_at IS NULL AND status='approved'
    AND approved_at >= NOW() - INTERVAL '30 days'
    AND store_id = 'a688853e-24e2-4eb2-b2b9-e69545aeafc7'
),
first_sale AS (
  SELECT influencer_id, MIN(sales_date) AS primeira_venda
  FROM mv_creator_daily_sales
  WHERE daily_valor_pago > 0
    AND store_id = 'a688853e-24e2-4eb2-b2b9-e69545aeafc7'
  GROUP BY influencer_id
)
SELECT
  COUNT(*)                                                                       AS leads_total,
  COUNT(CASE WHEN fs.primeira_venda IS NOT NULL
                  AND fs.primeira_venda >= l.approved_dt
             THEN 1 END)                                                         AS convertidos,
  CASE WHEN COUNT(*) > 0
       THEN ROUND((COUNT(CASE WHEN fs.primeira_venda IS NOT NULL
                                    AND fs.primeira_venda >= l.approved_dt
                              THEN 1 END)::numeric / COUNT(*) * 100), 1)
       ELSE 0 END                                                                AS conversao_pct,
  ROUND(AVG(CASE WHEN fs.primeira_venda IS NOT NULL
                       AND fs.primeira_venda >= l.approved_dt
                  THEN (fs.primeira_venda - l.approved_dt)
             END)::numeric, 1)                                                   AS dias_medios_1venda
FROM leads l
LEFT JOIN first_sale fs ON fs.influencer_id = l.influencer_id;


-- -------------------------------------------------------------
-- Q5 · Top 25 creators do mês (Pareto)
-- -------------------------------------------------------------
WITH params AS (
  SELECT
    date_trunc('month', {{ref_month}}::date) AS mes_ini,
    date_trunc('month', {{ref_month}}::date) + INTERVAL '1 month' AS mes_fim
),
sales_mes AS (
  SELECT s.influencer_id,
         SUM(s.daily_valor_pago)  AS receita,
         SUM(s.daily_total_vendas) AS pedidos
  FROM mv_creator_daily_sales s, params p
  WHERE s.sales_date >= p.mes_ini AND s.sales_date < p.mes_fim
    AND s.store_id = 'a688853e-24e2-4eb2-b2b9-e69545aeafc7'
  GROUP BY s.influencer_id
  HAVING SUM(s.daily_valor_pago) > 0
)
SELECT
  '@' || i.username                  AS creator,
  i.name                             AS nome,
  sm.receita::numeric(14,2)          AS receita,
  sm.pedidos                         AS pedidos,
  ROUND((sm.receita / SUM(sm.receita) OVER ())::numeric * 100, 1) AS pct_marca,
  ROUND((SUM(sm.receita) OVER (ORDER BY sm.receita DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
         / SUM(sm.receita) OVER ())::numeric * 100, 1)            AS pareto_acumulado_pct
FROM sales_mes sm
LEFT JOIN influencers i ON i.id = sm.influencer_id
ORDER BY receita DESC
LIMIT 25;


-- -------------------------------------------------------------
-- Q6 · Top 8 creators por farmer
-- -------------------------------------------------------------
WITH params AS (
  SELECT
    date_trunc('month', {{ref_month}}::date) AS mes_ini,
    date_trunc('month', {{ref_month}}::date) + INTERVAL '1 month' AS mes_fim
),
farmer_tags AS (
  SELECT unnest(ARRAY['carol','guilherme','vitoria']) AS farmer_tag
),
display AS (
  SELECT * FROM (VALUES
    ('carol','Carol'), ('guilherme','Guilherme'), ('vitoria','Vitória'),
    ('compartilhado','Compartilhado')
  ) AS d(farmer_tag, display_name)
),
creator_buckets AS (
  SELECT ins.influencer_id,
         CASE WHEN COUNT(DISTINCT ft.farmer_tag) = 1 THEN MAX(ft.farmer_tag)
              ELSE 'compartilhado' END AS bucket
  FROM influencer_stores ins
  JOIN unnest(ins.tags) AS raw_tag ON TRUE
  JOIN farmer_tags ft ON ft.farmer_tag = lower(trim(raw_tag))
  WHERE ins.deleted_at IS NULL AND ins.removed_at IS NULL AND ins.status='approved'
    AND ins.store_id = 'a688853e-24e2-4eb2-b2b9-e69545aeafc7'
  GROUP BY ins.influencer_id
),
sales_mes AS (
  SELECT s.influencer_id, SUM(s.daily_valor_pago) AS receita
  FROM mv_creator_daily_sales s, params p
  WHERE s.sales_date >= p.mes_ini AND s.sales_date < p.mes_fim
    AND s.store_id = 'a688853e-24e2-4eb2-b2b9-e69545aeafc7'
  GROUP BY s.influencer_id
  HAVING SUM(s.daily_valor_pago) > 0
),
ranked AS (
  SELECT cb.bucket,
         '@' || i.username AS creator,
         i.name            AS nome,
         sm.receita::numeric(14,2) AS receita,
         ROW_NUMBER() OVER (PARTITION BY cb.bucket ORDER BY sm.receita DESC) AS rank
  FROM creator_buckets cb
  JOIN sales_mes sm ON sm.influencer_id = cb.influencer_id
  LEFT JOIN influencers i ON i.id = cb.influencer_id
)
SELECT
  COALESCE(d.display_name, r.bucket) AS farmer,
  r.rank,
  r.creator,
  r.nome,
  r.receita
FROM ranked r
LEFT JOIN display d ON d.farmer_tag = r.bucket
WHERE r.rank <= 8
ORDER BY farmer, rank;


-- -------------------------------------------------------------
-- Q7 · Faturamento por farmer · mês vs M-1
-- -------------------------------------------------------------
WITH params AS (
  SELECT
    date_trunc('month', {{ref_month}}::date) AS mes_ini,
    date_trunc('month', {{ref_month}}::date) + INTERVAL '1 month' AS mes_fim,
    date_trunc('month', {{ref_month}}::date) - INTERVAL '1 month' AS m1_ini,
    date_trunc('month', {{ref_month}}::date) AS m1_fim
),
farmer_tags AS (
  SELECT unnest(ARRAY['carol','guilherme','vitoria']) AS farmer_tag
),
display AS (
  SELECT * FROM (VALUES
    ('carol','Carol'), ('guilherme','Guilherme'), ('vitoria','Vitória'),
    ('compartilhado','Compartilhado')
  ) AS d(farmer_tag, display_name)
),
creator_buckets AS (
  SELECT ins.influencer_id,
         CASE WHEN COUNT(DISTINCT ft.farmer_tag) = 1 THEN MAX(ft.farmer_tag)
              ELSE 'compartilhado' END AS bucket
  FROM influencer_stores ins
  JOIN unnest(ins.tags) AS raw_tag ON TRUE
  JOIN farmer_tags ft ON ft.farmer_tag = lower(trim(raw_tag))
  WHERE ins.deleted_at IS NULL AND ins.removed_at IS NULL AND ins.status='approved'
    AND ins.store_id = 'a688853e-24e2-4eb2-b2b9-e69545aeafc7'
  GROUP BY ins.influencer_id
),
sales_combined AS (
  SELECT cb.bucket,
         SUM(CASE WHEN s.sales_date >= p.mes_ini AND s.sales_date < p.mes_fim THEN s.daily_valor_pago ELSE 0 END) AS receita_mes,
         SUM(CASE WHEN s.sales_date >= p.m1_ini  AND s.sales_date < p.m1_fim  THEN s.daily_valor_pago ELSE 0 END) AS receita_m1
  FROM creator_buckets cb
  LEFT JOIN mv_creator_daily_sales s
         ON s.influencer_id = cb.influencer_id
        AND s.store_id = 'a688853e-24e2-4eb2-b2b9-e69545aeafc7'
  CROSS JOIN params p
  WHERE s.sales_date IS NULL
     OR (s.sales_date >= p.m1_ini AND s.sales_date < p.mes_fim)
  GROUP BY cb.bucket
)
SELECT
  COALESCE(d.display_name, sc.bucket) AS farmer,
  COALESCE(sc.receita_m1, 0)::numeric(14,2)  AS faturamento_m1,
  COALESCE(sc.receita_mes, 0)::numeric(14,2) AS faturamento_mes,
  CASE WHEN COALESCE(sc.receita_m1,0) > 0
       THEN ROUND(((sc.receita_mes - sc.receita_m1) / sc.receita_m1 * 100)::numeric, 1)
       ELSE NULL END                                                                AS mom_pct
FROM sales_combined sc
LEFT JOIN display d ON d.farmer_tag = sc.bucket
ORDER BY faturamento_mes DESC;


-- -------------------------------------------------------------
-- Q8 · Saúde do funil
-- -------------------------------------------------------------
WITH params AS (
  SELECT
    date_trunc('month', {{ref_month}}::date) AS mes_ini,
    date_trunc('month', {{ref_month}}::date) + INTERVAL '1 month' AS mes_fim
),
approved AS (
  SELECT influencer_id, approved_at
  FROM influencer_stores
  WHERE deleted_at IS NULL AND removed_at IS NULL AND status='approved'
    AND store_id = 'a688853e-24e2-4eb2-b2b9-e69545aeafc7'
),
sales_mes AS (
  SELECT s.influencer_id, SUM(s.daily_valor_pago) AS receita
  FROM mv_creator_daily_sales s, params p
  WHERE s.sales_date >= p.mes_ini AND s.sales_date < p.mes_fim
    AND s.store_id = 'a688853e-24e2-4eb2-b2b9-e69545aeafc7'
  GROUP BY s.influencer_id
)
SELECT
  CASE
    WHEN a.approved_at >= NOW() - INTERVAL '30 days'              THEN 'Lead novo (30d)'
    WHEN COALESCE(sm.receita, 0) > 0                              THEN 'Ativo (vendeu no mês)'
    ELSE                                                                'Dormente'
  END AS status,
  COUNT(DISTINCT a.influencer_id) AS creators
FROM approved a
LEFT JOIN sales_mes sm ON sm.influencer_id = a.influencer_id
GROUP BY 1
ORDER BY creators DESC;


-- -------------------------------------------------------------
-- Q9 · Postagens vs Vendas por dia
-- -------------------------------------------------------------
WITH params AS (
  SELECT
    date_trunc('month', {{ref_month}}::date) AS mes_ini,
    date_trunc('month', {{ref_month}}::date) + INTERVAL '1 month' AS mes_fim
),
posts AS (
  SELECT pp.post_day AS dia, SUM(pp.daily_total_posts) AS posts
  FROM mv_creator_daily_posts pp, params p
  WHERE pp.post_day >= p.mes_ini AND pp.post_day < p.mes_fim
    AND pp.store_id = 'a688853e-24e2-4eb2-b2b9-e69545aeafc7'
  GROUP BY pp.post_day
),
vendas AS (
  SELECT s.sales_date AS dia, SUM(s.daily_valor_pago) AS receita
  FROM mv_creator_daily_sales s, params p
  WHERE s.sales_date >= p.mes_ini AND s.sales_date < p.mes_fim
    AND s.store_id = 'a688853e-24e2-4eb2-b2b9-e69545aeafc7'
  GROUP BY s.sales_date
)
SELECT
  COALESCE(p.dia, v.dia)                  AS dia,
  COALESCE(p.posts, 0)                    AS posts,
  COALESCE(v.receita, 0)::numeric(14,2)   AS receita
FROM posts p
FULL OUTER JOIN vendas v ON v.dia = p.dia
ORDER BY dia;
