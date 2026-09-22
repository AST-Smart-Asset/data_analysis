-- =============================================================================
-- View: vw_reconciliation_discrepancies
-- Purpose: Detects and classifies audit discrepancies between the digital
--          asset registry and physical stocktake scans.
-- Types:
--   1. LOCATION_MISMATCH: Asset scanned in different room/building than recorded
--   2. GHOST_ASSET: Asset registered as in_service but missing from physical audit
--   3. STATUS_MISMATCH: Asset recorded in_service but scanned as damaged/critical
-- Compliance: AST-FR-07 (Stocktake & Discrepancies) & AST-FR-08 (Audits)
-- =============================================================================

CREATE OR REPLACE VIEW vw_reconciliation_discrepancies AS
SELECT 
    d.id AS discrepancy_id,
    ss.name AS stocktake_session_name,
    ss.status AS session_status,
    a.asset_tag,
    a.name AS asset_name,
    c.name AS category_name,
    d.discrepancy_type,
    d.expected_location_id,
    exp_loc.building || ' - ' || exp_loc.room_number AS expected_location,
    d.observed_location_id,
    obs_loc.building || ' - ' || obs_loc.room_number AS observed_location,
    d.status AS resolution_status,
    d.created_at,
    d.resolved_at,
    u.name AS resolved_by_user
FROM stocktake_discrepancies d
JOIN stocktake_sessions ss ON d.session_id = ss.id
JOIN assets a ON d.asset_id = a.id
LEFT JOIN categories c ON a.category_id = c.id
LEFT JOIN locations exp_loc ON d.expected_location_id = exp_loc.id
LEFT JOIN locations obs_loc ON d.observed_location_id = obs_loc.id
LEFT JOIN users u ON d.resolved_by_id = u.id;
