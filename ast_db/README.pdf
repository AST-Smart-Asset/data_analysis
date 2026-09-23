# Smart Asset Inventory & Predictive Maintenance — Database (AST)

Badr University in Assiut · DevHub Summer 2026 · Project 3 · Squad 3

PostgreSQL schema for the 12-table ERD, plus a full synthetic demo dataset
and a reporting layer built for Power BI.

Built and tested on **PostgreSQL 16**. Works on 14+.

---

## What is in here

```
ast_db/
├── ast_full_dump.sql              one-file restore: schema + data + views
├── sql/
│   ├── 01_schema.sql              12 tables, enums, indexes, triggers, risk engine
│   ├── 02_seed_data.sql           the synthetic demo dataset
│   ├── 03_reporting_views.sql     dim_* / fact_* / kpi_* views for Power BI
│   └── 04_rls_security_optional.sql   roles + Row Level Security  (OPTIONAL)
└── csv/
    ├── tables/                    the 12 raw tables as CSV
    └── powerbi/                   the reporting views as CSV
```

---

## Setup

### Option A — restore the dump (fastest)

```bash
createdb ast
psql -d ast -f ast_full_dump.sql
```

### Option B — run the scripts in order (what you will do in CI)

```bash
createdb ast
psql -d ast -v ON_ERROR_STOP=1 -f sql/01_schema.sql
psql -d ast -v ON_ERROR_STOP=1 -f sql/02_seed_data.sql
psql -d ast -v ON_ERROR_STOP=1 -f sql/03_reporting_views.sql
```

Roughly 30 seconds. The seed is **deterministic** — no `random()` anywhere,
every value comes from an md5 of the row key — so everyone on the squad
gets byte-identical data and your Power BI screenshots stay reproducible.

### Option C — Docker

```bash
docker run --name ast-db -e POSTGRES_PASSWORD=devhub -p 5432:5432 -d postgres:16
docker cp ast_full_dump.sql ast-db:/tmp/
docker exec -u postgres ast-db createdb ast
docker exec -u postgres ast-db psql -d ast -f /tmp/ast_full_dump.sql
```

### Do not run `04_rls_security_optional.sql` yet

It turns on organisational-scope RBAC at the database level. You want it in
the API, but if you load it and then connect Power BI with the wrong role,
every table comes back empty and it looks like the seed failed. Read the
header of that file first. If you do load it, connect Power BI as
`ast_report`, which is read-only and exempt.

---

## Connecting Power BI

**Home → Get Data → PostgreSQL database**

| Field | Value |
|---|---|
| Server | `localhost:5432` |
| Database | `ast` |
| Data Connectivity mode | **Import** |

Power BI needs the Npgsql provider. If Power BI complains about a missing
provider, install **Npgsql** with the *GAC installation* option ticked, then
restart Power BI.

### Which objects to import

Import **only** the `dim_*` and `fact_*` views. The raw tables are normalised
for the application, not for reporting — if you import both you will end up
with duplicate relationships and ambiguous filters.

| View | Rows | Use it for |
|---|---:|---|
| `dim_date` | 4,018 | date dimension, 2019–2029 |
| `dim_org_unit` | 10 | university / campus / college / department as columns |
| `dim_location` | 69 | campus / building / floor / room as columns |
| `dim_category` | 17 | category + its parent group + useful life |
| `dim_user` | 24 | users with roles rolled up, no password hash |
| `fact_asset` | 420 | the inventory pages — one row per asset, fully joined |
| `fact_work_order` | 2,004 | maintenance pages |
| `fact_asset_event` | 2,635 | custody and movement history |
| `fact_document` | 730 | procurement and warranty evidence |
| `fact_audit_log` | 738 | the security page |

`kpi_*` views are pre-aggregated answers to the AST-FR-08 dashboard
requirements. Handy for a quick card, but build your real measures in DAX
against the fact views so slicers work properly.

### Relationships to create

| From | To | Cardinality |
|---|---|---|
| `fact_asset[location_id]` | `dim_location[location_id]` | many → 1 |
| `fact_asset[category_id]` | `dim_category[category_id]` | many → 1 |
| `fact_asset[org_unit_id]` | `dim_org_unit[org_unit_id]` | many → 1 |
| `fact_asset[custodian_user_id]` | `dim_user[user_id]` | many → 1 |
| `fact_asset[purchase_date]` | `dim_date[date_key]` | many → 1 |
| `fact_work_order[asset_id]` | `fact_asset[asset_id]` | many → 1 |
| `fact_work_order[technician_user_id]` | `dim_user[user_id]` | many → 1 |
| `fact_work_order[completed_date]` | `dim_date[date_key]` | many → 1 (active) |
| `fact_asset_event[asset_id]` | `fact_asset[asset_id]` | many → 1 |
| `fact_document[asset_id]` | `fact_asset[asset_id]` | many → 1 |
| `fact_audit_log[actor_user_id]` | `dim_user[user_id]` | many → 1 |

Mark `dim_date` as the date table: **Modeling → Mark as date table →
`date_key`**. Build hierarchies on `dim_location` (campus → building →
floor → room) and `dim_org_unit` (university → campus → college →
department) so drill-down works.

Two date columns on `fact_work_order` point at `dim_date`
(`scheduled_date` and `completed_date`). Only one relationship can be
active — make `completed_date` active and reach the other with
`USERELATIONSHIP` in a measure.

### Working from CSV instead

If you cannot reach a Postgres instance, **Get Data → Folder →
`csv/powerbi`** loads the same model. The CSVs are a snapshot, so
date-relative buckets (`overdue`, `expiring in 30 days`) are frozen at
export time. Live connection is better for a demo.

---

## The dataset

| | |
|---|---:|
| Org units | 10 (university → campus → 2 colleges + 2 admin units → 4 departments) |
| Locations | 69 (1 campus, 3 buildings, 6 floors, 56 rooms/offices, 3 stores) |
| Users | 24 across 7 roles, including 1 disabled and 1 locked account |
| Asset categories | 17 (4 groups, 13 leaf categories) |
| Maintenance templates | 12 (calendar, runtime and condition triggers) |
| **Assets** | **420** across 3 buildings, purchased over the last 7 years |
| Documents | 730 invoice / warranty / manual / retirement records |
| **Work orders** | **2,004** over a 3-year history |
| Asset events | 2,635 registration, transfer, custody and service records |
| Audit log | 738 sanitised security events over 6 months |

Deliberate variety so the dashboards have something to show:

- 61 assets **overdue** for maintenance, 24 due within 30 days
- 220 **expired** warranties, 14 expiring within 90 days
- 22 assets **retired** with a reason, still visible in reporting
- 3 assets marked **lost**, a few still in `draft`
- Risk bands spread across low / medium / high / critical
- 2 documents that are **not downloadable** (one pending scan, one
  quarantined as infected) — the API must refuse to sign a URL for these
- 303 corrective vs 1,622 preventive jobs, so the preventive ratio KPI
  is meaningful

Everything is synthetic. No real student, staff, supplier or invoice.
Demo password for every seeded account is `DevHub#2026`, stored only as a
bcrypt hash.

---

## Chart ideas that the data supports

- Asset count and value by building → college → room (drill-down)
- Maintenance due / overdue gauge, sliced by category
- Preventive vs corrective ratio over time (`kpi_maintenance_monthly`)
- MTTR trend, and MTTR by technician (`fact_work_order[repair_hours]`)
- Downtime hours by category and month
- Warranty expiry funnel by bucket, with purchase cost at risk
- Lifecycle age vs useful life — `life_consumed_ratio` against a 1.0 line
- Risk review queue table with `risk_reasons_text` as a tooltip
- Failed-login heatmap by hour and day (`fact_audit_log`)
- Cost of ownership: `maintenance_to_purchase_ratio` by category

---

## Notes for the API pod

**Passwords.** The database only accepts something shaped like an Argon2id
or bcrypt hash, enforced by both a `CHECK` and a `BEFORE` trigger. Hash in
the API; never send a plain password to the database.

**Session context.** The RBAC helpers read
`current_setting('app.current_user_id')`. Every request must run
`SET LOCAL app.current_user_id = '<uuid>'` inside its transaction. No user
id means no rows.

**Preventive vs corrective.** There is no `kind` column. A work order with
a `template_id` is preventive; one without is a corrective (fault) job.
`fact_work_order.work_order_kind` derives this for you.

**Closing a work order** fires a trigger that updates
`assets.next_maintenance_due_at`, sets `work_orders.next_due_at` from the
template interval, and writes a `maintenance_completed` row to
`asset_events`. Do not do this by hand in the API — you will double-write.

**Append-only tables.** `asset_events` and `audit_log` reject `UPDATE` and
`DELETE` at the trigger level. Corrections are new rows, not edits.

**Retired assets are read-only.** Once `status` is `retired` or `disposed`,
any further update raises an exception unless the connection is the service
role.

**Documents are metadata only.** The file itself lives in private object
storage. `storage_key` must not be a public URL — a `CHECK` enforces it.
Never serve a document whose `malware_scan_status` is not `clean`.

**The risk engine is advisory.** `assess_asset_risk(asset_id, horizon_days)`
writes `risk_band` and `risk_reasons` and nothing else. It never creates a
work order, changes custody or retires anything. Run
`SELECT assess_all_assets(30);` as a nightly job. This is the deterministic
baseline the AST brief requires — the Python model, when it exists, has to
beat it or you report that it did not.

---

## Known limitations of the 12-table design

Worth saying out loud at the architecture review, because the Tech Lead
will ask:

1. **Supplier, purchase order, invoice and warranty are flattened into
   `asset_documents` as text columns.** There is no supplier table, so a
   supplier name can be spelled two ways and no foreign key stops it. Cost
   reporting by supplier is possible but fragile. Splitting these into
   their own tables is the first thing to do if the ERD is allowed to grow.
2. **No stocktake tables.** AST-FR-07 is a *Should*, and it currently has
   nowhere to store a session or an observation.
3. **Custody has no approval record.** AST-FR-04 asks for transfers "with
   approval". Today the transfer is a pair of `asset_events` rows; there is
   no pending state and no approver column that a query can enforce.
4. **Retirement has no approval record either.** `retirement_reason` and
   `retired_at` exist, but not who approved it or against what evidence.
5. **No import batch/error table.** AST-FR-02 asks for an import error
   report; today that has to live outside the database.
6. **Risk output has no history.** `assets.risk_band` is overwritten on
   every run, so you cannot show precision/recall over time or log which
   model version produced a band — both required by the AI release gate.

None of these block the MVP. All of them are cheap to add later, and each
is one table.
