-- =============================================================================
-- View: vw_asset_lifecycle_metrics
-- Purpose: Aggregates asset lifecycle metrics, operating age, warranty status,
--          and current book value based on straight-line depreciation.
-- Compliance: AST-FR-02 (Dashboard KPIs) & AST-FR-03 (Asset Registry)
-- =============================================================================

CREATE OR REPLACE VIEW vw_asset_lifecycle_metrics AS
SELECT 
    a.id AS asset_id,
    a.asset_tag,
    a.name AS asset_name,
    c.name AS category_name,
    l.building,
    l.floor,
    l.room_number,
    a.status,
    a.condition,
    a.purchase_cost,
    a.purchase_date,
    a.warranty_expiry_date,
    CURRENT_DATE - a.purchase_date AS operating_age_days,
    CASE 
        WHEN a.warranty_expiry_date IS NOT NULL AND a.warranty_expiry_date >= CURRENT_DATE 
        THEN TRUE 
        ELSE FALSE 
    END AS is_under_warranty,
    -- Straight-line depreciation over 5 years (1825 days) with 10% salvage value
    ROUND(
        GREATEST(
            a.purchase_cost * 0.10,
            a.purchase_cost - (
                (a.purchase_cost * 0.90) * 
                LEAST(1.0, (CURRENT_DATE - a.purchase_date)::NUMERIC / 1825.0)
            )
        ), 2
    ) AS estimated_book_value_egp,
    COUNT(DISTINCT wo.id) AS total_work_orders_count,
    COALESCE(SUM(wo.cost), 0.00) AS total_maintenance_spend_egp,
    COALESCE(SUM(wo.downtime_hours), 0.0) AS total_unplanned_downtime_hours
FROM assets a
LEFT JOIN categories c ON a.category_id = c.id
LEFT JOIN locations l ON a.location_id = l.id
LEFT JOIN work_orders wo ON a.id = wo.asset_id
GROUP BY 
    a.id, a.asset_tag, a.name, c.name, l.building, l.floor, l.room_number,
    a.status, a.condition, a.purchase_cost, a.purchase_date, a.warranty_expiry_date;
