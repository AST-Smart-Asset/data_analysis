-- =====================================================================
-- File 02 : DEMO DATA  (100% SYNTHETIC - no real person or record)
--
-- Everything here is deterministic: all "random" values come from an
-- md5 of the row key, so two people running this script get identical
-- data and your Power BI screenshots stay reproducible.
--
-- Volume produced (approximately):
--   10 org units - 69 locations - 24 users - 7 roles - 17 categories
--   12 maintenance templates - 420 assets - ~700 documents
--   ~2,000 work orders spread over 3 years - ~3,500 asset events
--   ~900 audit log rows
-- =====================================================================

BEGIN;

-- Deterministic pseudo-random helper: same key always gives same number.
CREATE OR REPLACE FUNCTION seed_rand(p_key text, p_max integer)
RETURNS integer LANGUAGE sql IMMUTABLE AS $$
    SELECT (('x' || substr(md5(p_key), 1, 7))::bit(28)::integer) % p_max
$$;

-- =====================================================================
-- 1. ORG UNITS
-- =====================================================================
INSERT INTO org_units (name, unit_type, parent_id) VALUES
    ('Badr University in Assiut', 'university', NULL);

INSERT INTO org_units (name, unit_type, parent_id)
SELECT 'Main Campus', 'campus', id FROM org_units WHERE unit_type = 'university';

INSERT INTO org_units (name, unit_type, parent_id)
SELECT v.name, v.t::org_unit_type, (SELECT id FROM org_units WHERE name='Main Campus')
FROM (VALUES
    ('Faculty of Engineering',            'college'),
    ('Faculty of AI and Data Management', 'college'),
    ('Finance and Procurement',           'unit'),
    ('Facilities Management',             'unit')
) v(name, t);

INSERT INTO org_units (name, unit_type, parent_id)
SELECT v.name, v.t::org_unit_type, (SELECT id FROM org_units WHERE name = v.parent)
FROM (VALUES
    ('Computer Science Department',      'department', 'Faculty of Engineering'),
    ('Electrical Engineering Department','department', 'Faculty of Engineering'),
    ('Artificial Intelligence Department','department','Faculty of AI and Data Management'),
    ('Data Science Department',          'department', 'Faculty of AI and Data Management')
) v(name, t, parent);

-- =====================================================================
-- 2. ROLES
-- =====================================================================
INSERT INTO roles (code, name, is_system) VALUES
    ('super_admin',         'Super Administrator',             true),
    ('asset_admin',         'Asset Administrator',             true),
    ('procurement_viewer',  'Procurement and Finance Viewer',  true),
    ('custodian',           'Custodian or Department Manager', true),
    ('technician',          'Maintenance Technician',          true),
    ('auditor',             'Auditor',                         true),
    ('retirement_approver', 'Retirement Approver',             true);

-- =====================================================================
-- 3. USERS   (demo password for every account: DevHub#2026)
--    Hashed here with pgcrypto only because this is a local seed file.
--    In the running system the API hashes with Argon2id before INSERT.
-- =====================================================================
INSERT INTO users (email, full_name, password_hash, status, mfa_enabled, last_login_at, failed_login_count)
SELECT v.email, v.full_name, crypt('DevHub#2026', gen_salt('bf', 10)),
       v.status::user_status, v.mfa,
       now() - make_interval(hours => seed_rand(v.email, 500)),
       seed_rand(v.email || 'f', 3)
FROM (VALUES
    ('super.admin@bua.test',    'Platform Super Admin',    'active',   true),
    ('asset.admin@bua.test',    'Hala Rashad',             'active',   true),
    ('eng.admin@bua.test',      'Tarek Selim',             'active',   false),
    ('ai.admin@bua.test',       'Nour Fahmy',              'active',   false),
    ('procurement@bua.test',    'Mostafa Adel',            'active',   true),
    ('finance.view@bua.test',   'Rania Gamal',             'active',   false),
    ('purchasing@bua.test',     'Sherif Lotfy',            'active',   false),
    ('cs.manager@bua.test',     'Ahmed Shawky',            'active',   false),
    ('ee.manager@bua.test',     'Omar Zaki',               'active',   false),
    ('ai.manager@bua.test',     'Salma Ibrahim',           'active',   false),
    ('ds.manager@bua.test',     'Youssef Kamal',           'active',   false),
    ('fin.manager@bua.test',    'Mona Abdel Aziz',         'active',   false),
    ('fm.manager@bua.test',     'Hany Bakr',               'active',   false),
    ('tech.one@bua.test',       'Mahmoud Saber',           'active',   false),
    ('tech.two@bua.test',       'Kareem Nabil',            'active',   false),
    ('tech.three@bua.test',     'Aya Mansour',             'active',   false),
    ('tech.four@bua.test',      'Islam Fathy',             'active',   false),
    ('tech.five@bua.test',      'Nadia Sobhy',             'active',   false),
    ('tech.six@bua.test',       'Waleed Amer',             'active',   false),
    ('auditor@bua.test',        'Dina Farouk',             'active',   true),
    ('auditor.two@bua.test',    'Sameh Ragab',             'active',   false),
    ('disposal.board@bua.test', 'Hossam El-Deen',          'active',   true),
    ('former.staff@bua.test',   'Former Staff Account',    'disabled', false),
    ('locked.user@bua.test',    'Locked Test Account',     'locked',   false)
) v(email, full_name, status, mfa);

UPDATE users SET locked_until = now() + interval '30 minutes', failed_login_count = 5
 WHERE email = 'locked.user@bua.test';
UPDATE users SET last_login_at = NULL WHERE status <> 'active';

-- Scoped role grants
INSERT INTO user_roles (user_id, role_id, org_unit_id, granted_by)
SELECT u.id, r.id,
       CASE WHEN v.scope IS NULL THEN NULL ELSE (SELECT id FROM org_units WHERE name = v.scope) END,
       (SELECT id FROM users WHERE email='super.admin@bua.test')
FROM (VALUES
    ('super.admin@bua.test',    'super_admin',         NULL),
    ('asset.admin@bua.test',    'asset_admin',         'Main Campus'),
    ('eng.admin@bua.test',      'asset_admin',         'Faculty of Engineering'),
    ('ai.admin@bua.test',       'asset_admin',         'Faculty of AI and Data Management'),
    ('procurement@bua.test',    'procurement_viewer',  'Main Campus'),
    ('finance.view@bua.test',   'procurement_viewer',  'Main Campus'),
    ('purchasing@bua.test',     'procurement_viewer',  'Finance and Procurement'),
    ('cs.manager@bua.test',     'custodian',           'Computer Science Department'),
    ('ee.manager@bua.test',     'custodian',           'Electrical Engineering Department'),
    ('ai.manager@bua.test',     'custodian',           'Artificial Intelligence Department'),
    ('ds.manager@bua.test',     'custodian',           'Data Science Department'),
    ('fin.manager@bua.test',    'custodian',           'Finance and Procurement'),
    ('fm.manager@bua.test',     'custodian',           'Facilities Management'),
    ('tech.one@bua.test',       'technician',          'Main Campus'),
    ('tech.two@bua.test',       'technician',          'Faculty of Engineering'),
    ('tech.three@bua.test',     'technician',          'Faculty of AI and Data Management'),
    ('tech.four@bua.test',      'technician',          'Main Campus'),
    ('tech.five@bua.test',      'technician',          'Facilities Management'),
    ('tech.six@bua.test',       'technician',          'Faculty of Engineering'),
    ('auditor@bua.test',        'auditor',             NULL),
    ('auditor.two@bua.test',    'auditor',             NULL),
    ('disposal.board@bua.test', 'retirement_approver', 'Main Campus'),
    ('eng.admin@bua.test',      'custodian',           'Faculty of Engineering'),
    ('fm.manager@bua.test',     'technician',          'Facilities Management')
) v(email, role_code, scope)
JOIN users u ON u.email = v.email
JOIN roles r ON r.code  = v.role_code;

-- =====================================================================
-- 4. LOCATIONS - campus > 3 buildings > 2 floors each > rooms/offices
-- =====================================================================
INSERT INTO locations (code, name, location_type, org_unit_id, parent_id, created_by)
VALUES ('MAIN', 'Main Campus', 'campus',
        (SELECT id FROM org_units WHERE name='Main Campus'), NULL,
        (SELECT id FROM users WHERE email='asset.admin@bua.test'));

INSERT INTO locations (code, name, location_type, org_unit_id, parent_id, created_by)
SELECT v.code, v.name, 'building',
       (SELECT id FROM org_units WHERE name = v.org),
       (SELECT id FROM locations WHERE code='MAIN'),
       (SELECT id FROM users WHERE email='asset.admin@bua.test')
FROM (VALUES
    ('BLD-A','Engineering Building',         'Faculty of Engineering'),
    ('BLD-B','AI and Data Science Building', 'Faculty of AI and Data Management'),
    ('BLD-C','Administration Building',      'Main Campus')
) v(code, name, org);

INSERT INTO locations (code, name, location_type, org_unit_id, parent_id, created_by)
SELECT b.code || '-F' || f, b.name || ' - Floor ' || f, 'floor',
       b.org_unit_id, b.id, (SELECT id FROM users WHERE email='asset.admin@bua.test')
FROM locations b CROSS JOIN generate_series(1,2) f
WHERE b.location_type = 'building';

INSERT INTO locations (code, name, location_type, org_unit_id, parent_id, created_by)
SELECT fl.code || '-R' || lpad(r::text,2,'0'),
       CASE WHEN r <= 6 THEN 'Lab ' ELSE 'Office ' END || fl.code || '-' || lpad(r::text,2,'0'),
       (CASE WHEN r <= 6 THEN 'room' ELSE 'office' END)::location_type,
       (SELECT id FROM org_units WHERE name =
            CASE WHEN fl.code LIKE 'BLD-A%' AND r % 2 = 1 THEN 'Computer Science Department'
                 WHEN fl.code LIKE 'BLD-A%'               THEN 'Electrical Engineering Department'
                 WHEN fl.code LIKE 'BLD-B%' AND r % 2 = 1 THEN 'Artificial Intelligence Department'
                 WHEN fl.code LIKE 'BLD-B%'               THEN 'Data Science Department'
                 WHEN r % 2 = 1                           THEN 'Finance and Procurement'
                 ELSE 'Facilities Management' END),
       fl.id, (SELECT id FROM users WHERE email='asset.admin@bua.test')
FROM locations fl
CROSS JOIN generate_series(1,10) r
WHERE fl.location_type = 'floor'
  AND NOT (fl.code LIKE 'BLD-C%' AND r > 8);       -- admin building is smaller

INSERT INTO locations (code, name, location_type, org_unit_id, parent_id, created_by)
SELECT b.code || '-STORE', 'Store room - ' || b.name, 'storage',
       b.org_unit_id, b.id, (SELECT id FROM users WHERE email='asset.admin@bua.test')
FROM locations b WHERE b.location_type = 'building';

-- =====================================================================
-- 5. ASSET CATEGORIES
-- =====================================================================
INSERT INTO asset_categories (code, name, useful_life_months, requires_serial) VALUES
    ('IT',   'Information Technology', NULL, false),
    ('FURN', 'Furniture',              NULL, false),
    ('FAC',  'Facility Equipment',     NULL, false),
    ('LAB',  'Laboratory Equipment',   NULL, false);

INSERT INTO asset_categories (code, name, useful_life_months, requires_serial, default_specs, parent_id)
SELECT v.code, v.name, v.life, v.serial, v.specs::jsonb,
       (SELECT id FROM asset_categories WHERE code = v.parent)
FROM (VALUES
    ('IT-PC',      'Desktop Computer',  60,  true,  '{"cpu":null,"ram_gb":null,"storage_gb":null}', 'IT'),
    ('IT-LAPTOP',  'Laptop',            48,  true,  '{"cpu":null,"ram_gb":null,"screen_in":null}',  'IT'),
    ('IT-MONITOR', 'Monitor',           72,  true,  '{"size_in":null,"resolution":null}',           'IT'),
    ('IT-PRINTER', 'Printer',           60,  true,  '{"type":null,"mono":null}',                    'IT'),
    ('IT-SWITCH',  'Network Switch',    84,  true,  '{"ports":null,"speed_gbps":null}',             'IT'),
    ('IT-PROJ',    'Projector',         48,  true,  '{"lumens":null,"lamp_hours":null}',            'IT'),
    ('FURN-DESK',  'Office Desk',      120,  false, '{"material":null,"width_cm":null}',            'FURN'),
    ('FURN-CHAIR', 'Office Chair',      84,  false, '{"material":null}',                            'FURN'),
    ('FURN-CAB',   'Filing Cabinet',   144,  false, '{"drawers":null}',                             'FURN'),
    ('FAC-AC',     'Air Conditioner',   96,  true,  '{"btu":null,"type":null}',                     'FAC'),
    ('FAC-UPS',    'UPS Unit',          60,  true,  '{"va":null,"battery_type":null}',              'FAC'),
    ('LAB-OSC',    'Oscilloscope',     120,  true,  '{"bandwidth_mhz":null,"channels":null}',       'LAB'),
    ('LAB-3DP',    '3D Printer',        72,  true,  '{"build_mm":null,"filament":null}',            'LAB')
) v(code, name, life, serial, specs, parent);

-- =====================================================================
-- 6. MAINTENANCE TEMPLATES
-- =====================================================================
INSERT INTO maintenance_templates (category_id, name, trigger_type, interval_days, runtime_hours,
                                   condition_rule, checklist, created_by)
SELECT (SELECT id FROM asset_categories WHERE code = v.cat),
       v.name, v.trig::trigger_type, v.days, v.hours, v.rule::jsonb, v.list::jsonb,
       (SELECT id FROM users WHERE email='asset.admin@bua.test')
FROM (VALUES
    ('IT-PC',      'Desktop preventive service (180 days)',   'calendar', 180, NULL, '{}',
     '["blow out dust","check fans","update OS and firmware","check disk SMART","verify antivirus"]'),
    ('IT-LAPTOP',  'Laptop preventive service (180 days)',    'calendar', 180, NULL, '{}',
     '["clean vents","battery health check","update OS","check hinges"]'),
    ('IT-MONITOR', 'Monitor inspection (365 days)',           'calendar', 365, NULL, '{}',
     '["check panel for dead pixels","clean screen","check cables"]'),
    ('IT-PRINTER', 'Printer service (120 days)',              'calendar', 120, NULL, '{}',
     '["clean rollers","check toner","calibrate","test print"]'),
    ('IT-SWITCH',  'Switch firmware and port audit (365 d)',  'calendar', 365, NULL, '{}',
     '["firmware check","port error counters","clean rack dust"]'),
    ('IT-PROJ',    'Projector lamp check (1200 runtime h)',   'runtime',  NULL, 1200, '{}',
     '["clean filter","check lamp hours","verify focus"]'),
    ('FAC-AC',     'AC preventive service (90 days)',         'calendar',  90, NULL, '{}',
     '["clean filters","check gas pressure","clean drain","measure delta T"]'),
    ('FAC-UPS',    'UPS battery test (180 days)',             'calendar', 180, NULL, '{}',
     '["battery load test","check terminals","log runtime"]'),
    ('LAB-OSC',    'Oscilloscope calibration (365 days)',     'calendar', 365, NULL, '{}',
     '["self calibration","probe compensation","certificate update"]'),
    ('LAB-3DP',    '3D printer service (500 runtime hours)',  'runtime',  NULL,  500, '{}',
     '["clean nozzle","level bed","check belts","lubricate rails"]'),
    ('FURN-CHAIR', 'Chair check when condition is reported poor','condition',NULL,NULL,
     '{"when":{"condition_in":["poor","failed"]}}',
     '["inspect gas lift","inspect casters","decide repair or replace"]'),
    ('FURN-DESK',  'Desk inspection (730 days)',              'calendar', 730, NULL, '{}',
     '["check stability","tighten fixings","inspect surface"]')
) v(cat, name, trig, days, hours, rule, list);

-- =====================================================================
-- 7. ASSETS - 420 rows across 3 buildings and 13 leaf categories
-- =====================================================================
INSERT INTO assets (
    asset_tag, category_id, current_location_id, custodian_user_id,
    brand, model, serial_number, specifications, condition, status,
    purchase_date, purchase_cost, created_by, created_at
)
WITH cat_mix AS (
    -- weighted category mix: more PCs and monitors than oscilloscopes
    SELECT (row_number() OVER (ORDER BY ord)) - 1 AS idx, code
    FROM (VALUES (1,'IT-PC'),(2,'IT-PC'),(3,'IT-PC'),(4,'IT-PC'),(5,'IT-PC'),(6,'IT-PC'),
                 (7,'IT-MONITOR'),(8,'IT-MONITOR'),(9,'IT-MONITOR'),(10,'IT-MONITOR'),
                 (11,'IT-LAPTOP'),(12,'IT-LAPTOP'),
                 (13,'FURN-DESK'),(14,'FURN-DESK'),(15,'FURN-CHAIR'),(16,'FURN-CHAIR'),(17,'FURN-CAB'),
                 (18,'FAC-AC'),(19,'FAC-UPS'),(20,'IT-PRINTER'),
                 (21,'IT-SWITCH'),(22,'IT-PROJ'),(23,'LAB-OSC'),(24,'LAB-3DP')
         ) v(ord, code)
),
rooms AS (
    SELECT (row_number() OVER (ORDER BY code)) - 1 AS idx, id, org_unit_id
    FROM locations WHERE location_type IN ('room','office')
),
rc AS (SELECT count(*)::int AS c FROM rooms),
pc_models AS (
    SELECT (row_number() OVER (ORDER BY ord)) - 1 AS idx, brand, model
    FROM (VALUES (1,'HP','ProDesk 600 G6'),(2,'Dell','OptiPlex 7090'),(3,'Lenovo','ThinkCentre M70q'),
                 (4,'Acer','Veriton X2680'),(5,'Asus','ExpertCenter D500')
         ) v(ord, brand, model)
)
SELECT
    'AST-' || cm.code || '-' || lpad(i::text, 5, '0'),
    c.id,
    r.id,
    (SELECT u.id FROM users u
       JOIN user_roles ur ON ur.user_id = u.id
       JOIN roles ro ON ro.id = ur.role_id AND ro.code = 'custodian'
      WHERE ur.org_unit_id = r.org_unit_id LIMIT 1),
    CASE WHEN cm.code = 'IT-PC'      THEN pm.brand
         WHEN cm.code = 'IT-LAPTOP'  THEN (ARRAY['HP','Dell','Lenovo'])[1 + seed_rand('b'||i, 3)]
         WHEN cm.code = 'IT-MONITOR' THEN (ARRAY['Samsung','LG','Dell','ViewSonic'])[1 + seed_rand('b'||i, 4)]
         WHEN cm.code = 'IT-PRINTER' THEN (ARRAY['HP','Canon','Brother'])[1 + seed_rand('b'||i, 3)]
         WHEN cm.code = 'IT-SWITCH'  THEN (ARRAY['Cisco','TP-Link','MikroTik'])[1 + seed_rand('b'||i, 3)]
         WHEN cm.code = 'IT-PROJ'    THEN (ARRAY['Epson','BenQ'])[1 + seed_rand('b'||i, 2)]
         WHEN cm.code LIKE 'FURN-%'  THEN 'Upper Office Works'
         WHEN cm.code = 'FAC-AC'     THEN (ARRAY['Carrier','Sharp','Fresh'])[1 + seed_rand('b'||i, 3)]
         WHEN cm.code = 'FAC-UPS'    THEN 'PowerGuard'
         ELSE 'LabLine' END,
    CASE WHEN cm.code = 'IT-PC'      THEN pm.model
         WHEN cm.code = 'IT-LAPTOP'  THEN 'ProBook 4' || (40 + seed_rand('m'||i, 5))
         WHEN cm.code = 'IT-MONITOR' THEN 'V' || (22 + seed_rand('m'||i, 5)) || 'HD'
         WHEN cm.code = 'IT-PRINTER' THEN 'LaserJet M' || (400 + seed_rand('m'||i, 30))
         WHEN cm.code = 'IT-SWITCH'  THEN 'SW-' || (8 * (1 + seed_rand('m'||i, 3))) || 'G'
         WHEN cm.code = 'IT-PROJ'    THEN 'BeamPro ' || (100 + seed_rand('m'||i, 20))
         WHEN cm.code = 'FURN-DESK'  THEN 'Desk-' || (120 + seed_rand('m'||i, 4) * 20) || 'cm'
         WHEN cm.code = 'FURN-CHAIR' THEN 'Ergo-' || (ARRAY['Basic','Plus','Pro'])[1 + seed_rand('m'||i, 3)]
         WHEN cm.code = 'FURN-CAB'   THEN 'Cabinet-' || (2 + seed_rand('m'||i, 3)) || 'D'
         WHEN cm.code = 'FAC-AC'     THEN 'Split ' || (12 + seed_rand('m'||i, 3) * 6) || 'K'
         WHEN cm.code = 'FAC-UPS'    THEN 'PG-' || (1000 + seed_rand('m'||i, 4) * 500) || 'VA'
         WHEN cm.code = 'LAB-OSC'    THEN 'OSC-' || (100 + seed_rand('m'||i, 10))
         ELSE 'FDM-' || (200 + seed_rand('m'||i, 5)) END,
    CASE WHEN c.requires_serial
         THEN replace(cm.code, '-', '') || '-' || lpad((100000 + seed_rand('s'||i, 899999))::text, 6, '0')
    END,
    CASE WHEN cm.code = 'IT-PC'      THEN jsonb_build_object('cpu', (ARRAY['i5-10500','i5-11400','i7-10700'])[1+seed_rand('c'||i,3)], 'ram_gb', (ARRAY[8,16,32])[1+seed_rand('r'||i,3)], 'storage_gb', (ARRAY[256,512,1024])[1+seed_rand('d'||i,3)])
         WHEN cm.code = 'IT-LAPTOP'  THEN jsonb_build_object('cpu','i7-1165G7','ram_gb',(ARRAY[8,16])[1+seed_rand('r'||i,2)],'screen_in',(ARRAY[13,14,15])[1+seed_rand('d'||i,3)])
         WHEN cm.code = 'IT-MONITOR' THEN jsonb_build_object('size_in',(ARRAY[22,24,27])[1+seed_rand('d'||i,3)],'resolution',(ARRAY['1920x1080','2560x1440'])[1+seed_rand('r'||i,2)])
         WHEN cm.code = 'IT-SWITCH'  THEN jsonb_build_object('ports',(ARRAY[8,24,48])[1+seed_rand('d'||i,3)],'speed_gbps',1)
         WHEN cm.code = 'IT-PROJ'    THEN jsonb_build_object('lumens', 3000 + seed_rand('d'||i,5)*500, 'lamp_hours', seed_rand('lh'||i, 2400))
         WHEN cm.code = 'FAC-AC'     THEN jsonb_build_object('btu', 12000 + seed_rand('d'||i,3)*6000, 'type','split')
         WHEN cm.code = 'FAC-UPS'    THEN jsonb_build_object('va', 1000 + seed_rand('d'||i,4)*500, 'battery_type','SLA')
         WHEN cm.code = 'LAB-OSC'    THEN jsonb_build_object('bandwidth_mhz', 100*(1+seed_rand('d'||i,3)), 'channels', (ARRAY[2,4])[1+seed_rand('r'||i,2)])
         WHEN cm.code = 'LAB-3DP'    THEN jsonb_build_object('build_mm','220x220x250','filament',(ARRAY['PLA','ABS','PETG'])[1+seed_rand('r'||i,3)])
         WHEN cm.code = 'FURN-DESK'  THEN jsonb_build_object('material',(ARRAY['MDF','steel_wood'])[1+seed_rand('r'||i,2)],'width_cm',120+seed_rand('d'||i,4)*20)
         ELSE '{}'::jsonb END,
    (CASE WHEN seed_rand('cond'||i, 100) < 3  THEN 'failed'
          WHEN seed_rand('cond'||i, 100) < 12 THEN 'poor'
          WHEN seed_rand('cond'||i, 100) < 32 THEN 'fair'
          WHEN seed_rand('cond'||i, 100) < 42 THEN 'new'
          ELSE 'good' END)::asset_condition,
    (CASE WHEN seed_rand('st'||i, 100) < 2 THEN 'lost'
          WHEN seed_rand('st'||i, 100) < 5 THEN 'draft'
          ELSE 'active' END)::asset_status,
    CURRENT_DATE - (180 + seed_rand('pd'||i, 2400)),
    (CASE cm.code
        WHEN 'IT-PC'      THEN 17000 + seed_rand('p'||i, 9) * 800
        WHEN 'IT-LAPTOP'  THEN 25000 + seed_rand('p'||i, 8) * 1300
        WHEN 'IT-MONITOR' THEN  3900 + seed_rand('p'||i, 6) * 320
        WHEN 'IT-PRINTER' THEN  9200 + seed_rand('p'||i, 5) * 850
        WHEN 'IT-PROJ'    THEN 14500 + seed_rand('p'||i, 4) * 2100
        WHEN 'IT-SWITCH'  THEN 10500 + seed_rand('p'||i, 4) * 1600
        WHEN 'FURN-DESK'  THEN  3600 + seed_rand('p'||i, 5) * 260
        WHEN 'FURN-CHAIR' THEN  1900 + seed_rand('p'||i, 5) * 190
        WHEN 'FURN-CAB'   THEN  2800 + seed_rand('p'||i, 4) * 220
        WHEN 'FAC-AC'     THEN 21000 + seed_rand('p'||i, 4) * 4200
        WHEN 'FAC-UPS'    THEN  7400 + seed_rand('p'||i, 5) * 950
        WHEN 'LAB-OSC'    THEN 62000 + seed_rand('p'||i, 4) * 9500
        ELSE                   29000 + seed_rand('p'||i, 4) * 3200
     END)::numeric(14,2),
    (SELECT id FROM users WHERE email='asset.admin@bua.test'),
    (CURRENT_DATE - (180 + seed_rand('pd'||i, 2400)) + 7)::timestamptz
FROM generate_series(1, 420) i
CROSS JOIN rc
JOIN cat_mix cm ON cm.idx = i % 24
JOIN rooms   r  ON r.idx  = (i * 11) % rc.c
JOIN pc_models pm ON pm.idx = i % 5
JOIN asset_categories c ON c.code = cm.code;

-- =====================================================================
-- 8. ASSET DOCUMENTS - procurement and warranty evidence (metadata only)
-- =====================================================================

-- Invoice record for ~80% of assets
INSERT INTO asset_documents (asset_id, document_type, supplier_name, purchase_order_number,
                             invoice_number, invoice_amount, storage_bucket, storage_key,
                             mime_type, byte_size, sha256_hex, malware_scan_status, uploaded_by, created_at)
SELECT a.id, 'invoice',
       (ARRAY['Nile Tech Systems','Delta Computer Supplies','Upper Egypt Office Works',
              'CoolAir Engineering','LabLine Scientific','PowerGuard Energy'])[1 + seed_rand('sup'||a.asset_tag, 6)],
       'PO-' || to_char(a.purchase_date, 'YYYY') || '-' || lpad((1 + seed_rand('po'||a.asset_tag, 60))::text, 4, '0'),
       'INV-' || to_char(a.purchase_date, 'YYYY') || '-' || lpad((1 + seed_rand('inv'||a.asset_tag, 900))::text, 4, '0'),
       round(a.purchase_cost * 1.14, 2),
       'ast-private-docs',
       'invoices/' || to_char(a.purchase_date, 'YYYY') || '/' || a.asset_tag || '.pdf',
       'application/pdf',
       120000 + seed_rand('sz'||a.asset_tag, 400000),
       encode(digest('invoice-' || a.asset_tag, 'sha256'), 'hex'),
       'clean',
       (SELECT id FROM users WHERE email='procurement@bua.test'),
       (a.purchase_date + 14)::timestamptz
FROM assets a
WHERE seed_rand('hasinv'||a.asset_tag, 100) < 80;

-- Warranty record for ~70% of assets: 24 or 36 months from purchase
INSERT INTO asset_documents (asset_id, document_type, supplier_name, warranty_provider,
                             warranty_expires_at, storage_bucket, storage_key,
                             mime_type, byte_size, sha256_hex, malware_scan_status, uploaded_by, created_at)
SELECT a.id, 'warranty',
       (ARRAY['Nile Tech Systems','Delta Computer Supplies','Upper Egypt Office Works',
              'CoolAir Engineering','LabLine Scientific','PowerGuard Energy'])[1 + seed_rand('sup'||a.asset_tag, 6)],
       (ARRAY['Manufacturer warranty','Supplier extended cover','Service contract'])[1 + seed_rand('wp'||a.asset_tag, 3)],
       a.purchase_date + CASE WHEN seed_rand('wl'||a.asset_tag, 10) < 3 THEN 1095 ELSE 730 END,
       'ast-private-docs',
       'warranties/' || a.asset_tag || '.pdf',
       'application/pdf',
       60000 + seed_rand('wsz'||a.asset_tag, 180000),
       encode(digest('warranty-' || a.asset_tag, 'sha256'), 'hex'),
       'clean',
       (SELECT id FROM users WHERE email='procurement@bua.test'),
       (a.purchase_date + 14)::timestamptz
FROM assets a
WHERE seed_rand('haswr'||a.asset_tag, 100) < 70;

-- A few manuals, and two files that must NOT be downloadable:
-- one still in the scanner queue, one flagged infected and quarantined.
INSERT INTO asset_documents (asset_id, document_type, storage_bucket, storage_key,
                             mime_type, byte_size, sha256_hex, malware_scan_status, uploaded_by)
SELECT a.id, 'manual', 'ast-private-docs', 'manuals/' || a.asset_tag || '.pdf',
       'application/pdf', 1500000 + seed_rand('man'||a.asset_tag, 2000000),
       encode(digest('manual-' || a.asset_tag, 'sha256'), 'hex'),
       'clean', (SELECT id FROM users WHERE email='asset.admin@bua.test')
FROM assets a WHERE seed_rand('hasman'||a.asset_tag, 100) < 18;

INSERT INTO asset_documents (asset_id, document_type, storage_bucket, storage_key,
                             mime_type, byte_size, sha256_hex, malware_scan_status, uploaded_by)
SELECT a.id, 'other', 'ast-private-docs', 'uploads/pending/' || a.asset_tag || '.pdf',
       'application/pdf', 240000,
       encode(digest('pending-' || a.asset_tag, 'sha256'), 'hex'),
       'pending', (SELECT id FROM users WHERE email='asset.admin@bua.test')
FROM assets a ORDER BY a.asset_tag LIMIT 3;

INSERT INTO asset_documents (asset_id, document_type, storage_bucket, storage_key,
                             mime_type, byte_size, sha256_hex, malware_scan_status, uploaded_by)
SELECT a.id, 'other', 'ast-quarantine', 'quarantine/' || a.asset_tag || '.pdf',
       'application/pdf', 512000,
       encode(digest('quarantine-' || a.asset_tag, 'sha256'), 'hex'),
       'infected', (SELECT id FROM users WHERE email='procurement@bua.test')
FROM assets a ORDER BY a.asset_tag DESC LIMIT 2;

-- =====================================================================
-- 9. REGISTRATION EVENTS - one per asset
-- =====================================================================
INSERT INTO asset_events (asset_id, actor_user_id, event_type, to_location_id, to_custodian_user_id,
                          event_data, occurred_at)
SELECT a.id, a.created_by,
       CASE WHEN seed_rand('imp'||a.asset_tag, 10) < 7 THEN 'imported'::event_type ELSE 'created'::event_type END,
       a.current_location_id, a.custodian_user_id,
       jsonb_build_object('asset_tag', a.asset_tag, 'source', 'initial registration'),
       a.created_at
FROM assets a;

-- =====================================================================
-- 10. WORK ORDER HISTORY  (3 years of preventive + corrective jobs)
-- Preventive jobs come from a calendar template. Corrective jobs have
-- no template - that is how the two are told apart in reporting.
-- =====================================================================
DO $$
DECLARE
    a            record;
    t            record;
    v_tech       uuid[];
    v_admin      uuid;
    v_date       timestamptz;
    v_start      timestamptz;
    v_end        timestamptz;
    v_horizon    timestamptz := now();
    v_cutoff     timestamptz;
    v_floor      timestamptz := now() - interval '3 years';
    v_seq        integer;
    v_labor      numeric;
    v_parts      numeric;
    v_down       integer;
    v_outcome    text;
    v_wo         uuid;
    v_n_corr     integer;
    v_k          integer;
BEGIN
    SELECT array_agg(u.id ORDER BY u.email) INTO v_tech
      FROM users u JOIN user_roles ur ON ur.user_id = u.id
      JOIN roles r ON r.id = ur.role_id AND r.code = 'technician';

    SELECT id INTO v_admin FROM users WHERE email = 'asset.admin@bua.test';

    FOR a IN
        SELECT ast.id, ast.asset_tag, ast.category_id, ast.purchase_date, ast.condition, ast.status
          FROM assets ast
         WHERE ast.status IN ('active','in_maintenance','lost')
    LOOP
        -- ---- preventive jobs from the calendar template ----------------
        SELECT mt.id, mt.interval_days INTO t
          FROM maintenance_templates mt
         WHERE mt.category_id = a.category_id AND mt.is_active AND mt.trigger_type = 'calendar'
         LIMIT 1;

        IF FOUND THEN
            -- Offset every asset onto its own cycle. Without this, all
            -- assets sharing an interval land on the same grid and the
            -- whole estate appears to be serviced on the same day.
            v_date := GREATEST(
                        (a.purchase_date + 30)::timestamptz,
                        v_floor + make_interval(days => seed_rand('off'||a.asset_tag, t.interval_days)));

            -- ~18% of assets have let the schedule lapse, so their next
            -- service is already in the past. A maintenance dashboard with
            -- an empty overdue bucket is not a useful test dataset.
            v_cutoff := CASE WHEN seed_rand('lapse'||a.asset_tag, 100) < 18
                             THEN v_horizon - make_interval(days => t.interval_days
                                                   + seed_rand('lapsed'||a.asset_tag, t.interval_days))
                             ELSE v_horizon END;
            v_seq := 0;

            WHILE v_date < v_horizon + make_interval(days => t.interval_days) LOOP
                v_seq := v_seq + 1;

                v_start := v_date + make_interval(days  => seed_rand('pst'||a.asset_tag||v_seq, 9),
                                                  hours => 8 + seed_rand('ph'||a.asset_tag||v_seq, 7));

                IF v_date < v_cutoff AND v_start < v_horizon THEN
                    -- historical: completed, occasionally a few days late
                    v_end   := v_start + make_interval(mins => 30 + seed_rand('pd'||a.asset_tag||v_seq, 150));
                    v_labor := 120 * (1 + seed_rand('pl'||a.asset_tag||v_seq, 4));
                    v_parts := CASE WHEN seed_rand('pp'||a.asset_tag||v_seq, 10) < 3
                                    THEN 150 + seed_rand('ppc'||a.asset_tag||v_seq, 900) ELSE 0 END;

                    INSERT INTO work_orders (asset_id, template_id, technician_user_id, priority, status,
                                             scheduled_at, started_at, completed_at, checklist_result,
                                             parts_cost, labor_cost, downtime_minutes, outcome,
                                             completion_notes, next_due_at, created_by, updated_by, created_at)
                    VALUES (a.id, t.id,
                            v_tech[1 + seed_rand('tech'||a.asset_tag||v_seq, array_length(v_tech,1))],
                            (ARRAY['low','medium','medium','high'])[1 + seed_rand('pri'||a.asset_tag||v_seq, 4)]::work_order_priority,
                            'completed', v_date, v_start, v_end,
                            '{"visual_inspection":"pass","functional_test":"pass"}'::jsonb,
                            v_parts, v_labor,
                            EXTRACT(EPOCH FROM (v_end - v_start))::integer / 60,
                            'preventive service completed',
                            'Scheduled preventive maintenance, no fault found.',
                            v_date + make_interval(days => t.interval_days),
                            v_admin, v_admin, v_date)
                    RETURNING id INTO v_wo;

                    INSERT INTO asset_events (asset_id, actor_user_id, event_type, event_data, occurred_at)
                    VALUES (a.id, v_admin, 'maintenance_completed',
                            jsonb_build_object('work_order_id', v_wo, 'kind', 'preventive',
                                               'parts_cost', v_parts, 'labor_cost', v_labor),
                            v_end);
                ELSE
                    -- the next job in the cycle: still outstanding.
                    -- For a lapsed asset this date is in the past, which
                    -- is exactly what "overdue" means on the dashboard.
                    INSERT INTO work_orders (asset_id, template_id, technician_user_id, priority, status,
                                             scheduled_at, created_by, created_at)
                    VALUES (a.id, t.id,
                            v_tech[1 + seed_rand('tech'||a.asset_tag||v_seq, array_length(v_tech,1))],
                            (ARRAY['low','medium','medium','high'])[1 + seed_rand('pri'||a.asset_tag||v_seq, 4)]::work_order_priority,
                            CASE WHEN v_date < now() + interval '7 days'
                                 THEN 'scheduled'::work_order_status ELSE 'open'::work_order_status END,
                            v_date, v_admin, LEAST(v_date, now()) - interval '7 days');

                    UPDATE assets SET next_maintenance_due_at = v_date WHERE id = a.id;
                    EXIT;
                END IF;

                v_date := v_date + make_interval(days => t.interval_days);
            END LOOP;
        END IF;

        -- ---- corrective jobs (reported faults) -------------------------
        v_n_corr := CASE a.condition
                        WHEN 'failed' THEN 3 + seed_rand('nc'||a.asset_tag, 3)
                        WHEN 'poor'   THEN 2 + seed_rand('nc'||a.asset_tag, 3)
                        WHEN 'fair'   THEN 1 + seed_rand('nc'||a.asset_tag, 2)
                        WHEN 'good'   THEN seed_rand('nc'||a.asset_tag, 2)
                        ELSE 0 END;

        FOR v_k IN 1 .. v_n_corr LOOP
            v_start := v_floor + make_interval(days => seed_rand('cd'||a.asset_tag||v_k, 1090),
                                               hours => 8 + seed_rand('ch'||a.asset_tag||v_k, 8));
            IF v_start < (a.purchase_date + 30)::timestamptz THEN CONTINUE; END IF;

            v_down    := 45 + seed_rand('cdw'||a.asset_tag||v_k, 2800);
            v_end     := v_start + make_interval(mins => v_down);
            v_labor   := 150 * (1 + seed_rand('cl'||a.asset_tag||v_k, 6));
            v_parts   := CASE WHEN seed_rand('cp'||a.asset_tag||v_k, 10) < 7
                              THEN 200 + seed_rand('cpc'||a.asset_tag||v_k, 2600) ELSE 0 END;
            v_outcome := (ARRAY['repaired','part replaced','cleaned and reconfigured',
                                'no fault found','escalated to supplier'])[1 + seed_rand('co'||a.asset_tag||v_k, 5)];

            -- a small share of faults are still open today
            IF seed_rand('copen'||a.asset_tag||v_k, 100) < 6 THEN
                INSERT INTO work_orders (asset_id, technician_user_id, priority, status,
                                         scheduled_at, started_at, created_by, created_at)
                VALUES (a.id, v_tech[1 + seed_rand('ct'||a.asset_tag||v_k, array_length(v_tech,1))],
                        (ARRAY['medium','high','critical'])[1 + seed_rand('cpri'||a.asset_tag||v_k, 3)]::work_order_priority,
                        'in_progress', now() - interval '2 days', now() - interval '1 day',
                        v_admin, now() - interval '2 days');
            ELSE
                INSERT INTO work_orders (asset_id, technician_user_id, priority, status,
                                         scheduled_at, started_at, completed_at, checklist_result,
                                         parts_cost, labor_cost, downtime_minutes, outcome,
                                         completion_notes, created_by, updated_by, created_at)
                VALUES (a.id, v_tech[1 + seed_rand('ct'||a.asset_tag||v_k, array_length(v_tech,1))],
                        (ARRAY['medium','high','high','critical'])[1 + seed_rand('cpri'||a.asset_tag||v_k, 4)]::work_order_priority,
                        'completed', v_start, v_start, v_end,
                        '{"fault_confirmed":true}'::jsonb,
                        v_parts, v_labor, v_down, v_outcome,
                        'Corrective job raised from a fault report.',
                        v_admin, v_admin, v_start)
                RETURNING id INTO v_wo;

                INSERT INTO asset_events (asset_id, actor_user_id, event_type, event_data, occurred_at)
                VALUES (a.id, v_admin, 'maintenance_completed',
                        jsonb_build_object('work_order_id', v_wo, 'kind', 'corrective',
                                           'outcome', v_outcome, 'downtime_minutes', v_down),
                        v_end);
            END IF;
        END LOOP;
    END LOOP;
END $$;

-- A handful of cancelled jobs, for a realistic status mix
UPDATE work_orders
   SET status = 'cancelled', completion_notes = 'Cancelled: asset relocated before the visit.'
 WHERE id IN (SELECT id FROM work_orders WHERE status = 'open' ORDER BY created_at LIMIT 14);

-- =====================================================================
-- 11. TRANSFERS  (AST-FR-04: movement history with actor and timestamp)
-- ~70 assets move at least once, one asset moves three times.
-- =====================================================================
DO $$
DECLARE
    a        record;
    v_target uuid;
    v_org    uuid;
    v_cust   uuid;
    v_from   uuid;
    v_old    uuid;
    v_when   timestamptz;
    v_admin  uuid;
    v_k      integer;
    v_moves  integer;
BEGIN
    SELECT id INTO v_admin FROM users WHERE email='asset.admin@bua.test';

    FOR a IN
        SELECT ast.id, ast.asset_tag, ast.current_location_id, ast.custodian_user_id, ast.created_at
          FROM assets ast
         WHERE ast.status = 'active'
           AND seed_rand('mv'||ast.asset_tag, 100) < 17
    LOOP
        v_moves := 1 + seed_rand('nmv'||a.asset_tag, 2);
        v_from  := a.current_location_id;
        v_old   := a.custodian_user_id;

        FOR v_k IN 1 .. v_moves LOOP
            SELECT l.id, l.org_unit_id INTO v_target, v_org
              FROM locations l
             WHERE l.location_type IN ('room','office') AND l.id <> v_from
             ORDER BY md5(l.code || a.asset_tag || v_k)
             LIMIT 1;

            SELECT u.id INTO v_cust
              FROM users u JOIN user_roles ur ON ur.user_id = u.id
              JOIN roles r ON r.id = ur.role_id AND r.code='custodian'
             WHERE ur.org_unit_id = v_org LIMIT 1;

            v_when := GREATEST(a.created_at, now() - interval '3 years')
                      + make_interval(days => seed_rand('mvd'||a.asset_tag||v_k, 900));
            IF v_when > now() - interval '1 day' THEN v_when := now() - interval '10 days'; END IF;

            INSERT INTO asset_events (asset_id, actor_user_id, event_type, from_location_id, to_location_id,
                                      from_custodian_user_id, to_custodian_user_id, event_data, occurred_at)
            VALUES (a.id, v_old, 'transfer_requested', v_from, v_target, v_old, v_cust,
                    jsonb_build_object('reason', (ARRAY['department reorganisation','lab relocation',
                                                        'staff change','room refurbishment'])[1 + seed_rand('rsn'||a.asset_tag||v_k, 4)]),
                    v_when);

            INSERT INTO asset_events (asset_id, actor_user_id, event_type, from_location_id, to_location_id,
                                      from_custodian_user_id, to_custodian_user_id, event_data, occurred_at)
            VALUES (a.id, v_admin, 'transfer_approved', v_from, v_target, v_old, v_cust,
                    jsonb_build_object('approved_by_role','asset_admin'), v_when + interval '6 hours');

            INSERT INTO asset_events (asset_id, actor_user_id, event_type, from_location_id, to_location_id,
                                      event_data, occurred_at)
            VALUES (a.id, v_admin, 'location_changed', v_from, v_target, '{}'::jsonb, v_when + interval '7 hours');

            IF v_cust IS DISTINCT FROM v_old THEN
                INSERT INTO asset_events (asset_id, actor_user_id, event_type,
                                          from_custodian_user_id, to_custodian_user_id, event_data, occurred_at)
                VALUES (a.id, v_admin, 'custody_changed', v_old, v_cust, '{}'::jsonb, v_when + interval '7 hours');
            END IF;

            v_from := v_target;
            v_old  := v_cust;
        END LOOP;

        UPDATE assets
           SET current_location_id = v_from, custodian_user_id = v_old, updated_by = v_admin
         WHERE id = a.id;
    END LOOP;
END $$;

-- Some condition reports from custodians
INSERT INTO asset_events (asset_id, actor_user_id, event_type, event_data, occurred_at)
SELECT a.id, a.custodian_user_id, 'condition_changed',
       jsonb_build_object('to', a.condition::text, 'source', 'custodian report'),
       now() - make_interval(days => seed_rand('cc'||a.asset_tag, 600))
FROM assets a
WHERE a.condition IN ('poor','failed','fair') AND a.custodian_user_id IS NOT NULL;

-- =====================================================================
-- 12. RETIREMENT  (AST-FR-10)
-- Oldest assets in poor or failed condition are retired with a reason.
-- =====================================================================
DO $$
DECLARE
    a        record;
    v_req    uuid;
    v_appr   uuid;
BEGIN
    SELECT id INTO v_req  FROM users WHERE email='asset.admin@bua.test';
    SELECT id INTO v_appr FROM users WHERE email='disposal.board@bua.test';

    FOR a IN
        SELECT ast.id, ast.asset_tag, ast.current_location_id
          FROM assets ast
         WHERE ast.status = 'active' AND ast.condition IN ('poor','failed')
         ORDER BY ast.purchase_date
         LIMIT 22
    LOOP
        INSERT INTO asset_events (asset_id, actor_user_id, event_type, event_data, occurred_at)
        VALUES (a.id, v_req, 'retirement_requested',
                jsonb_build_object('reason','Beyond economic repair; no remaining warranty cover.'),
                now() - make_interval(days => 20 + seed_rand('rr'||a.asset_tag, 300)));

        UPDATE assets
           SET status = 'retired',
               retired_at = now() - make_interval(days => 10 + seed_rand('rt'||a.asset_tag, 250)),
               retirement_reason = (ARRAY['Beyond economic repair',
                                          'Obsolete, no spare parts available',
                                          'Replaced under the renewal plan',
                                          'Damaged beyond repair'])[1 + seed_rand('rrs'||a.asset_tag, 4)],
               custodian_user_id = NULL,
               next_maintenance_due_at = NULL,
               updated_by = v_appr
         WHERE id = a.id;

        INSERT INTO asset_events (asset_id, actor_user_id, event_type, event_data, occurred_at)
        SELECT a.id, v_appr, 'retired',
               jsonb_build_object('approved_by','retirement_approver',
                                  'reason', ast.retirement_reason),
               ast.retired_at
        FROM assets ast WHERE ast.id = a.id;

        INSERT INTO asset_documents (asset_id, document_type, storage_bucket, storage_key,
                                     mime_type, byte_size, sha256_hex, malware_scan_status, uploaded_by)
        VALUES (a.id, 'retirement_evidence', 'ast-private-docs',
                'retirement/' || a.asset_tag || '.pdf', 'application/pdf', 340000,
                encode(digest('retirement-' || a.asset_tag, 'sha256'), 'hex'), 'clean', v_appr);
    END LOOP;
END $$;

-- =====================================================================
-- 13. RISK BASELINE  (AST-FR-09) - advisory bands with written reasons
-- =====================================================================
SELECT assess_all_assets(30);

-- =====================================================================
-- 14. AUDIT LOG - ~900 sanitised security events over 6 months
-- =====================================================================
INSERT INTO audit_log (actor_user_id, action, table_name, record_id, ip_address, user_agent, metadata, created_at)
SELECT u.id,
       act.action, act.tbl, NULL,
       ('10.20.' || seed_rand('ip'||n||u.email, 20) || '.' || (10 + seed_rand('ip2'||n||u.email, 200)))::inet,
       (ARRAY['Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/126',
              'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) Safari/17',
              'Mozilla/5.0 (X11; Linux x86_64) Firefox/127',
              'AST-Mobile/1.2 (Android 14)'])[1 + seed_rand('ua'||n||u.email, 4)],
       act.meta::jsonb,
       now() - make_interval(days => seed_rand('ad'||n||u.email, 180),
                             hours => seed_rand('ah'||n||u.email, 24),
                             mins  => seed_rand('am'||n||u.email, 60))
FROM generate_series(1, 40) n
CROSS JOIN users u
CROSS JOIN LATERAL (
    SELECT * FROM (VALUES
        ('auth.login_success',       'users',           '{"mfa":true}'),
        ('auth.login_failed',        'users',           '{"reason":"bad_credentials"}'),
        ('asset.created',            'assets',          '{"source":"ui"}'),
        ('asset.updated',            'assets',          '{"fields":["condition"]}'),
        ('asset.transfer_approved',  'asset_events',    '{"approval":"single_step"}'),
        ('document.download_signed', 'asset_documents', '{"ttl_seconds":120}'),
        ('work_order.completed',     'work_orders',     '{"kind":"preventive"}'),
        ('report.export',            'assets',          '{"format":"csv"}'),
        ('rbac.permission_granted',  'user_roles',      '{"scope":"college"}'),
        ('retirement.approved',      'assets',          '{"evidence":"attached"}')
    ) x(action, tbl, meta)
    ORDER BY md5(x.action || n::text || u.email)
    LIMIT 1
) act
WHERE u.status = 'active'
  AND seed_rand('al'||n||u.email, 100) < 85;

COMMIT;

ANALYZE;
