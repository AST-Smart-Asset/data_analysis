# AST Dashboard — API Filter Specification

For: backend/API developer
From: Squad 3 — BI/data pod
Purpose: the query filters the "Institutional Metrics" dashboard needs, so
every card and the campus selector can be wired to real data with correct
RBAC scoping.

This spec assumes the API sits on top of the `ast` PostgreSQL database
(schema `sql/01_schema.sql`, views `sql/03_reporting_views.sql`).

---

## 1. Global scope filter — the campus/org selector

The dropdown at the top of the dashboard ("North Science & Medical
Campus") is not just a UI filter — it must be enforced server-side, or a
department manager could switch it and see another college's assets.

**Every endpoint below must accept:**

| Query param | Type | Meaning |
|---|---|---|
| `org_unit_id` | uuid, optional | Scope to this org unit and everything under it |
| `building_id` | uuid, optional | Scope to one building (a `locations` row where `location_type='building'`) |

**Enforcement rule:** even if the client omits `org_unit_id`, the API must
intersect the request with the caller's own RBAC scope (from
`user_roles.org_unit_id`, expanded to descendants — see
`visible_org_units()` in `04_rls_security_optional.sql`). The dropdown
narrows within what the user is already allowed to see; it never widens
it. If RLS is enabled and the connection runs as `ast_app` with
`SET LOCAL app.current_user_id`, this is enforced automatically and the
API does not need to duplicate the logic.

**Populate the dropdown itself with:**
```sql
SELECT id, name, unit_type FROM org_units WHERE id IN (SELECT org_unit_id FROM visible_org_units());
```

---

## 2. Card-by-card filter requirements

### Total Assets
```sql
SELECT count(*) FROM fact_asset WHERE org_unit_id = :scope;
```
Optional additional filters the UI may want later: `category_id`,
`building`, `status`.

### Active Service (count + %)
```sql
SELECT count(*) FILTER (WHERE is_active) AS active,
       count(*)                          AS total
FROM fact_asset WHERE org_unit_id = :scope;
```
Percentage = `active / total`, computed client-side or in the API — not
stored, always derived live.

### Maintenance (open work orders + urgent count)
```sql
SELECT count(*) FILTER (WHERE is_outstanding)                                   AS open_orders,
       count(*) FILTER (WHERE is_outstanding AND priority IN ('high','critical')) AS urgent_orders
FROM fact_work_order WHERE org_unit_id = :scope;
```
**Filter params the UI should expose here (Should, not MVP-blocking):**
`priority` (low/medium/high/critical), `status`
(open/scheduled/in_progress), `work_order_kind` (preventive/corrective).

### Overdue Maintenance
```sql
SELECT count(*) FROM fact_work_order
WHERE org_unit_id = :scope AND is_overdue = true;
```
Drill-down list (for when the user clicks the card) needs: `asset_tag`,
`building`, `room`, `priority`, `days_overdue`, `technician_name` — all
already present in `fact_work_order`.

### Warranty <60 days
```sql
SELECT count(*) FROM fact_asset
WHERE org_unit_id = :scope
  AND warranty_days_left BETWEEN 0 AND 60;
```
Make the threshold (`60`) a query param (`warranty_days`) rather than a
hard-coded number — the client may want a 30/60/90 toggle later, same as
`kpi_warranty` already buckets it.

### AI High-Risk
```sql
SELECT count(*) FROM fact_asset
WHERE org_unit_id = :scope
  AND risk_band IN ('high','critical');
```
**Important for this card specifically:** the risk band is advisory
output only (see `assess_asset_risk()` in the schema). The API must never
let this endpoint, or any endpoint reachable from this card's drill-down,
trigger a write — no auto-creating a work order, no auto-changing asset
status. Clicking into "AI High-Risk" should open `kpi_risk_queue` as a
**read-only review list**; any action on it (acknowledge / create work
order / dismiss) must be a separate, explicit, human-triggered request.

### Category distribution (donut)
```sql
SELECT category_group_name, count(*) AS asset_count
FROM fact_asset WHERE org_unit_id = :scope
GROUP BY category_group_name;
```

---

## 3. Filters to support on the Assets list page (for the "Assets" tab)

These are the columns a custodian or auditor will want to filter/search by.
All are already present on `fact_asset`:

| Filter | Column | Notes |
|---|---|---|
| Search by tag/serial | `asset_tag`, `serial_number` | free-text `ILIKE` |
| Building / Floor / Room | `building`, `floor`, `room` | cascading dropdowns, driven by `dim_location` |
| Category | `category_code`, `category_group_name` | |
| Status | `status` | draft/active/in_transfer/in_maintenance/retired/disposed/lost |
| Condition | `condition` | new/good/fair/poor/failed/unknown |
| Custodian | `custodian_user_id` | dropdown of users in scope |
| Lifecycle stage | `lifecycle_stage` | early life / mid life / near end of life / past useful life |
| Maintenance bucket | `maintenance_bucket` | not scheduled / overdue / due in 30 days / due in 90 days / scheduled |
| Warranty bucket | `warranty_bucket` | no warranty on record / expired / expiring in 30/90 days / covered |
| Risk band | `risk_band` | unknown/low/medium/high/critical |

---

## 4. Search bar (top of the dashboard)

Free-text search should hit at minimum: `asset_tag`, `serial_number`,
`brand`, `model`, and `location_name`. A single `q` query param, matched
with `ILIKE '%...%'` across those columns, covers the "Search by Floor,
Room..." placeholder shown in the design.

---

## 5. What the API must NOT do

- Never return rows outside the caller's RBAC scope regardless of what
  `org_unit_id` the client sends — the server intersects, it doesn't trust.
- Never expose `asset_documents.storage_key` or `sha256_hex` directly to
  the dashboard; a document download must go through a short-lived signed
  URL endpoint that also checks `malware_scan_status = 'clean'`.
- Never let a risk-queue or dashboard endpoint change `assets.status`,
  `assets.custodian_user_id`, or create a `work_orders` row as a side
  effect of a GET request.

---

## 6. Suggested endpoint shape

```
GET /api/dashboard/metrics?org_unit_id=&building_id=
GET /api/dashboard/category-distribution?org_unit_id=
GET /api/assets?org_unit_id=&building=&category=&status=&condition=&risk_band=&maintenance_bucket=&warranty_bucket=&q=&page=&page_size=
GET /api/work-orders?org_unit_id=&status=&priority=&kind=&overdue_only=
GET /api/risk-queue?org_unit_id=&risk_band=
```

All of the above map directly onto `fact_asset` / `fact_work_order` /
`kpi_risk_queue` with a `WHERE org_unit_id = ANY(:visible_scope)` clause
added by the API layer before anything else runs.
