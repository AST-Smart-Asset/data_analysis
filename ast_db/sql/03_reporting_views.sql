-- =====================================================================
-- File 03 : REPORTING VIEWS FOR POWER BI
--
-- The 12 tables are normalised for the application. Power BI is much
-- happier with a small star schema, so this file exposes:
--
--   dim_date, dim_location, dim_org_unit, dim_category, dim_user
--   fact_asset, fact_work_order, fact_asset_event, fact_document,
--   fact_audit_log
--   plus ready-made KPI views for the dashboards in AST-FR-08.
--
-- In Power BI, import the dim_* and fact_* views and join them on the
-- *_id columns. Do not import the raw tables as well - you will end up
-- with duplicate relationships.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- dim_date : a proper date dimension, 2019-01-01 to 2029-12-31.
-- Mark this as the date table in Power BI (Modeling > Mark as date table).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW dim_date AS
SELECT d::date                                        AS date_key,
       EXTRACT(YEAR    FROM d)::int                   AS year,
       EXTRACT(QUARTER FROM d)::int                   AS quarter,
       'Q' || EXTRACT(QUARTER FROM d)::int            AS quarter_name,
       EXTRACT(MONTH   FROM d)::int                   AS month,
       to_char(d, 'Mon')                              AS month_short,
       to_char(d, 'Month')                            AS month_name,
       to_char(d, 'YYYY-MM')                          AS year_month,
       EXTRACT(DAY     FROM d)::int                   AS day_of_month,
       EXTRACT(ISODOW  FROM d)::int                    AS day_of_week,
       to_char(d, 'Dy')                               AS day_name,
       (EXTRACT(ISODOW FROM d) IN (5,6))              AS is_weekend,   -- Fri/Sat
       date_trunc('month', d)::date                   AS month_start,
       (date_trunc('month', d) + interval '1 month - 1 day')::date AS month_end
FROM generate_series(DATE '2019-01-01', DATE '2029-12-31', interval '1 day') d;

-- ---------------------------------------------------------------------
-- dim_org_unit : the organisational tree flattened into columns
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW dim_org_unit AS
WITH RECURSIVE tree AS (
    SELECT o.id, o.parent_id, o.name, o.unit_type, o.is_active,
           o.name::text AS path,
           1            AS depth,
           o.name       AS level_1,
           NULL::text   AS level_2,
           NULL::text   AS level_3,
           NULL::text   AS level_4
    FROM org_units o WHERE o.parent_id IS NULL
    UNION ALL
    SELECT c.id, c.parent_id, c.name, c.unit_type, c.is_active,
           t.path || ' > ' || c.name,
           t.depth + 1,
           t.level_1,
           CASE WHEN t.depth + 1 = 2 THEN c.name ELSE t.level_2 END,
           CASE WHEN t.depth + 1 = 3 THEN c.name ELSE t.level_3 END,
           CASE WHEN t.depth + 1 = 4 THEN c.name ELSE t.level_4 END
    FROM org_units c JOIN tree t ON c.parent_id = t.id
)
SELECT id AS org_unit_id, parent_id AS parent_org_unit_id,
       name AS org_unit_name, unit_type::text AS org_unit_type,
       is_active, depth, path AS org_path,
       level_1 AS university, level_2 AS campus, level_3 AS college, level_4 AS department
FROM tree;

-- ---------------------------------------------------------------------
-- dim_location : campus / building / floor / room as separate columns,
-- which is exactly what a Power BI drill-down hierarchy needs.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW dim_location AS
WITH RECURSIVE tree AS (
    SELECT l.id, l.parent_id, l.org_unit_id, l.location_type, l.name, l.code, l.is_active,
           l.code::text AS path_code,
           l.name::text AS path_name,
           1            AS depth,
           l.name       AS lvl1, NULL::text AS lvl2, NULL::text AS lvl3, NULL::text AS lvl4
    FROM locations l WHERE l.parent_id IS NULL
    UNION ALL
    SELECT c.id, c.parent_id, c.org_unit_id, c.location_type, c.name, c.code, c.is_active,
           t.path_code || '/' || c.code,
           t.path_name || ' > ' || c.name,
           t.depth + 1,
           t.lvl1,
           CASE WHEN t.depth + 1 = 2 THEN c.name ELSE t.lvl2 END,
           CASE WHEN t.depth + 1 = 3 THEN c.name ELSE t.lvl3 END,
           CASE WHEN t.depth + 1 = 4 THEN c.name ELSE t.lvl4 END
    FROM locations c JOIN tree t ON c.parent_id = t.id
)
SELECT t.id AS location_id, t.parent_id AS parent_location_id,
       t.code AS location_code, t.name AS location_name,
       t.location_type::text AS location_type, t.is_active,
       t.depth, t.path_code AS location_path, t.path_name AS location_path_name,
       t.lvl1 AS campus, t.lvl2 AS building, t.lvl3 AS floor, t.lvl4 AS room,
       t.org_unit_id, o.org_unit_name, o.college, o.department
FROM tree t
LEFT JOIN dim_org_unit o ON o.org_unit_id = t.org_unit_id;

-- ---------------------------------------------------------------------
-- dim_category
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW dim_category AS
SELECT c.id AS category_id, c.code AS category_code, c.name AS category_name,
       c.parent_id AS parent_category_id,
       COALESCE(p.code, c.code) AS category_group_code,
       COALESCE(p.name, c.name) AS category_group_name,
       c.useful_life_months,
       round(c.useful_life_months / 12.0, 1) AS useful_life_years,
       c.requires_serial
FROM asset_categories c
LEFT JOIN asset_categories p ON p.id = c.parent_id;

-- ---------------------------------------------------------------------
-- dim_user : one row per user, with the roles rolled up into a string.
-- No password hash is exposed here - reporting never needs it.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW dim_user AS
SELECT u.id AS user_id, u.full_name, u.email::text AS email,
       u.status::text AS user_status, u.mfa_enabled,
       u.last_login_at, u.last_login_at::date AS last_login_date,
       u.failed_login_count,
       (u.locked_until IS NOT NULL AND u.locked_until > now()) AS is_locked,
       COALESCE(string_agg(DISTINCT r.name, ', '), 'No role') AS roles,
       COALESCE(string_agg(DISTINCT o.name, ', '), 'University-wide') AS role_scopes,
       count(DISTINCT ur.id) AS role_grant_count
FROM users u
LEFT JOIN user_roles ur ON ur.user_id = u.id AND (ur.expires_at IS NULL OR ur.expires_at > now())
LEFT JOIN roles r       ON r.id = ur.role_id
LEFT JOIN org_units o   ON o.id = ur.org_unit_id
GROUP BY u.id, u.full_name, u.email, u.status, u.mfa_enabled,
         u.last_login_at, u.failed_login_count, u.locked_until;

-- ---------------------------------------------------------------------
-- fact_asset : one row per asset, everything already joined.
-- This is the main table for the inventory pages.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW fact_asset AS
SELECT
    a.id                                   AS asset_id,
    a.asset_tag,
    a.serial_number,
    a.brand,
    a.model,
    COALESCE(a.brand || ' ' || a.model, a.model, a.brand) AS brand_model,
    a.condition::text                      AS condition,
    a.status::text                         AS status,
    (a.status = 'active')                  AS is_active,
    (a.status IN ('retired','disposed'))   AS is_retired,

    a.category_id, c.category_code, c.category_name, c.category_group_name, c.useful_life_months,
    a.current_location_id AS location_id,
    l.location_code, l.location_name, l.campus, l.building, l.floor, l.room, l.location_path,
    l.org_unit_id, l.org_unit_name, l.college, l.department,

    a.custodian_user_id,
    cu.full_name                           AS custodian_name,
    (a.custodian_user_id IS NOT NULL)      AS has_custodian,

    a.purchase_date,
    date_trunc('month', a.purchase_date)::date AS purchase_month,
    EXTRACT(YEAR FROM a.purchase_date)::int    AS purchase_year,
    a.purchase_cost,

    -- lifecycle age
    (CURRENT_DATE - a.purchase_date)                                        AS age_days,
    round((CURRENT_DATE - a.purchase_date) / 30.44, 1)                      AS age_months,
    round((CURRENT_DATE - a.purchase_date) / 365.25, 2)                     AS age_years,
    CASE WHEN c.useful_life_months IS NULL OR c.useful_life_months = 0 THEN NULL
         ELSE round(((CURRENT_DATE - a.purchase_date) / 30.44) / c.useful_life_months, 3)
    END                                                                     AS life_consumed_ratio,
    CASE WHEN c.useful_life_months IS NULL THEN 'no policy'
         WHEN ((CURRENT_DATE - a.purchase_date) / 30.44) / c.useful_life_months >= 1.0 THEN 'past useful life'
         WHEN ((CURRENT_DATE - a.purchase_date) / 30.44) / c.useful_life_months >= 0.8 THEN 'near end of life'
         WHEN ((CURRENT_DATE - a.purchase_date) / 30.44) / c.useful_life_months >= 0.5 THEN 'mid life'
         ELSE 'early life' END                                              AS lifecycle_stage,

    -- maintenance
    a.next_maintenance_due_at,
    a.next_maintenance_due_at::date         AS next_due_date,
    CASE WHEN a.next_maintenance_due_at IS NULL THEN NULL
         ELSE (a.next_maintenance_due_at::date - CURRENT_DATE) END          AS days_to_due,
    CASE WHEN a.next_maintenance_due_at IS NULL                      THEN 'not scheduled'
         WHEN a.next_maintenance_due_at < now()                      THEN 'overdue'
         WHEN a.next_maintenance_due_at < now() + interval '30 days' THEN 'due in 30 days'
         WHEN a.next_maintenance_due_at < now() + interval '90 days' THEN 'due in 90 days'
         ELSE 'scheduled' END                                               AS maintenance_bucket,

    -- warranty (from the document metadata)
    w.warranty_expires_at,
    CASE WHEN w.warranty_expires_at IS NULL THEN NULL
         ELSE (w.warranty_expires_at - CURRENT_DATE) END                    AS warranty_days_left,
    CASE WHEN w.warranty_expires_at IS NULL                       THEN 'no warranty on record'
         WHEN w.warranty_expires_at <  CURRENT_DATE               THEN 'expired'
         WHEN w.warranty_expires_at <= CURRENT_DATE + 30          THEN 'expiring in 30 days'
         WHEN w.warranty_expires_at <= CURRENT_DATE + 90          THEN 'expiring in 90 days'
         ELSE 'covered' END                                                 AS warranty_bucket,
    w.warranty_provider,
    inv.supplier_name,
    inv.purchase_order_number,
    inv.invoice_number,
    inv.invoice_amount,

    -- maintenance history rollup
    COALESCE(m.work_order_count, 0)        AS work_order_count,
    COALESCE(m.preventive_count, 0)        AS preventive_count,
    COALESCE(m.corrective_count, 0)        AS corrective_count,
    COALESCE(m.corrective_12m, 0)          AS corrective_last_12m,
    COALESCE(m.downtime_minutes, 0)        AS downtime_minutes_total,
    round(COALESCE(m.downtime_minutes, 0) / 60.0, 1) AS downtime_hours_total,
    COALESCE(m.maintenance_cost, 0)        AS maintenance_cost_total,
    CASE WHEN a.purchase_cost IS NULL OR a.purchase_cost = 0 THEN NULL
         ELSE round(COALESCE(m.maintenance_cost, 0) / a.purchase_cost, 3) END AS maintenance_to_purchase_ratio,
    m.last_service_at,
    m.last_service_at::date                AS last_service_date,

    -- advisory risk output (AST-FR-09)
    a.risk_band,
    CASE a.risk_band WHEN 'critical' THEN 4 WHEN 'high' THEN 3
                     WHEN 'medium' THEN 2 WHEN 'low' THEN 1 ELSE 0 END AS risk_rank,
    (SELECT string_agg(x->>'detail', ' | ')
       FROM jsonb_array_elements(a.risk_reasons) x
      WHERE x->>'code' <> 'score')          AS risk_reasons_text,
    (SELECT (x->>'weight')::numeric
       FROM jsonb_array_elements(a.risk_reasons) x
      WHERE x->>'code' = 'score' LIMIT 1)   AS risk_score,

    a.retired_at, a.retired_at::date AS retired_date, a.retirement_reason,
    a.created_at, a.created_at::date AS registered_date
FROM assets a
JOIN dim_category c ON c.category_id = a.category_id
JOIN dim_location l ON l.location_id = a.current_location_id
LEFT JOIN users cu  ON cu.id = a.custodian_user_id
LEFT JOIN LATERAL (
    SELECT d.warranty_expires_at, d.warranty_provider
    FROM asset_documents d
    WHERE d.asset_id = a.id AND d.document_type = 'warranty'
    ORDER BY d.warranty_expires_at DESC NULLS LAST LIMIT 1
) w ON true
LEFT JOIN LATERAL (
    SELECT d.supplier_name, d.purchase_order_number, d.invoice_number, d.invoice_amount
    FROM asset_documents d
    WHERE d.asset_id = a.id AND d.document_type = 'invoice'
    ORDER BY d.created_at LIMIT 1
) inv ON true
LEFT JOIN LATERAL (
    SELECT count(*)                                                        AS work_order_count,
           count(*) FILTER (WHERE wo.template_id IS NOT NULL)              AS preventive_count,
           count(*) FILTER (WHERE wo.template_id IS NULL)                  AS corrective_count,
           count(*) FILTER (WHERE wo.template_id IS NULL
                              AND wo.completed_at > now() - interval '12 months') AS corrective_12m,
           COALESCE(SUM(wo.downtime_minutes), 0)                           AS downtime_minutes,
           COALESCE(SUM(wo.parts_cost + wo.labor_cost), 0)                 AS maintenance_cost,
           MAX(wo.completed_at)                                            AS last_service_at
    FROM work_orders wo
    WHERE wo.asset_id = a.id AND wo.status = 'completed'
) m ON true;

-- ---------------------------------------------------------------------
-- fact_work_order : one row per job, with preventive vs corrective
-- derived from template_id (see the comment on the column).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW fact_work_order AS
SELECT
    wo.id                                   AS work_order_id,
    wo.asset_id,
    a.asset_tag,
    a.category_id, c.category_code, c.category_name,
    a.current_location_id AS location_id,
    l.building, l.floor, l.room, l.location_name,
    l.org_unit_id, l.org_unit_name, l.college, l.department,

    wo.template_id,
    mt.name                                 AS template_name,
    CASE WHEN wo.template_id IS NOT NULL THEN 'preventive' ELSE 'corrective' END AS work_order_kind,

    wo.technician_user_id,
    t.full_name                             AS technician_name,
    wo.priority::text                       AS priority,
    CASE wo.priority WHEN 'critical' THEN 4 WHEN 'high' THEN 3
                     WHEN 'medium' THEN 2 ELSE 1 END AS priority_rank,
    wo.status::text                         AS status,
    (wo.status = 'completed')               AS is_completed,
    (wo.status IN ('open','scheduled','in_progress')) AS is_outstanding,

    wo.scheduled_at, wo.scheduled_at::date  AS scheduled_date,
    wo.started_at,   wo.started_at::date    AS started_date,
    wo.completed_at, wo.completed_at::date  AS completed_date,
    date_trunc('month', wo.completed_at)::date AS completed_month,
    wo.next_due_at,  wo.next_due_at::date   AS next_due_date,

    -- is an outstanding job already late?
    CASE WHEN wo.status IN ('open','scheduled','in_progress') AND wo.scheduled_at < now()
         THEN true ELSE false END           AS is_overdue,
    CASE WHEN wo.status IN ('open','scheduled','in_progress') AND wo.scheduled_at < now()
         THEN (CURRENT_DATE - wo.scheduled_at::date) END AS days_overdue,

    -- repair time: scheduled -> completed is the metric the brief calls MTTR
    CASE WHEN wo.completed_at IS NOT NULL AND wo.started_at IS NOT NULL
         THEN round(EXTRACT(EPOCH FROM (wo.completed_at - wo.started_at)) / 3600.0, 2) END AS repair_hours,
    CASE WHEN wo.completed_at IS NOT NULL AND wo.scheduled_at IS NOT NULL
         THEN round(EXTRACT(EPOCH FROM (wo.completed_at - wo.scheduled_at)) / 3600.0, 2) END AS response_hours,

    wo.parts_cost, wo.labor_cost,
    (wo.parts_cost + wo.labor_cost)         AS total_cost,
    wo.downtime_minutes,
    round(wo.downtime_minutes / 60.0, 2)    AS downtime_hours,
    wo.outcome, wo.completion_notes,
    wo.created_at, wo.created_at::date      AS created_date
FROM work_orders wo
JOIN assets a       ON a.id = wo.asset_id
JOIN dim_category c ON c.category_id = a.category_id
JOIN dim_location l ON l.location_id = a.current_location_id
LEFT JOIN maintenance_templates mt ON mt.id = wo.template_id
LEFT JOIN users t   ON t.id = wo.technician_user_id;

-- ---------------------------------------------------------------------
-- fact_asset_event : the audit trail of movement and custody
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW fact_asset_event AS
SELECT
    e.id                                AS event_id,
    e.asset_id, a.asset_tag,
    e.event_type::text                  AS event_type,
    CASE WHEN e.event_type IN ('transfer_requested','transfer_approved','location_changed','custody_changed')
         THEN 'movement'
         WHEN e.event_type IN ('maintenance_completed') THEN 'maintenance'
         WHEN e.event_type IN ('retirement_requested','retired','disposed') THEN 'lifecycle'
         WHEN e.event_type IN ('created','imported') THEN 'registration'
         ELSE 'other' END               AS event_group,
    e.occurred_at,
    e.occurred_at::date                 AS event_date,
    date_trunc('month', e.occurred_at)::date AS event_month,
    e.actor_user_id, actor.full_name    AS actor_name,
    e.from_location_id, fl.location_name AS from_location, fl.building AS from_building,
    e.to_location_id,   tl.location_name AS to_location,   tl.building AS to_building,
    e.from_custodian_user_id, fc.full_name AS from_custodian,
    e.to_custodian_user_id,   tc.full_name AS to_custodian,
    e.event_data->>'reason'             AS reason,
    e.event_data->>'kind'               AS maintenance_kind,
    e.event_data
FROM asset_events e
JOIN assets a            ON a.id = e.asset_id
LEFT JOIN users actor    ON actor.id = e.actor_user_id
LEFT JOIN dim_location fl ON fl.location_id = e.from_location_id
LEFT JOIN dim_location tl ON tl.location_id = e.to_location_id
LEFT JOIN users fc       ON fc.id = e.from_custodian_user_id
LEFT JOIN users tc       ON tc.id = e.to_custodian_user_id;

-- ---------------------------------------------------------------------
-- fact_document : procurement and warranty evidence.
-- storage_key and the hash are intentionally NOT exposed to reporting.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW fact_document AS
SELECT
    d.id                                AS document_id,
    d.asset_id, a.asset_tag,
    l.org_unit_id, l.org_unit_name, l.building,
    d.document_type::text               AS document_type,
    d.supplier_name,
    d.purchase_order_number,
    d.invoice_number,
    d.invoice_amount,
    d.warranty_provider,
    d.warranty_expires_at,
    CASE WHEN d.warranty_expires_at IS NULL THEN NULL
         ELSE (d.warranty_expires_at - CURRENT_DATE) END AS warranty_days_left,
    CASE WHEN d.warranty_expires_at IS NULL                  THEN 'not a warranty'
         WHEN d.warranty_expires_at <  CURRENT_DATE          THEN 'expired'
         WHEN d.warranty_expires_at <= CURRENT_DATE + 30     THEN 'expiring in 30 days'
         WHEN d.warranty_expires_at <= CURRENT_DATE + 90     THEN 'expiring in 90 days'
         ELSE 'covered' END                                  AS warranty_bucket,
    d.mime_type,
    d.byte_size,
    round(d.byte_size / 1048576.0, 2)   AS size_mb,
    d.malware_scan_status::text         AS scan_status,
    (d.malware_scan_status = 'clean')   AS is_downloadable,
    d.uploaded_by, u.full_name          AS uploaded_by_name,
    d.created_at, d.created_at::date    AS uploaded_date
FROM asset_documents d
JOIN assets a       ON a.id = d.asset_id
JOIN dim_location l ON l.location_id = a.current_location_id
LEFT JOIN users u   ON u.id = d.uploaded_by;

-- ---------------------------------------------------------------------
-- fact_audit_log
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW fact_audit_log AS
SELECT
    al.id                               AS audit_id,
    al.actor_user_id, u.full_name       AS actor_name, u.email::text AS actor_email,
    al.action,
    split_part(al.action, '.', 1)       AS action_domain,
    split_part(al.action, '.', 2)       AS action_name,
    CASE WHEN al.action LIKE 'auth.login_failed%' THEN true ELSE false END AS is_failed_login,
    al.table_name,
    host(al.ip_address)                 AS ip_address,
    al.user_agent,
    CASE WHEN al.user_agent ILIKE '%Android%' OR al.user_agent ILIKE '%Mobile%'
         THEN 'mobile' ELSE 'desktop' END AS device_type,
    al.created_at,
    al.created_at::date                 AS event_date,
    date_trunc('month', al.created_at)::date AS event_month,
    EXTRACT(HOUR FROM al.created_at)::int    AS event_hour
FROM audit_log al
LEFT JOIN users u ON u.id = al.actor_user_id;

-- =====================================================================
-- READY-MADE KPI VIEWS  (AST-FR-08)
-- Useful as quick cards in Power BI, or as a sanity check in psql.
-- =====================================================================

-- Inventory: count, value and completeness per org unit and category
CREATE OR REPLACE VIEW kpi_inventory AS
SELECT org_unit_name, college, department, building, category_group_name, category_name,
       count(*)                                          AS asset_count,
       count(*) FILTER (WHERE status = 'active')         AS active_count,
       count(*) FILTER (WHERE is_retired)                AS retired_count,
       count(*) FILTER (WHERE status = 'lost')           AS lost_count,
       count(*) FILTER (WHERE NOT has_custodian AND status = 'active') AS without_custodian,
       count(*) FILTER (WHERE serial_number IS NULL)     AS without_serial,
       round(100.0 * count(*) FILTER (WHERE has_custodian AND serial_number IS NOT NULL)
             / NULLIF(count(*), 0), 1)                   AS completeness_pct,
       COALESCE(SUM(purchase_cost), 0)                   AS total_purchase_cost,
       round(AVG(age_years), 2)                          AS avg_age_years
FROM fact_asset
GROUP BY org_unit_name, college, department, building, category_group_name, category_name;

-- Maintenance: due/overdue, MTTR, downtime, preventive vs corrective
CREATE OR REPLACE VIEW kpi_maintenance AS
SELECT org_unit_name, building, category_name,
       count(*)                                                       AS work_order_count,
       count(*) FILTER (WHERE work_order_kind = 'preventive')         AS preventive_count,
       count(*) FILTER (WHERE work_order_kind = 'corrective')         AS corrective_count,
       round(100.0 * count(*) FILTER (WHERE work_order_kind = 'preventive')
             / NULLIF(count(*), 0), 1)                                AS preventive_pct,
       count(*) FILTER (WHERE is_outstanding)                         AS outstanding_count,
       count(*) FILTER (WHERE is_overdue)                             AS overdue_count,
       round(AVG(repair_hours) FILTER (WHERE is_completed), 2)        AS mttr_hours,
       COALESCE(SUM(downtime_minutes), 0)                             AS downtime_minutes,
       round(COALESCE(SUM(downtime_minutes), 0) / 60.0, 1)            AS downtime_hours,
       COALESCE(SUM(total_cost), 0)                                   AS maintenance_cost
FROM fact_work_order
GROUP BY org_unit_name, building, category_name;

-- Warranty coverage board
CREATE OR REPLACE VIEW kpi_warranty AS
SELECT org_unit_name, building, category_name, warranty_bucket,
       count(*)                     AS asset_count,
       SUM(purchase_cost)           AS purchase_cost_at_risk
FROM fact_asset
WHERE NOT is_retired
GROUP BY org_unit_name, building, category_name, warranty_bucket;

-- The human review queue for the risk baseline (AST-FR-09).
-- Nothing here changes an asset: a person has to act on it.
CREATE OR REPLACE VIEW kpi_risk_queue AS
SELECT asset_id, asset_tag, category_name, building, room, org_unit_name,
       custodian_name, condition, age_years, lifecycle_stage,
       corrective_last_12m, downtime_hours_total, maintenance_cost_total,
       maintenance_bucket, warranty_bucket,
       risk_band, risk_rank, risk_score, risk_reasons_text
FROM fact_asset
WHERE NOT is_retired AND risk_band IN ('medium','high','critical');

-- Monthly maintenance trend, ready for a line chart
CREATE OR REPLACE VIEW kpi_maintenance_monthly AS
SELECT completed_month AS month, work_order_kind,
       count(*)                                   AS jobs_completed,
       SUM(total_cost)                            AS total_cost,
       round(SUM(downtime_minutes) / 60.0, 1)     AS downtime_hours,
       round(AVG(repair_hours), 2)                AS avg_repair_hours
FROM fact_work_order
WHERE is_completed AND completed_month IS NOT NULL
GROUP BY completed_month, work_order_kind;

COMMIT;
