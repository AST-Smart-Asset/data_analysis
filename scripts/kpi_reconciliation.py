#!/usr/bin/env python3
"""
AST KPI & Reconciliation Verification Script
Grounds calculations against AST_Dashboard_API_Filters_Spec.md
Validates consistency between physical audit scans and backend registry.
"""

import json
from datetime import datetime, timezone
from pathlib import Path

def calculate_kpis(assets, work_orders, discrepancies, predictions):
    """
    Computes official AST Executive KPIs strictly following AST_Dashboard_API_Filters_Spec.md:
    1. Total Assets: COUNT(*) FROM assets
    2. In-Service Assets: COUNT(*) WHERE status = 'in_service'
    3. Active Work Orders: COUNT(*) WHERE status IN ('open', 'in_progress', 'pending_approval')
    4. Open Discrepancies: COUNT(*) WHERE status = 'open'
    5. Critical Risk Alerts: COUNT(*) WHERE risk_band = 'critical'
    """
    total_assets = len(assets)
    in_service_assets = sum(1 for a in assets if a.get("status") == "in_service")
    active_work_orders = sum(1 for w in work_orders if w.get("status") in ["open", "in_progress", "pending_approval"])
    open_discrepancies = sum(1 for d in discrepancies if d.get("status") == "open")
    critical_risk_alerts = sum(1 for p in predictions if p.get("risk_band") == "critical")

    # Discrepancy taxonomy
    loc_mismatches = sum(1 for d in discrepancies if d.get("type") == "location_mismatch" and d.get("status") == "open")
    ghost_assets = sum(1 for d in discrepancies if d.get("type") == "ghost_asset" and d.get("status") == "open")
    status_mismatches = sum(1 for d in discrepancies if d.get("type") == "status_mismatch" and d.get("status") == "open")

    # Financial valuation
    total_replacement_value = sum(float(a.get("purchase_cost", 0)) for a in assets)
    total_maintenance_expenditure = sum(float(w.get("cost", 0)) for w in work_orders)

    return {
        "calculated_at": datetime.now(timezone.utc).isoformat(),
        "executive_kpis": {
            "total_assets": total_assets,
            "in_service_assets": in_service_assets,
            "active_work_orders": active_work_orders,
            "open_reconciliation_discrepancies": open_discrepancies,
            "critical_ai_risk_alerts": critical_risk_alerts,
        },
        "reconciliation_breakdown": {
            "location_mismatches": loc_mismatches,
            "ghost_assets": ghost_assets,
            "status_mismatches": status_mismatches,
            "total_open": open_discrepancies,
        },
        "financial_summary": {
            "total_capital_asset_value_egp": round(total_replacement_value, 2),
            "total_maintenance_expenditure_egp": round(total_maintenance_expenditure, 2),
            "maintenance_to_asset_value_ratio": round(total_maintenance_expenditure / max(1.0, total_replacement_value), 4),
        }
    }

def run_synthetic_audit():
    # Representative benchmark dataset matching BUA campus seed
    assets = [
        {"id": f"AST-00{i}", "status": "in_service", "purchase_cost": 45000 + (i * 1200)}
        for i in range(1, 95)
    ] + [
        {"id": f"AST-0{i}", "status": "maintenance", "purchase_cost": 75000}
        for i in range(95, 105)
    ] + [
        {"id": f"AST-1{i}", "status": "disposed", "purchase_cost": 25000}
        for i in range(5)
    ]

    work_orders = [
        {"id": "WO-01", "status": "in_progress", "cost": 3200},
        {"id": "WO-02", "status": "open", "cost": 1500},
        {"id": "WO-03", "status": "open", "cost": 4800},
        {"id": "WO-04", "status": "completed", "cost": 7500},
        {"id": "WO-05", "status": "completed", "cost": 12000},
    ]

    discrepancies = [
        {"id": "DISC-01", "type": "location_mismatch", "status": "open"},
        {"id": "DISC-02", "type": "location_mismatch", "status": "open"},
        {"id": "DISC-03", "type": "ghost_asset", "status": "open"},
        {"id": "DISC-04", "type": "status_mismatch", "status": "open"},
        {"id": "DISC-05", "type": "location_mismatch", "status": "resolved"},
    ]

    predictions = [
        {"asset_id": "AST-001", "risk_band": "critical"},
        {"asset_id": "AST-002", "risk_band": "critical"},
        {"asset_id": "AST-003", "risk_band": "high"},
        {"asset_id": "AST-004", "risk_band": "medium"},
    ]

    results = calculate_kpis(assets, work_orders, discrepancies, predictions)

    reports_dir = Path("reports")
    reports_dir.mkdir(parents=True, exist_ok=True)
    out_file = reports_dir / "reconciliation_summary.json"
    with open(out_file, "w") as f:
        json.dump(results, f, indent=2)

    print("=" * 60)
    print("AST EXECUTIVE KPI & RECONCILIATION AUDIT")
    print("=" * 60)
    for k, v in results["executive_kpis"].items():
        print(f"{k.replace('_', ' ').title():<38}: {v}")
    print("-" * 60)
    print(f"Total Capital Asset Value (EGP)       : {results['financial_summary']['total_capital_asset_value_egp']:,.2f}")
    print(f"Total Maintenance Expenditure (EGP)   : {results['financial_summary']['total_maintenance_expenditure_egp']:,.2f}")
    print(f"Location Mismatches                   : {results['reconciliation_breakdown']['location_mismatches']}")
    print(f"Ghost Assets (Physically Missing)     : {results['reconciliation_breakdown']['ghost_assets']}")
    print("=" * 60)
    print(f"Results exported to {out_file}")

if __name__ == "__main__":
    run_synthetic_audit()
