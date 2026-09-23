-- =====================================================================
-- File 04 : ROLES AND ROW LEVEL SECURITY   ***OPTIONAL***
--
-- READ THIS BEFORE RUNNING IT.
--
-- This file turns on organisational-scope RBAC at the database level.
-- It is what the AST security requirements ask for, and you will want
-- it in the API. It is NOT needed to explore the data in Power BI, and
-- if you run it and then connect Power BI with the wrong role you will
-- see empty tables and think the seed failed.
--
-- Three login roles are created:
--   ast_app     - the API connects with this. RLS is enforced. Every
--                 request must run:  SET app.current_user_id = '<uuid>';
--   ast_service - background jobs and imports. Bypasses RLS.
--   ast_report  - READ ONLY, sees everything. USE THIS ONE FOR POWER BI.
--
-- Change the passwords below before using this anywhere real, and load
-- them from environment/secret storage - never from a committed file.
-- =====================================================================

BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='ast_app') THEN
        CREATE ROLE ast_app     LOGIN PASSWORD 'change_me_app';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='ast_service') THEN
        CREATE ROLE ast_service LOGIN PASSWORD 'change_me_service';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='ast_report') THEN
        CREATE ROLE ast_report  LOGIN PASSWORD 'change_me_report';
    END IF;
END $$;

GRANT USAGE ON SCHEMA public TO ast_app, ast_service, ast_report;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO ast_app, ast_service;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO ast_report;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO ast_app, ast_service;

-- ---------------------------------------------------------------------
-- RBAC helper functions
--
-- These are SECURITY DEFINER so they can read user_roles even when the
-- caller cannot. They must call app_is_service_role(), which is based
-- on session_user - SECURITY DEFINER changes current_user but not
-- session_user. Using current_user here would make every helper report
-- "service role" and RLS would silently stop filtering anything.
-- ---------------------------------------------------------------------

-- Every org unit the current user can see: their granted units plus all
-- descendants. A NULL grant means university-wide.
CREATE OR REPLACE FUNCTION visible_org_units()
RETURNS TABLE (org_unit_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    WITH RECURSIVE grants AS (
        SELECT ur.org_unit_id
        FROM user_roles ur
        WHERE ur.user_id = app_current_user_id()
          AND (ur.expires_at IS NULL OR ur.expires_at > now())
    ),
    roots AS (
        SELECT ou.id FROM org_units ou
        WHERE EXISTS (SELECT 1 FROM grants g WHERE g.org_unit_id = ou.id)
           OR EXISTS (SELECT 1 FROM grants g WHERE g.org_unit_id IS NULL)
    ),
    tree AS (
        SELECT id FROM roots
        UNION
        SELECT c.id FROM org_units c JOIN tree t ON c.parent_id = t.id
    )
    SELECT id FROM tree
$$;

CREATE OR REPLACE FUNCTION org_unit_is_visible(p_org_unit_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    SELECT app_is_service_role()
        OR (p_org_unit_id IS NOT NULL
            AND EXISTS (SELECT 1 FROM visible_org_units() v WHERE v.org_unit_id = p_org_unit_id))
$$;

CREATE OR REPLACE FUNCTION has_role(p_role_code text, p_org_unit_id uuid DEFAULT NULL)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    WITH RECURSIVE grants AS (
        SELECT ur.org_unit_id
        FROM user_roles ur
        JOIN roles r ON r.id = ur.role_id
        WHERE ur.user_id = app_current_user_id()
          AND r.code = p_role_code
          AND (ur.expires_at IS NULL OR ur.expires_at > now())
    ),
    scope AS (
        SELECT ou.id FROM org_units ou WHERE EXISTS (SELECT 1 FROM grants g WHERE g.org_unit_id = ou.id)
        UNION
        SELECT c.id FROM org_units c JOIN scope s ON c.parent_id = s.id
    )
    SELECT app_is_service_role()
        OR EXISTS (SELECT 1 FROM grants WHERE org_unit_id IS NULL)
        OR (p_org_unit_id IS NOT NULL AND EXISTS (SELECT 1 FROM scope WHERE id = p_org_unit_id))
        OR (p_org_unit_id IS NULL     AND EXISTS (SELECT 1 FROM grants))
$$;

-- The org unit that owns an asset, taken from its current location.
CREATE OR REPLACE FUNCTION asset_org_unit_id(p_asset_id uuid)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
    SELECT l.org_unit_id
    FROM assets a JOIN locations l ON l.id = a.current_location_id
    WHERE a.id = p_asset_id
$$;

-- ---------------------------------------------------------------------
-- Enable AND force RLS.
-- FORCE matters: without it the table owner bypasses every policy, which
-- is the classic way a schema looks secure and is not.
-- ---------------------------------------------------------------------
DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'org_units','locations','users','roles','user_roles','asset_categories',
        'assets','asset_documents','asset_events','maintenance_templates',
        'work_orders','audit_log'
    ] LOOP
        EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
        -- ast_report is a read-only reporting connection and is exempt,
        -- so Power BI and the BI pod always see the whole estate.
        EXECUTE format('CREATE POLICY %I ON %I FOR SELECT TO ast_report USING (true)', t || '_report_read', t);
    END LOOP;
END $$;

-- ---------------------------------------------------------------------
-- Policies
-- ---------------------------------------------------------------------
CREATE POLICY org_units_select ON org_units FOR SELECT USING (org_unit_is_visible(id));
CREATE POLICY org_units_write  ON org_units FOR ALL
    USING (has_role('super_admin')) WITH CHECK (has_role('super_admin'));

CREATE POLICY locations_select ON locations FOR SELECT USING (org_unit_is_visible(org_unit_id));
CREATE POLICY locations_write  ON locations FOR ALL
    USING (has_role('asset_admin', org_unit_id)) WITH CHECK (has_role('asset_admin', org_unit_id));

CREATE POLICY users_select ON users FOR SELECT
    USING (app_is_service_role() OR id = app_current_user_id() OR has_role('super_admin'));
CREATE POLICY users_write ON users FOR ALL
    USING (has_role('super_admin')) WITH CHECK (has_role('super_admin'));

CREATE POLICY roles_select ON roles FOR SELECT
    USING (app_current_user_id() IS NOT NULL OR app_is_service_role());
CREATE POLICY roles_write ON roles FOR ALL
    USING (has_role('super_admin')) WITH CHECK (has_role('super_admin'));

CREATE POLICY user_roles_select ON user_roles FOR SELECT
    USING (app_is_service_role() OR user_id = app_current_user_id()
           OR has_role('super_admin') OR has_role('asset_admin', org_unit_id));
CREATE POLICY user_roles_write ON user_roles FOR ALL
    USING (has_role('super_admin')) WITH CHECK (has_role('super_admin'));

CREATE POLICY asset_categories_select ON asset_categories FOR SELECT
    USING (app_current_user_id() IS NOT NULL OR app_is_service_role());
CREATE POLICY asset_categories_write ON asset_categories FOR ALL
    USING (has_role('asset_admin')) WITH CHECK (has_role('asset_admin'));

-- Assets: visible inside the user's org scope only.
-- A college manager cannot browse another college.
CREATE POLICY assets_select ON assets FOR SELECT
    USING (org_unit_is_visible((SELECT l.org_unit_id FROM locations l WHERE l.id = current_location_id)));
CREATE POLICY assets_insert ON assets FOR INSERT
    WITH CHECK (has_role('asset_admin', (SELECT l.org_unit_id FROM locations l WHERE l.id = current_location_id)));
CREATE POLICY assets_update ON assets FOR UPDATE
    USING (has_role('asset_admin', asset_org_unit_id(id)))
    WITH CHECK (has_role('asset_admin', (SELECT l.org_unit_id FROM locations l WHERE l.id = current_location_id)));

-- Procurement evidence is a SEPARATE permission from the asset registry.
-- Manuals and photos follow asset visibility; invoices and warranties do not.
CREATE POLICY asset_documents_select ON asset_documents FOR SELECT
    USING (
        org_unit_is_visible(asset_org_unit_id(asset_id))
        AND (
            document_type IN ('manual','other')
            OR has_role('procurement_viewer', asset_org_unit_id(asset_id))
            OR has_role('asset_admin',        asset_org_unit_id(asset_id))
            OR has_role('auditor')
        )
    );
CREATE POLICY asset_documents_write ON asset_documents FOR ALL
    USING (has_role('procurement_viewer', asset_org_unit_id(asset_id))
        OR has_role('asset_admin',        asset_org_unit_id(asset_id)))
    WITH CHECK (has_role('procurement_viewer', asset_org_unit_id(asset_id))
        OR has_role('asset_admin',            asset_org_unit_id(asset_id)));

-- History: readable in scope, insertable by anyone acting on the asset.
-- UPDATE and DELETE are blocked by trigger regardless of any policy.
CREATE POLICY asset_events_select ON asset_events FOR SELECT
    USING (
        org_unit_is_visible(asset_org_unit_id(asset_id))
        OR EXISTS (SELECT 1 FROM locations l
                    WHERE l.id IN (from_location_id, to_location_id)
                      AND org_unit_is_visible(l.org_unit_id))
    );
CREATE POLICY asset_events_insert ON asset_events FOR INSERT
    WITH CHECK (
        has_role('asset_admin', asset_org_unit_id(asset_id))
     OR has_role('technician',  asset_org_unit_id(asset_id))
     OR has_role('custodian',   asset_org_unit_id(asset_id))
    );

CREATE POLICY maintenance_templates_select ON maintenance_templates FOR SELECT
    USING (app_current_user_id() IS NOT NULL OR app_is_service_role());
CREATE POLICY maintenance_templates_write ON maintenance_templates FOR ALL
    USING (has_role('asset_admin')) WITH CHECK (has_role('asset_admin'));

CREATE POLICY work_orders_select ON work_orders FOR SELECT
    USING (technician_user_id = app_current_user_id()
           OR org_unit_is_visible(asset_org_unit_id(asset_id)));
CREATE POLICY work_orders_write ON work_orders FOR ALL
    USING (has_role('asset_admin', asset_org_unit_id(asset_id))
        OR has_role('technician',  asset_org_unit_id(asset_id))
        OR technician_user_id = app_current_user_id())
    WITH CHECK (has_role('asset_admin', asset_org_unit_id(asset_id))
        OR has_role('technician',       asset_org_unit_id(asset_id))
        OR technician_user_id = app_current_user_id());

-- The audit log is write-only for everyone and readable only by auditors.
CREATE POLICY audit_log_select ON audit_log FOR SELECT
    USING (has_role('auditor') OR has_role('super_admin'));
CREATE POLICY audit_log_insert ON audit_log FOR INSERT
    WITH CHECK (app_is_service_role() OR actor_user_id = app_current_user_id());

COMMIT;

-- =====================================================================
-- Quick proof that scoping works. Run this after loading the file:
--
--   SET ROLE ast_app;
--   SET app.current_user_id = (SELECT id FROM users WHERE email='cs.manager@bua.test');
--   SELECT count(*) FROM assets;       -- only Computer Science assets
--   SELECT count(*) FROM invoices;     -- 0: procurement is a separate right
--   RESET ROLE;
--
-- To undo everything in this file:
--   ALTER TABLE <each table> DISABLE ROW LEVEL SECURITY;
-- =====================================================================
