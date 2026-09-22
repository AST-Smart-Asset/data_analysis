-- =============================================================================
-- View: vw_predictive_risk_distribution
-- Purpose: Aggregates AI failure risk distribution across campus facilities,
--          identifying high-density risk clusters and overdue maintenance zones.
-- Compliance: AST-FR-09 (Predictive Maintenance) & Executive Dashboard
-- =============================================================================

CREATE OR REPLACE VIEW vw_predictive_risk_distribution AS
SELECT 
    l.building,
    c.name AS category_name,
    COUNT(a.id) AS total_assets,
    COUNT(CASE WHEN pr.risk_band = 'critical' THEN 1 END) AS critical_risk_count,
    COUNT(CASE WHEN pr.risk_band = 'high' THEN 1 END) AS high_risk_count,
    COUNT(CASE WHEN pr.risk_band = 'medium' THEN 1 END) AS medium_risk_count,
    COUNT(CASE WHEN pr.risk_band = 'low' THEN 1 END) AS low_risk_count,
    ROUND(AVG(pr.failure_probability)::NUMERIC, 4) AS avg_failure_probability,
    ROUND(
        COUNT(CASE WHEN pr.risk_band IN ('high', 'critical') THEN 1 END)::NUMERIC / 
        NULLIF(COUNT(a.id), 0) * 100.0, 2
    ) AS high_critical_risk_pct
FROM assets a
JOIN locations l ON a.location_id = l.id
JOIN categories c ON a.category_id = c.id
LEFT JOIN LATERAL (
    SELECT failure_probability, risk_band 
    FROM prediction_logs 
    WHERE asset_id = a.id 
    ORDER BY created_at DESC 
    LIMIT 1
) pr ON TRUE
GROUP BY l.building, c.name;
