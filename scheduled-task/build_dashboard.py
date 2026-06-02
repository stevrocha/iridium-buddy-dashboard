#!/usr/bin/env python3
"""Builds dashboard.json from Supabase query results (embedded)."""
import json, copy, os
from datetime import datetime, timezone, timedelta
from calendar import monthrange

REPO_ROOT = "/sessions/serene-laughing-faraday/mnt/Iridium"

BUDDY = "1dedd6dc-b11a-448b-9bb8-cf4865237bf8"
IRID  = "a688853e-24e2-4eb2-b2b9-e69545aeafc7"
STORE_TO_KEY = {BUDDY: "buddy", IRID: "iridium"}

# ------------------- Query results -------------------
MASTER = [
  {"store_id":BUDDY,"farmer_bucket":"barbara","tipo":"afiliado","total":29,"venderam":0,"postaram":0,"faturamento":0,"pedidos":0,"leads_mes":0,"dormentes":29},
  {"store_id":BUDDY,"farmer_bucket":"barbara","tipo":"creator","total":54,"venderam":2,"postaram":5,"faturamento":632.4,"pedidos":3,"leads_mes":0,"dormentes":50},
  {"store_id":BUDDY,"farmer_bucket":"brion","tipo":"afiliado","total":203,"venderam":6,"postaram":0,"faturamento":3334.55,"pedidos":16,"leads_mes":0,"dormentes":197},
  {"store_id":BUDDY,"farmer_bucket":"brion","tipo":"creator","total":34,"venderam":1,"postaram":6,"faturamento":253.3,"pedidos":1,"leads_mes":0,"dormentes":33},
  {"store_id":BUDDY,"farmer_bucket":"gabi","tipo":"creator","total":9,"venderam":0,"postaram":1,"faturamento":0,"pedidos":0,"leads_mes":0,"dormentes":0},
  {"store_id":IRID,"farmer_bucket":"carol","tipo":"afiliado","total":74,"venderam":2,"postaram":0,"faturamento":702.88,"pedidos":3,"leads_mes":0,"dormentes":72},
  {"store_id":IRID,"farmer_bucket":"carol","tipo":"creator","total":37,"venderam":2,"postaram":9,"faturamento":654.42,"pedidos":3,"leads_mes":0,"dormentes":32},
  {"store_id":IRID,"farmer_bucket":"guilherme","tipo":"afiliado","total":52,"venderam":0,"postaram":0,"faturamento":0,"pedidos":0,"leads_mes":0,"dormentes":52},
  {"store_id":IRID,"farmer_bucket":"guilherme","tipo":"creator","total":58,"venderam":2,"postaram":12,"faturamento":280.48,"pedidos":2,"leads_mes":0,"dormentes":48},
]

MOM = [
  {"store_id":BUDDY,"farmer_bucket":"barbara","faturamento_m1":12446.80},
  {"store_id":BUDDY,"farmer_bucket":"brion","faturamento_m1":44378.18},
  {"store_id":BUDDY,"farmer_bucket":"gabi","faturamento_m1":330.22},
  {"store_id":IRID,"farmer_bucket":"carol","faturamento_m1":16212.53},
  {"store_id":IRID,"farmer_bucket":"guilherme","faturamento_m1":18480.42},
]

SEM_FARMER = [
  {"store_id":BUDDY,"tipo":"afiliado","total":12,"venderam":0,"postaram":0,"faturamento":0,"pedidos":0,"leads_mes":0,"dormentes":3,"faturamento_m1":0},
  {"store_id":BUDDY,"tipo":"creator","total":5,"venderam":1,"postaram":0,"faturamento":253.3,"pedidos":1,"leads_mes":1,"dormentes":3,"faturamento_m1":6202.47},
  {"store_id":IRID,"tipo":"afiliado","total":11,"venderam":2,"postaram":0,"faturamento":1597.87,"pedidos":8,"leads_mes":0,"dormentes":7,"faturamento_m1":19989.66},
  {"store_id":IRID,"tipo":"creator","total":1,"venderam":0,"postaram":1,"faturamento":0,"pedidos":0,"leads_mes":0,"dormentes":0,"faturamento_m1":0},
]

TOTAIS = [
  {"store_id":BUDDY,"tipo":"afiliado","total":244,"venderam":6,"postaram":0,"faturamento":3334.55,"pedidos":16,"leads_mes":0,"leads_30d":9,"dormentes":229,"faturamento_m1":27016.71},
  {"store_id":BUDDY,"tipo":"creator","total":102,"venderam":4,"postaram":12,"faturamento":1139.0,"pedidos":5,"leads_mes":1,"leads_30d":12,"dormentes":86,"faturamento_m1":36340.96},
  {"store_id":IRID,"tipo":"afiliado","total":137,"venderam":4,"postaram":0,"faturamento":2300.75,"pedidos":11,"leads_mes":0,"leads_30d":2,"dormentes":131,"faturamento_m1":23896.79},
  {"store_id":IRID,"tipo":"creator","total":96,"venderam":4,"postaram":22,"faturamento":934.90,"pedidos":5,"leads_mes":0,"leads_30d":12,"dormentes":80,"faturamento_m1":30785.82},
]

CONV = [
  {"store_id":BUDDY,"leads_total":21,"converteram":2,"dias_medios":3.0},
  {"store_id":IRID,"leads_total":14,"converteram":4,"dias_medios":9.8},
]

EVOL = [
  {"store_id":BUDDY,"sales_date":"2026-06-01","acumulado":2354.50},
  {"store_id":BUDDY,"sales_date":"2026-06-02","acumulado":4473.55},
  {"store_id":IRID,"sales_date":"2026-06-01","acumulado":3006.18},
  {"store_id":IRID,"sales_date":"2026-06-02","acumulado":3235.65},
]

TOP = [
  {"store_id":BUDDY,"farmer_bucket":"barbara","username":"caramelo_tiao","name":"Daiane","receita":379.1,"rk":1},
  {"store_id":BUDDY,"farmer_bucket":"barbara","username":"harrymofadinho","name":"Giovana","receita":253.3,"rk":2},
  {"store_id":BUDDY,"farmer_bucket":"brion","username":"adotadasoficial","name":"Débora","receita":2245.70,"rk":1},
  {"store_id":BUDDY,"farmer_bucket":"brion","username":"dra_vetnutri","name":"Érica Vidal","receita":253.3,"rk":2},
  {"store_id":BUDDY,"farmer_bucket":"brion","username":"bernardo_goldenr","name":"Samantha","receita":253.3,"rk":3},
  {"store_id":BUDDY,"farmer_bucket":"brion","username":"aslute_kira","name":"debora","receita":253.3,"rk":4},
  {"store_id":BUDDY,"farmer_bucket":"brion","username":"2dogsemeio","name":"Paulinne","receita":253.3,"rk":5},
  {"store_id":BUDDY,"farmer_bucket":"brion","username":"maya_bully22","name":"fernanda","receita":202.3,"rk":6},
  {"store_id":BUDDY,"farmer_bucket":"brion","username":"petsko.nutrivet","name":"IANA CAROLINE","receita":126.65,"rk":7},
  {"store_id":IRID,"farmer_bucket":"carol","username":"camilepezzin","name":"Camile","receita":535.44,"rk":1},
  {"store_id":IRID,"farmer_bucket":"carol","username":"fernandosantoforte","name":"Fernando","receita":452.14,"rk":2},
  {"store_id":IRID,"farmer_bucket":"carol","username":"gabiahnert","name":"Gabriela","receita":250.74,"rk":3},
  {"store_id":IRID,"farmer_bucket":"carol","username":"isabelleramalho1","name":"isabelle","receita":118.98,"rk":4},
  {"store_id":IRID,"farmer_bucket":"guilherme","username":"felipesart","name":"Felipe","receita":169.99,"rk":1},
  {"store_id":IRID,"farmer_bucket":"guilherme","username":"andreresende20","name":"André","receita":110.49,"rk":2},
]

FARMER_COLORS = {
  "brion":"#3B82F6","barbara":"#EC4899","alice":"#10B981","gabi":"#F59E0B","doug":"#8B5CF6",
  "carol":"#EF4444","guilherme":"#06B6D4","vitoria":"#A855F7",
  "sem_farmer":"#6B7280","compartilhado":"#9CA3AF",
}

# ------------------- Helpers -------------------
def r2(v):
    return round(float(v), 2)

def mom(now, m1):
    if not m1 or float(m1) == 0:
        return None
    return round((float(now) - float(m1)) / float(m1) * 100, 1)

def find(rows, **kw):
    out = [r for r in rows if all(r.get(k) == v for k,v in kw.items())]
    return out

# ------------------- Load farmers config -------------------
farmers_cfg = json.load(open(f"{REPO_ROOT}/data/farmers.json"))
mes_ref = "2026-06"
m1_ref  = "2026-05"

# ------------------- Load current json (for historico) -------------------
old = json.load(open(f"{REPO_ROOT}/data/dashboard.json"))
old_mes = old.get("meta",{}).get("mesReferencia")
historico = old.get("historico", {}) or {}
if old_mes and old_mes != mes_ref:
    snap = copy.deepcopy(old.get("marcas", {}))
    for mk in snap:
        snap[mk]["_closed"] = True
    historico[old_mes] = snap

# ------------------- Meta -------------------
# BRT now = UTC-3
now_utc = datetime.now(timezone.utc)
brt_now = now_utc.astimezone(timezone(timedelta(hours=-3)))
dias_no_mes = monthrange(brt_now.year, brt_now.month)[1]
dia_atual = brt_now.day

meta = {
    "geradoEm": brt_now.strftime("%Y-%m-%dT%H:%M:%S-03:00"),
    "mesReferencia": mes_ref,
    "schemaVersion": 3,
    "diasNoMes": dias_no_mes,
    "diaAtual": dia_atual,
}

# ------------------- Build per marca -------------------
def build_marca(store_id, marca_key):
    cfg = farmers_cfg["marcas"][marca_key]
    farmers_tags = cfg["farmers_tags"]
    display = cfg["farmer_display_names"]
    name = cfg["name"]
    emoji = cfg["logoEmoji"]

    meta_mensal = farmers_cfg["metas_mensais"].get(marca_key, {}).get(mes_ref)
    if meta_mensal is None:
        # fallback to latest known meta
        metas = farmers_cfg["metas_mensais"].get(marca_key, {})
        meta_mensal = max(metas.values()) if metas else 0

    meta_sdr = farmers_cfg["metas_sdr"].get(marca_key, {}).get(mes_ref)
    if meta_sdr is None:
        metas_s = farmers_cfg["metas_sdr"].get(marca_key, {})
        meta_sdr = max(metas_s.values()) if metas_s else 0

    # ---- totais marca ----
    tot_creator = find(TOTAIS, store_id=store_id, tipo="creator")
    tot_afi     = find(TOTAIS, store_id=store_id, tipo="afiliado")
    tc = tot_creator[0] if tot_creator else {"total":0,"venderam":0,"postaram":0,"faturamento":0,"pedidos":0,"leads_mes":0,"leads_30d":0,"dormentes":0,"faturamento_m1":0}
    ta = tot_afi[0] if tot_afi else {"total":0,"venderam":0,"postaram":0,"faturamento":0,"pedidos":0,"leads_mes":0,"leads_30d":0,"dormentes":0,"faturamento_m1":0}

    faturamento_creators = r2(tc["faturamento"])
    faturamento_afiliados = r2(ta["faturamento"])
    faturamento_total = r2(faturamento_creators + faturamento_afiliados)
    faturamento_m1_total = r2(float(tc["faturamento_m1"]) + float(ta["faturamento_m1"]))
    pedidos_creators = int(tc["pedidos"])
    pedidos_afiliados = int(ta["pedidos"])
    pedidos_total = pedidos_creators + pedidos_afiliados
    ticket_medio = r2(faturamento_total / pedidos_total) if pedidos_total else 0.0

    # ---- evolução diária ----
    evol_pts = sorted([r for r in EVOL if r["store_id"]==store_id], key=lambda r: r["sales_date"])
    evol_map = {int(r["sales_date"].split("-")[2]): r2(r["acumulado"]) for r in evol_pts}
    evolucao = []
    last = 0.0
    for d in range(1, dias_no_mes+1):
        if d > dia_atual:
            break
        if d in evol_map:
            last = evol_map[d]
        evolucao.append({"dia": d, "realizado_acumulado": last})

    # ---- farmers (incluindo sem_farmer) ----
    farmers_out = []
    for tag in farmers_tags:
        rows_c = find(MASTER, store_id=store_id, farmer_bucket=tag, tipo="creator")
        rows_a = find(MASTER, store_id=store_id, farmer_bucket=tag, tipo="afiliado")
        rc = rows_c[0] if rows_c else {"total":0,"venderam":0,"postaram":0,"faturamento":0,"pedidos":0,"leads_mes":0,"dormentes":0}
        ra = rows_a[0] if rows_a else {"total":0,"venderam":0,"postaram":0,"faturamento":0,"pedidos":0,"leads_mes":0,"dormentes":0}
        fat_now = r2(float(rc["faturamento"]) + float(ra["faturamento"]))
        m1_rows = find(MOM, store_id=store_id, farmer_bucket=tag)
        fat_m1 = r2(float(m1_rows[0]["faturamento_m1"])) if m1_rows else 0.0
        pedidos = int(rc["pedidos"]) + int(ra["pedidos"])
        # top creators (filter receita > 0 already)
        tops = [r for r in TOP if r["store_id"]==store_id and r["farmer_bucket"]==tag]
        tops.sort(key=lambda r: r["rk"])
        top_creators = [{"username": t["username"], "name": (t["name"] or "").strip(), "receita": r2(t["receita"])} for t in tops[:8]]
        farmers_out.append({
            "id": tag,
            "nome": display.get(tag, tag.title()),
            "color": FARMER_COLORS.get(tag, "#9CA3AF"),
            "faturamento": fat_now,
            "faturamento_m1": fat_m1,
            "mom_pct": mom(fat_now, fat_m1),
            "creators_total": int(rc["total"]) + int(ra["total"]),
            "creators_que_venderam": int(rc["venderam"]) + int(ra["venderam"]),
            "creators_que_postaram": int(rc["postaram"]) + int(ra["postaram"]),
            "leads_no_mes": int(rc["leads_mes"]) + int(ra["leads_mes"]),
            "dormentes": int(rc["dormentes"]) + int(ra["dormentes"]),
            "pedidos": pedidos,
            "ticket_medio": r2(fat_now / pedidos) if pedidos else 0.0,
            "creators_pool": {
                "total": int(rc["total"]), "venderam": int(rc["venderam"]), "postaram": int(rc["postaram"]),
                "faturamento": r2(rc["faturamento"]), "pedidos": int(rc["pedidos"]), "dormentes": int(rc["dormentes"]),
            },
            "afiliados_pool": {
                "total": int(ra["total"]), "venderam": int(ra["venderam"]),
                "faturamento": r2(ra["faturamento"]), "pedidos": int(ra["pedidos"]), "dormentes": int(ra["dormentes"]),
            },
            "top_creators": top_creators,
        })

    # sem_farmer bucket
    sf_c_rows = find(SEM_FARMER, store_id=store_id, tipo="creator")
    sf_a_rows = find(SEM_FARMER, store_id=store_id, tipo="afiliado")
    sf_c = sf_c_rows[0] if sf_c_rows else {"total":0,"venderam":0,"postaram":0,"faturamento":0,"pedidos":0,"leads_mes":0,"dormentes":0,"faturamento_m1":0}
    sf_a = sf_a_rows[0] if sf_a_rows else {"total":0,"venderam":0,"postaram":0,"faturamento":0,"pedidos":0,"leads_mes":0,"dormentes":0,"faturamento_m1":0}
    sf_total = int(sf_c["total"]) + int(sf_a["total"])
    if sf_total > 0:
        fat_now = r2(float(sf_c["faturamento"]) + float(sf_a["faturamento"]))
        fat_m1 = r2(float(sf_c["faturamento_m1"]) + float(sf_a["faturamento_m1"]))
        pedidos = int(sf_c["pedidos"]) + int(sf_a["pedidos"])
        farmers_out.append({
            "id": "sem_farmer",
            "nome": "Sem Farmer",
            "color": FARMER_COLORS["sem_farmer"],
            "faturamento": fat_now,
            "faturamento_m1": fat_m1,
            "mom_pct": mom(fat_now, fat_m1),
            "creators_total": sf_total,
            "creators_que_venderam": int(sf_c["venderam"]) + int(sf_a["venderam"]),
            "creators_que_postaram": int(sf_c["postaram"]) + int(sf_a["postaram"]),
            "leads_no_mes": int(sf_c["leads_mes"]) + int(sf_a["leads_mes"]),
            "dormentes": int(sf_c["dormentes"]) + int(sf_a["dormentes"]),
            "pedidos": pedidos,
            "ticket_medio": r2(fat_now / pedidos) if pedidos else 0.0,
            "creators_pool": {
                "total": int(sf_c["total"]), "venderam": int(sf_c["venderam"]), "postaram": int(sf_c["postaram"]),
                "faturamento": r2(sf_c["faturamento"]), "pedidos": int(sf_c["pedidos"]), "dormentes": int(sf_c["dormentes"]),
            },
            "afiliados_pool": {
                "total": int(sf_a["total"]), "venderam": int(sf_a["venderam"]),
                "faturamento": r2(sf_a["faturamento"]), "pedidos": int(sf_a["pedidos"]), "dormentes": int(sf_a["dormentes"]),
            },
            "top_creators": [],
            "_sem_farmer": True,
        })

    # ---- ranking ----
    ranked = sorted(farmers_out, key=lambda f: f["faturamento"], reverse=True)
    ranking = []
    trofeu_idx = 0
    trofeus = ["ouro", "prata", "bronze"]
    for i, f in enumerate(ranked):
        is_sf = f.get("_sem_farmer", False)
        if is_sf:
            tr = None
        else:
            tr = trofeus[trofeu_idx] if trofeu_idx < 3 else None
            trofeu_idx += 1
        ranking.append({
            "posicao": i+1,
            "id": f["id"],
            "nome": f["nome"],
            "faturamento": f["faturamento"],
            "mom_pct": f["mom_pct"],
            "trofeu": tr,
            "sem_farmer": is_sf,
        })

    # ---- SDR ----
    conv_row = find(CONV, store_id=store_id)
    conv = conv_row[0] if conv_row else {"leads_total":0,"converteram":0,"dias_medios":0}
    leads_total = int(conv["leads_total"])
    converteram = int(conv["converteram"])
    sdr = {
        "prospeccoes_total": int(tc["leads_mes"]) + int(ta["leads_mes"]),
        "meta": int(meta_sdr),
        "convertidos": converteram,
        "conversao_pct": round((converteram / leads_total * 100), 1) if leads_total else 0.0,
        "dias_medios_1venda": float(conv["dias_medios"]) if conv["dias_medios"] else 0.0,
    }

    # Default color per marca
    marca_color = "#F97316" if marca_key == "buddy" else "#7C3AED"

    return {
        "id": marca_key,
        "name": name,
        "logoEmoji": emoji,
        "color": marca_color,
        "meta_mensal": meta_mensal,
        "faturamento_total": faturamento_total,
        "faturamento_m1": faturamento_m1_total,
        "mom_pct": mom(faturamento_total, faturamento_m1_total),
        "creators_total": int(tc["total"]),
        "afiliados_total": int(ta["total"]),
        "total_aprovados": int(tc["total"]) + int(ta["total"]),
        "creators_que_venderam": int(tc["venderam"]),
        "creators_que_postaram": int(tc["postaram"]),
        "afiliados_que_venderam": int(ta["venderam"]),
        "creators_dormentes": int(tc["dormentes"]),
        "afiliados_dormentes": int(ta["dormentes"]),
        "faturamento_creators": faturamento_creators,
        "faturamento_afiliados": faturamento_afiliados,
        "pedidos_creators": pedidos_creators,
        "pedidos_afiliados": pedidos_afiliados,
        "pedidos_total": pedidos_total,
        "ticket_medio": ticket_medio,
        "evolucao_diaria": evolucao,
        "farmers": farmers_out,
        "ranking_farmers": ranking,
        "sdr": sdr,
    }

marcas = {
    "buddy": build_marca(BUDDY, "buddy"),
    "iridium": build_marca(IRID, "iridium"),
}

new_json = {
    "meta": meta,
    "marcas": marcas,
    "historico": historico,
}

# Preserve marca color/emoji from previous if exists
for mk in ("buddy","iridium"):
    if mk in old.get("marcas", {}):
        old_color = old["marcas"][mk].get("color")
        if old_color:
            new_json["marcas"][mk]["color"] = old_color

# ------------------- Validate -------------------
assert "historico" in new_json, "historico missing"
for mk, m in new_json["marcas"].items():
    assert "prospeccoes_total" in m["sdr"], f"prospeccoes_total missing in {mk}"

# ------------------- Write -------------------
out_path = f"{REPO_ROOT}/data/dashboard.json"
with open(out_path, "w") as f:
    json.dump(new_json, f, ensure_ascii=False, indent=2)

print("OK", "buddy fat:", marcas["buddy"]["faturamento_total"], "iridium fat:", marcas["iridium"]["faturamento_total"])
print("historico keys:", list(historico.keys()))
print("mesReferencia:", meta["mesReferencia"], "dia:", dia_atual, "/", dias_no_mes)
