-- =============================================================================
-- View: vw_maintenance_cost_downtime
-- Purpose: Analyzes maintenance operational efficiency, MTTR (Mean Time to Repair),
--          MTBF (Mean Time Between Failures), and cost by category.
-- Compliance: AST-FR-06 (Work Orders) & AST Executive Analytics
-- =============================================================================

CREATE OR REPLACE VIEW vw_maintenance_cost_downtime AS
SELECT 
    c.name AS category_name,
    l.building,
    COUNT(DISTINCT a.id) AS total_assets,
    COUNT(wo.id) AS total_work_orders,
    COUNT(CASE WHEN wo.type = 'corrective' THEN 1 END) AS corrective_repairs_count,
    COUNT(CASE WHEN wo.type = 'preventive' THEN 1 END) AS preventive_orders_count,
    ROUND(
        COUNT(CASE WHEN wo.type = 'preventive' THEN 1 END)::NUMERIC / 
        NULLIF(COUNT(wo.id), 0) * 100.0, 2
    ) AS preventive_maintenance_ratio_pct,
    ROUND(COALESCE(SUM(wo.cost), 0.00), 2) AS total_maintenance_cost_egp,
    ROUND(COALESCE(AVG(wo.cost), 0.00), 2) AS avg_work_order_cost_egp,
    ROUND(COALESCE(SUM(wo.downtime_hours), 0.0), 1) AS total_downtime_hours,
    ROUND(
        COALESCE(AVG(CASE WHEN wo.status = 'completed' THEN wo.downtime_hours END), 0.0), 2
    ) AS mean_time_to_repair_mttr_hours,
    ROUND(
        (COUNT(DISTINCT a.id) * 365.0 * 24.0 - COALESCE(SUM(wo.downtime_hours), 0.0)) / 
        NULLIF(COUNT(CASE WHEN wo.type = 'corrective' THEN 1 END), 0), 1
    ) AS mean_time_between_failures_mtbf_hours
FROM assets a
JOIN categories c ON a.category_id = c.id
JOIN locations l ON a.location_id = l.id
LEFT JOIN work_orders wo ON a.id = wo.asset_id
GROUP BY c.name, l.building;
