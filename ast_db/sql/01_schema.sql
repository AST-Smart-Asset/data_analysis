-- =====================================================================
-- Smart Asset Inventory & Predictive Maintenance  (AST)
-- Badr University in Assiut - DevHub Summer 2026 - Project 3
--
-- File 01 : SCHEMA - the 12 tables from the approved ERD
-- Target   : PostgreSQL 14+   (built and tested on PostgreSQL 16)
--
-- Run order:
--   01_schema.sql -> 02_seed_data.sql -> 03_reporting_views.sql
--   04_rls_security.sql is OPTIONAL - see the README before running it,
--   because Row Level Security will hide rows from Power BI unless you
--   connect with the right role.
-- =====================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

-- ---------------------------------------------------------------------
-- ENUM TYPES
-- ---------------------------------------------------------------------
CREATE TYPE org_unit_type       AS ENUM ('university','campus','college','department','unit');
CREATE TYPE location_type       AS ENUM ('campus','building','college','department','floor','room','office','storage');
CREATE TYPE user_status         AS ENUM ('active','disabled','locked');
CREATE TYPE asset_condition     AS ENUM ('new','good','fair','poor','failed','unknown');
CREATE TYPE asset_status        AS ENUM ('draft','active','in_transfer','in_maintenance','retired','disposed','lost');
CREATE TYPE document_type       AS ENUM ('supplier','purchase_order','invoice','receipt','warranty','manual','retirement_evidence','other');
CREATE TYPE malware_scan_status AS ENUM ('pending','clean','infected','failed');
CREATE TYPE event_type          AS ENUM ('created','imported','transfer_requested','transfer_approved','checked_in','checked_out',
                                         'custody_changed','location_changed','condition_changed','stocktake_observed',
                                         'maintenance_completed','retirement_requested','retired','disposed');
CREATE TYPE trigger_type        AS ENUM ('calendar','runtime','condition');
CREATE TYPE work_order_priority AS ENUM ('low','medium','high','critical');
CREATE TYPE work_order_status   AS ENUM ('open','scheduled','in_progress','completed','cancelled');

-- =====================================================================
-- 1. org_units - the organisational tree and the RBAC scope boundary
-- =====================================================================
CREATE TABLE org_units (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_id  uuid REFERENCES org_units(id) ON DELETE RESTRICT,
    name       text NOT NULL,
    unit_type  org_unit_type NOT NULL,
    is_active  boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT org_units_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT org_units_no_self_parent CHECK (parent_id IS NULL OR parent_id <> id)
);

-- =====================================================================
-- 2. locations - campus > building > floor > room/office/storage
-- =====================================================================
CREATE TABLE locations (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_id     uuid REFERENCES locations(id) ON DELETE RESTRICT,
    org_unit_id   uuid NOT NULL REFERENCES org_units(id) ON DELETE RESTRICT,
    location_type location_type NOT NULL,
    name          text NOT NULL,
    code          text,
    is_active     boolean NOT NULL DEFAULT true,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    created_by    uuid,
    updated_by    uuid,
    CONSTRAINT locations_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT locations_code_not_blank CHECK (code IS NULL OR btrim(code) <> ''),
    CONSTRAINT locations_no_self_parent CHECK (parent_id IS NULL OR parent_id <> id),
    CONSTRAINT locations_unique_code_per_org UNIQUE (org_unit_id, code)
);

-- =====================================================================
-- 3. users - identities. Plain passwords are NEVER stored.
-- =====================================================================
CREATE TABLE users (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email              citext NOT NULL UNIQUE,
    full_name          text NOT NULL,
    password_hash      text NOT NULL,
    status             user_status NOT NULL DEFAULT 'active',
    mfa_enabled        boolean NOT NULL DEFAULT false,
    last_login_at      timestamptz,
    failed_login_count integer NOT NULL DEFAULT 0,
    locked_until       timestamptz,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT users_email_basic_shape CHECK (email::text ~* '^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$'),
    CONSTRAINT users_full_name_not_blank CHECK (btrim(full_name) <> ''),
    CONSTRAINT users_failed_login_non_negative CHECK (failed_login_count >= 0),
    -- The database only accepts something shaped like an Argon2 or bcrypt
    -- hash. The API does the hashing; the DB refuses anything else.
    CONSTRAINT users_password_hash_strong_shape CHECK (
        password_hash ~ '^(\$argon2(id|i|d)\$v=[0-9]+\$m=[0-9]+,t=[0-9]+,p=[0-9]+\$[A-Za-z0-9+/=]+\$[A-Za-z0-9+/=]+|\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53})$'
    )
);

-- =====================================================================
-- 4. roles
-- =====================================================================
CREATE TABLE roles (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code       text NOT NULL UNIQUE,
    name       text NOT NULL,
    is_system  boolean NOT NULL DEFAULT true,
    created_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT roles_code_shape CHECK (code ~ '^[a-z][a-z0-9_]{2,63}$'),
    CONSTRAINT roles_name_not_blank CHECK (btrim(name) <> '')
);

-- =====================================================================
-- 5. user_roles - a grant is always scoped to an org unit
--    (NULL scope = university-wide, only for super_admin / auditor)
-- =====================================================================
CREATE TABLE user_roles (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role_id     uuid NOT NULL REFERENCES roles(id) ON DELETE RESTRICT,
    org_unit_id uuid REFERENCES org_units(id) ON DELETE RESTRICT,
    granted_by  uuid REFERENCES users(id) ON DELETE SET NULL,
    expires_at  timestamptz,
    created_at  timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT user_roles_expiry_future CHECK (expires_at IS NULL OR expires_at > created_at)
);

CREATE UNIQUE INDEX user_roles_unique_open_ended
    ON user_roles (user_id, role_id, COALESCE(org_unit_id, '00000000-0000-0000-0000-000000000000'::uuid))
    WHERE expires_at IS NULL;

-- =====================================================================
-- 6. asset_categories - hierarchy + useful-life policy
-- =====================================================================
CREATE TABLE asset_categories (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    parent_id          uuid REFERENCES asset_categories(id) ON DELETE RESTRICT,
    code               text NOT NULL UNIQUE,
    name               text NOT NULL,
    useful_life_months integer,
    requires_serial    boolean NOT NULL DEFAULT false,
    default_specs      jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT asset_categories_code_shape CHECK (code ~ '^[A-Z0-9_\-]{2,40}$'),
    CONSTRAINT asset_categories_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT asset_categories_life_positive CHECK (useful_life_months IS NULL OR useful_life_months > 0),
    CONSTRAINT asset_categories_no_self_parent CHECK (parent_id IS NULL OR parent_id <> id)
);

-- =====================================================================
-- 7. assets - the register itself
-- =====================================================================
CREATE TABLE assets (
    id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id             uuid NOT NULL REFERENCES asset_categories(id) ON DELETE RESTRICT,
    current_location_id     uuid NOT NULL REFERENCES locations(id) ON DELETE RESTRICT,
    custodian_user_id       uuid REFERENCES users(id) ON DELETE SET NULL,
    asset_tag               text NOT NULL UNIQUE,
    serial_number           text,
    brand                   text,
    model                   text,
    specifications          jsonb NOT NULL DEFAULT '{}'::jsonb,
    condition               asset_condition NOT NULL DEFAULT 'unknown',
    status                  asset_status NOT NULL DEFAULT 'draft',
    purchase_date           date,
    purchase_cost           numeric(14,2),
    next_maintenance_due_at timestamptz,
    -- Advisory AI/rules output only. Never drives a state change.
    risk_band               text NOT NULL DEFAULT 'unknown',
    risk_reasons            jsonb NOT NULL DEFAULT '[]'::jsonb,
    retired_at              timestamptz,
    retirement_reason       text,
    created_at              timestamptz NOT NULL DEFAULT now(),
    updated_at              timestamptz NOT NULL DEFAULT now(),
    created_by              uuid REFERENCES users(id) ON DELETE SET NULL,
    updated_by              uuid REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT assets_tag_shape CHECK (asset_tag ~ '^[A-Z0-9][A-Z0-9_\-]{2,63}$'),
    CONSTRAINT assets_serial_not_blank CHECK (serial_number IS NULL OR btrim(serial_number) <> ''),
    CONSTRAINT assets_cost_non_negative CHECK (purchase_cost IS NULL OR purchase_cost >= 0),
    CONSTRAINT assets_risk_band_allowed CHECK (risk_band IN ('unknown','low','medium','high','critical')),
    CONSTRAINT assets_risk_reasons_is_array CHECK (jsonb_typeof(risk_reasons) = 'array'),
    CONSTRAINT assets_retired_fields CHECK (
        (status NOT IN ('retired','disposed') AND retired_at IS NULL)
     OR (status IN ('retired','disposed') AND retired_at IS NOT NULL
         AND btrim(COALESCE(retirement_reason,'')) <> '')
    )
);

-- Serial numbers are unique only where they exist.
CREATE UNIQUE INDEX assets_serial_number_unique ON assets (serial_number) WHERE serial_number IS NOT NULL;

-- =====================================================================
-- 8. asset_documents - METADATA ONLY
--    The real files live in private object storage. This table holds
--    the bucket/key, the hash and the malware scan result, plus the
--    procurement references (supplier, PO, invoice, warranty).
-- =====================================================================
CREATE TABLE asset_documents (
    id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id              uuid NOT NULL REFERENCES assets(id) ON DELETE RESTRICT,
    document_type         document_type NOT NULL,
    supplier_name         text,
    purchase_order_number text,
    invoice_number        text,
    invoice_amount        numeric(14,2),
    warranty_provider     text,
    warranty_expires_at   date,
    storage_bucket        text NOT NULL,
    storage_key           text NOT NULL,
    mime_type             text NOT NULL,
    byte_size             bigint NOT NULL,
    sha256_hex            text NOT NULL,
    malware_scan_status   malware_scan_status NOT NULL DEFAULT 'pending',
    uploaded_by           uuid REFERENCES users(id) ON DELETE SET NULL,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT asset_documents_storage_not_blank CHECK (btrim(storage_bucket) <> '' AND btrim(storage_key) <> ''),
    CONSTRAINT asset_documents_byte_size_positive CHECK (byte_size > 0),
    CONSTRAINT asset_documents_sha256_shape CHECK (sha256_hex ~ '^[a-f0-9]{64}$'),
    CONSTRAINT asset_documents_amount_non_negative CHECK (invoice_amount IS NULL OR invoice_amount >= 0),
    -- No public links may be stored: downloads must be short-lived and signed.
    CONSTRAINT asset_documents_no_public_urls CHECK (storage_key !~* '^(https?|s3|gs)://')
);

-- =====================================================================
-- 9. asset_events - APPEND-ONLY custody, movement and service history
-- =====================================================================
CREATE TABLE asset_events (
    id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id               uuid NOT NULL REFERENCES assets(id) ON DELETE RESTRICT,
    actor_user_id          uuid REFERENCES users(id) ON DELETE SET NULL,
    event_type             event_type NOT NULL,
    from_location_id       uuid REFERENCES locations(id) ON DELETE SET NULL,
    to_location_id         uuid REFERENCES locations(id) ON DELETE SET NULL,
    from_custodian_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
    to_custodian_user_id   uuid REFERENCES users(id) ON DELETE SET NULL,
    event_data             jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at            timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT asset_events_transfer_has_target CHECK (
        event_type NOT IN ('transfer_requested','transfer_approved','location_changed')
        OR to_location_id IS NOT NULL
    )
);

-- =====================================================================
-- 10. maintenance_templates - calendar / runtime / condition triggers
-- =====================================================================
CREATE TABLE maintenance_templates (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id    uuid NOT NULL REFERENCES asset_categories(id) ON DELETE RESTRICT,
    name           text NOT NULL,
    trigger_type   trigger_type NOT NULL,
    interval_days  integer,
    runtime_hours  integer,
    condition_rule jsonb NOT NULL DEFAULT '{}'::jsonb,
    checklist      jsonb NOT NULL DEFAULT '[]'::jsonb,
    is_active      boolean NOT NULL DEFAULT true,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now(),
    created_by     uuid REFERENCES users(id) ON DELETE SET NULL,
    updated_by     uuid REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT maintenance_templates_name_not_blank CHECK (btrim(name) <> ''),
    CONSTRAINT maintenance_templates_trigger_config CHECK (
        (trigger_type = 'calendar'  AND interval_days IS NOT NULL AND interval_days > 0)
     OR (trigger_type = 'runtime'   AND runtime_hours IS NOT NULL AND runtime_hours > 0)
     OR (trigger_type = 'condition' AND condition_rule <> '{}'::jsonb)
    )
);

-- =====================================================================
-- 11. work_orders
--     A work order with a template_id is PREVENTIVE.
--     A work order without one is CORRECTIVE (a reported fault).
-- =====================================================================
CREATE TABLE work_orders (
    id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id           uuid NOT NULL REFERENCES assets(id) ON DELETE RESTRICT,
    template_id        uuid REFERENCES maintenance_templates(id) ON DELETE SET NULL,
    technician_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
    priority           work_order_priority NOT NULL DEFAULT 'medium',
    status             work_order_status NOT NULL DEFAULT 'open',
    scheduled_at       timestamptz,
    started_at         timestamptz,
    completed_at       timestamptz,
    checklist_result   jsonb NOT NULL DEFAULT '{}'::jsonb,
    parts_cost         numeric(14,2) NOT NULL DEFAULT 0,
    labor_cost         numeric(14,2) NOT NULL DEFAULT 0,
    downtime_minutes   integer NOT NULL DEFAULT 0,
    outcome            text,
    completion_notes   text,
    next_due_at        timestamptz,
    created_at         timestamptz NOT NULL DEFAULT now(),
    updated_at         timestamptz NOT NULL DEFAULT now(),
    created_by         uuid REFERENCES users(id) ON DELETE SET NULL,
    updated_by         uuid REFERENCES users(id) ON DELETE SET NULL,
    CONSTRAINT work_orders_costs_non_negative CHECK (parts_cost >= 0 AND labor_cost >= 0),
    CONSTRAINT work_orders_downtime_non_negative CHECK (downtime_minutes >= 0),
    CONSTRAINT work_orders_completed_fields CHECK (
        status <> 'completed'
        OR (completed_at IS NOT NULL AND btrim(COALESCE(outcome,'')) <> '')
    )
);

-- =====================================================================
-- 12. audit_log - APPEND-ONLY, sanitised security trail
-- =====================================================================
CREATE TABLE audit_log (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    actor_user_id uuid REFERENCES users(id) ON DELETE SET NULL,
    action        text NOT NULL,
    table_name    text,
    record_id     uuid,
    ip_address    inet,
    user_agent    text,
    metadata      jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT audit_log_action_shape CHECK (action ~ '^[a-z][a-z0-9_.\-]{2,120}$'),
    CONSTRAINT audit_log_no_secret_metadata CHECK (
        metadata::text !~* '(password|"token"|secret|authorization|cookie)'
    )
);

-- locations.created_by / updated_by point at users, which is created later
ALTER TABLE locations
    ADD CONSTRAINT locations_created_by_fk FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
    ADD CONSTRAINT locations_updated_by_fk FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL;

-- =====================================================================
-- INDEXES
-- =====================================================================
CREATE INDEX org_units_parent_idx        ON org_units(parent_id);
CREATE INDEX locations_parent_idx        ON locations(parent_id);
CREATE INDEX locations_org_unit_idx      ON locations(org_unit_id);
CREATE INDEX user_roles_user_idx         ON user_roles(user_id);
CREATE INDEX user_roles_role_scope_idx   ON user_roles(role_id, org_unit_id);
CREATE INDEX asset_categories_parent_idx ON asset_categories(parent_id);
CREATE INDEX assets_category_idx         ON assets(category_id);
CREATE INDEX assets_location_idx         ON assets(current_location_id);
CREATE INDEX assets_custodian_idx        ON assets(custodian_user_id);
CREATE INDEX assets_status_idx           ON assets(status);
CREATE INDEX assets_next_due_idx         ON assets(next_maintenance_due_at);
CREATE INDEX asset_documents_asset_idx   ON asset_documents(asset_id);
CREATE INDEX asset_documents_type_idx    ON asset_documents(document_type);
CREATE INDEX asset_documents_warranty_idx ON asset_documents(warranty_expires_at);
CREATE INDEX asset_events_asset_time_idx ON asset_events(asset_id, occurred_at DESC);
CREATE INDEX asset_events_type_time_idx  ON asset_events(event_type, occurred_at DESC);
CREATE INDEX maintenance_templates_category_idx ON maintenance_templates(category_id);
CREATE INDEX work_orders_asset_status_idx ON work_orders(asset_id, status);
CREATE INDEX work_orders_technician_idx   ON work_orders(technician_user_id);
CREATE INDEX work_orders_completed_idx    ON work_orders(completed_at);
CREATE INDEX audit_log_actor_time_idx     ON audit_log(actor_user_id, created_at DESC);
CREATE INDEX audit_log_action_time_idx    ON audit_log(action, created_at DESC);

-- =====================================================================
-- FUNCTIONS AND TRIGGERS
-- =====================================================================

-- The API sets this on every request:  SET LOCAL app.current_user_id = '<uuid>';
CREATE OR REPLACE FUNCTION app_current_user_id()
RETURNS uuid LANGUAGE sql STABLE AS $$
    SELECT NULLIF(current_setting('app.current_user_id', true), '')::uuid
$$;

-- Trusted *connection*. Deliberately based on session_user, which a
-- SECURITY DEFINER function does NOT change. If this used current_user,
-- every definer-owned helper would report "service role" and Row Level
-- Security would silently stop filtering anything.
CREATE OR REPLACE FUNCTION app_is_service_role()
RETURNS boolean LANGUAGE sql STABLE AS $$
    SELECT session_user IN ('postgres','ast_service')
$$;

CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END $$;

CREATE TRIGGER org_units_touch_updated_at            BEFORE UPDATE ON org_units            FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER locations_touch_updated_at            BEFORE UPDATE ON locations            FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER users_touch_updated_at                BEFORE UPDATE ON users                FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER asset_categories_touch_updated_at     BEFORE UPDATE ON asset_categories     FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER assets_touch_updated_at               BEFORE UPDATE ON assets               FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER asset_documents_touch_updated_at      BEFORE UPDATE ON asset_documents      FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER maintenance_templates_touch_updated_at BEFORE UPDATE ON maintenance_templates FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
CREATE TRIGGER work_orders_touch_updated_at          BEFORE UPDATE ON work_orders          FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

-- Passwords -----------------------------------------------------------
CREATE OR REPLACE FUNCTION reject_plain_password_hash()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.password_hash IS NULL
       OR NEW.password_hash !~ '^(\$argon2(id|i|d)\$v=[0-9]+\$m=[0-9]+,t=[0-9]+,p=[0-9]+\$[A-Za-z0-9+/=]+\$[A-Za-z0-9+/=]+|\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53})$'
    THEN
        RAISE EXCEPTION 'users.password_hash must contain an Argon2 or bcrypt hash, never a plain password';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER users_reject_plain_password_hash
BEFORE INSERT OR UPDATE OF password_hash ON users
FOR EACH ROW EXECUTE FUNCTION reject_plain_password_hash();

-- Append-only history -------------------------------------------------
CREATE OR REPLACE FUNCTION block_append_only_changes()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION '% is append-only; updates and deletes are not allowed', TG_TABLE_NAME;
END $$;

CREATE TRIGGER asset_events_append_only BEFORE UPDATE OR DELETE ON asset_events
FOR EACH ROW EXECUTE FUNCTION block_append_only_changes();

CREATE TRIGGER audit_log_append_only BEFORE UPDATE OR DELETE ON audit_log
FOR EACH ROW EXECUTE FUNCTION block_append_only_changes();

-- Retired assets are read-only (AST-FR-10) ----------------------------
CREATE OR REPLACE FUNCTION block_retired_asset_mutation()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF OLD.status IN ('retired','disposed') AND NOT app_is_service_role() THEN
        RAISE EXCEPTION 'asset % is % and is read-only', OLD.asset_tag, OLD.status;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER assets_block_retired_mutation
BEFORE UPDATE ON assets
FOR EACH ROW EXECUTE FUNCTION block_retired_asset_mutation();

-- Category serial policy (AST-FR-02) ----------------------------------
CREATE OR REPLACE FUNCTION assets_check_serial_policy()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE v_requires boolean;
BEGIN
    SELECT requires_serial INTO v_requires FROM asset_categories WHERE id = NEW.category_id;
    IF v_requires AND btrim(COALESCE(NEW.serial_number,'')) = '' THEN
        RAISE EXCEPTION 'category requires a serial number for asset %', NEW.asset_tag;
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER assets_serial_policy
BEFORE INSERT OR UPDATE OF category_id, serial_number ON assets
FOR EACH ROW EXECUTE FUNCTION assets_check_serial_policy();

-- Next due date from a template ---------------------------------------
CREATE OR REPLACE FUNCTION compute_next_due_at(p_template_id uuid, p_from timestamptz)
RETURNS timestamptz LANGUAGE plpgsql STABLE AS $$
DECLARE t maintenance_templates%ROWTYPE;
BEGIN
    SELECT * INTO t FROM maintenance_templates WHERE id = p_template_id;
    IF NOT FOUND OR NOT t.is_active OR t.trigger_type <> 'calendar' THEN
        RETURN NULL;   -- runtime/condition templates are evaluated by the scheduler
    END IF;
    RETURN p_from + make_interval(days => t.interval_days);
END $$;

CREATE OR REPLACE FUNCTION pick_template_for_asset(p_asset_id uuid)
RETURNS uuid LANGUAGE sql STABLE AS $$
    SELECT mt.id
    FROM assets a
    JOIN maintenance_templates mt ON mt.category_id = a.category_id AND mt.is_active
    WHERE a.id = p_asset_id
    ORDER BY mt.created_at
    LIMIT 1
$$;

-- Closing a work order must update the service history AND the next due
-- date on the asset. This is the acceptance test for AST-FR-06 and it is
-- the one thing the first draft of this schema did not do.
CREATE OR REPLACE FUNCTION work_order_apply_completion()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_next timestamptz;
BEGIN
    IF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed' THEN

        v_next := COALESCE(
                    NEW.next_due_at,
                    compute_next_due_at(COALESCE(NEW.template_id, pick_template_for_asset(NEW.asset_id)),
                                        NEW.completed_at));

        IF NEW.next_due_at IS DISTINCT FROM v_next THEN
            UPDATE work_orders SET next_due_at = v_next WHERE id = NEW.id;
        END IF;

        UPDATE assets
           SET next_maintenance_due_at = v_next,
               status = CASE WHEN status = 'in_maintenance' THEN 'active'::asset_status ELSE status END,
               updated_by = COALESCE(NEW.updated_by, NEW.technician_user_id)
         WHERE id = NEW.asset_id;

        INSERT INTO asset_events (asset_id, actor_user_id, event_type, event_data)
        VALUES (NEW.asset_id, COALESCE(NEW.updated_by, NEW.technician_user_id), 'maintenance_completed',
                jsonb_build_object('work_order_id', NEW.id,
                                   'parts_cost', NEW.parts_cost,
                                   'labor_cost', NEW.labor_cost,
                                   'downtime_minutes', NEW.downtime_minutes,
                                   'outcome', NEW.outcome,
                                   'next_due_at', v_next));
    END IF;
    RETURN NULL;
END $$;

CREATE TRIGGER work_orders_log_completion
AFTER UPDATE OF status ON work_orders
FOR EACH ROW EXECUTE FUNCTION work_order_apply_completion();

-- =====================================================================
-- RISK ENGINE (AST-FR-09) - deterministic, explainable baseline.
-- This is the non-AI fallback the brief requires. It only writes the
-- advisory columns; it never changes status, custody or work orders.
-- =====================================================================
CREATE OR REPLACE FUNCTION assess_asset_risk(p_asset_id uuid, p_horizon_days integer DEFAULT 30)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
    a assets%ROWTYPE;
    v_life_months  integer;
    v_life_ratio   numeric := 0;
    v_days_to_due  numeric;
    v_corrective   integer;
    v_downtime     integer;
    v_repair_cost  numeric;
    v_warranty_days numeric;
    v_score        numeric := 0;
    v_band         text;
    v_reasons      jsonb := '[]'::jsonb;
BEGIN
    SELECT * INTO a FROM assets WHERE id = p_asset_id;
    IF NOT FOUND OR a.status IN ('retired','disposed') THEN RETURN NULL; END IF;

    SELECT useful_life_months INTO v_life_months FROM asset_categories WHERE id = a.category_id;

    -- 1) age against expected useful life
    IF a.purchase_date IS NOT NULL AND v_life_months IS NOT NULL THEN
        v_life_ratio := (EXTRACT(EPOCH FROM (now() - a.purchase_date::timestamptz)) / 2629800.0) / v_life_months;
        IF v_life_ratio >= 0.9 THEN
            v_score := v_score + 0.30;
            v_reasons := v_reasons || jsonb_build_object('code','age_near_or_past_useful_life','weight',0.30,
                         'detail', round(v_life_ratio*100) || '% of expected life consumed');
        ELSIF v_life_ratio >= 0.7 THEN
            v_score := v_score + 0.15;
            v_reasons := v_reasons || jsonb_build_object('code','age_high','weight',0.15,
                         'detail', round(v_life_ratio*100) || '% of expected life consumed');
        END IF;
    END IF;

    -- 2) maintenance due proximity
    IF a.next_maintenance_due_at IS NOT NULL THEN
        v_days_to_due := EXTRACT(EPOCH FROM (a.next_maintenance_due_at - now())) / 86400.0;
        IF v_days_to_due < 0 THEN
            v_score := v_score + 0.30;
            v_reasons := v_reasons || jsonb_build_object('code','maintenance_overdue','weight',0.30,
                         'detail', abs(round(v_days_to_due)) || ' days overdue');
        ELSIF v_days_to_due <= p_horizon_days THEN
            v_score := v_score + 0.15;
            v_reasons := v_reasons || jsonb_build_object('code','maintenance_due_within_horizon','weight',0.15,
                         'detail', round(v_days_to_due) || ' days to next service');
        END IF;
    ELSE
        v_score := v_score + 0.05;
        v_reasons := v_reasons || jsonb_build_object('code','no_maintenance_schedule','weight',0.05,
                     'detail','asset has no active maintenance template');
    END IF;

    -- 3) recent corrective work = failure proxy
    SELECT count(*), COALESCE(SUM(downtime_minutes),0), COALESCE(SUM(parts_cost+labor_cost),0)
      INTO v_corrective, v_downtime, v_repair_cost
      FROM work_orders
     WHERE asset_id = p_asset_id AND template_id IS NULL
       AND status = 'completed' AND completed_at > now() - interval '12 months';

    IF v_corrective >= 3 THEN
        v_score := v_score + 0.25;
        v_reasons := v_reasons || jsonb_build_object('code','repeated_failures','weight',0.25,
                     'detail', v_corrective || ' corrective jobs in 12 months');
    ELSIF v_corrective = 2 THEN
        v_score := v_score + 0.12;
        v_reasons := v_reasons || jsonb_build_object('code','repeat_failure','weight',0.12,
                     'detail','2 corrective jobs in 12 months');
    END IF;

    IF v_downtime >= 960 THEN
        v_score := v_score + 0.10;
        v_reasons := v_reasons || jsonb_build_object('code','high_downtime','weight',0.10,
                     'detail', round(v_downtime/60.0) || ' hours of downtime in 12 months');
    END IF;

    IF a.purchase_cost IS NOT NULL AND a.purchase_cost > 0 AND v_repair_cost > a.purchase_cost * 0.4 THEN
        v_score := v_score + 0.10;
        v_reasons := v_reasons || jsonb_build_object('code','repair_cost_ratio_high','weight',0.10,
                     'detail','12-month repair cost exceeds 40% of purchase cost');
    END IF;

    -- 4) reported condition
    IF a.condition = 'failed' THEN
        v_score := v_score + 0.30;
        v_reasons := v_reasons || jsonb_build_object('code','condition_failed','weight',0.30,'detail','condition reported as failed');
    ELSIF a.condition = 'poor' THEN
        v_score := v_score + 0.15;
        v_reasons := v_reasons || jsonb_build_object('code','condition_poor','weight',0.15,'detail','condition reported as poor');
    END IF;

    -- 5) warranty cover
    SELECT MIN(warranty_expires_at - CURRENT_DATE) INTO v_warranty_days
      FROM asset_documents
     WHERE asset_id = p_asset_id AND warranty_expires_at >= CURRENT_DATE;

    IF v_warranty_days IS NULL THEN
        v_score := v_score + 0.05;
        v_reasons := v_reasons || jsonb_build_object('code','no_active_warranty','weight',0.05,
                     'detail','no warranty currently covers this asset');
    ELSIF v_warranty_days <= 60 THEN
        v_score := v_score + 0.05;
        v_reasons := v_reasons || jsonb_build_object('code','warranty_expiring','weight',0.05,
                     'detail', v_warranty_days || ' days of warranty cover left');
    END IF;

    v_score := LEAST(v_score, 1.0);
    v_band  := CASE WHEN v_score >= 0.70 THEN 'critical'
                    WHEN v_score >= 0.45 THEN 'high'
                    WHEN v_score >= 0.20 THEN 'medium'
                    ELSE 'low' END;

    UPDATE assets
       SET risk_band = v_band,
           risk_reasons = v_reasons || jsonb_build_object(
               'code','score','weight', round(v_score,3),
               'detail','baseline_rules v1.0.0, horizon ' || p_horizon_days || ' days')
     WHERE id = p_asset_id;

    RETURN v_band;
END $$;

COMMENT ON FUNCTION assess_asset_risk(uuid,integer) IS
'Deterministic explainable baseline for AST-FR-09. Advisory only: it writes risk_band and risk_reasons and nothing else.';

CREATE OR REPLACE FUNCTION assess_all_assets(p_horizon_days integer DEFAULT 30)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE r record; n integer := 0;
BEGIN
    FOR r IN SELECT id FROM assets WHERE status NOT IN ('retired','disposed') LOOP
        PERFORM assess_asset_risk(r.id, p_horizon_days);
        n := n + 1;
    END LOOP;
    RETURN n;
END $$;

-- =====================================================================
-- DOCUMENTATION
-- =====================================================================
COMMENT ON TABLE users            IS 'User identities. Plain passwords are never stored; password_hash must be Argon2id or bcrypt.';
COMMENT ON COLUMN users.password_hash IS 'One-way hash only, produced by the API layer.';
COMMENT ON TABLE asset_documents  IS 'Metadata only. Files live in private object storage with malware scan and short-lived download authorization.';
COMMENT ON TABLE asset_events     IS 'Append-only movement, custody, maintenance and retirement history.';
COMMENT ON TABLE audit_log        IS 'Append-only sanitised security audit trail. Never stores passwords, tokens or secret payloads.';
COMMENT ON COLUMN assets.risk_band IS 'Advisory output of the rules baseline. Never drives a state change.';
COMMENT ON COLUMN work_orders.template_id IS 'NULL means a corrective (fault) job; NOT NULL means preventive, generated from a template.';

COMMIT;
