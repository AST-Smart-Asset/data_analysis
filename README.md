# AST Smart Asset Management - Data Analytics & Reporting

[![SQL Views](https://img.shields.io/badge/SQL-PostgreSQL%20Analytical%20Views-336791?logo=postgresql)](https://github.com/AST-Smart-Asset/data_analysis)
[![Python](https://img.shields.io/badge/Python-3.12-3776AB?logo=python)](https://python.org)
[![Project 3](https://img.shields.io/badge/BUA-DevHub%20Field%20Phase-navy)](https://github.com/AST-Smart-Asset)

Analytical and reporting repository for **Project 3: Smart Asset Inventory & Predictive Maintenance (AST)** at Badr University in Assiut (BUA DevHub Field Phase, Squad 3).

---

## 📊 Overview & Scope

This repository provides operational business intelligence, executive KPI auditing, and reconciliation discrepancy detection between physical barcode/QR scans and the central database:

1. **SQL Analytical Views (`sql/`):**
   - `01_vw_asset_lifecycle_metrics.sql`: Lifecycle aging, straight-line depreciation, warranty expiration, and total work order expenditures.
   - `02_vw_maintenance_cost_downtime.sql`: MTTR (Mean Time to Repair), MTBF (Mean Time Between Failures), and preventive-to-corrective maintenance ratios.
   - `03_vw_reconciliation_discrepancies.sql`: Automated detection and classification of location mismatches, ghost assets, and condition downgrades.
   - `04_vw_predictive_risk_distribution.sql`: Spatial aggregation of AI failure probability by campus facility and equipment type.

2. **Reconciliation & KPI Scripts (`scripts/`):**
   - `kpi_reconciliation.py`: Validates calculation integrity against `AST_Dashboard_API_Filters_Spec.md`, verifying exact KPI numbers and discrepancy taxonomy.

3. **Executive Analytics Reports (`reports/`):**
   - `AST_Data_Analysis_Report.md`: Full fleet operational analysis, asset health distribution, capital replacement horizons, and financial depreciation curves.

---

## 🚀 Running Reconciliation Audits

```bash
# Run the KPI verification and reconciliation script
python scripts/kpi_reconciliation.py
```

The script computes metrics and writes `reports/reconciliation_summary.json` containing the audited KPIs.