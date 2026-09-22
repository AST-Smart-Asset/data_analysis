# AST Smart Asset Management - Fleet & Inventory Analytics Report

**Project:** Project 3: Smart Asset Inventory & Predictive Maintenance (AST)  
**Institution:** Badr University in Assiut (BUA DevHub Field Phase - Squad 3)  
**Reporting Period:** September 2026  
**Scope:** Campus Facilities (Main Engineering Complex & Healthcare Technology Facility)

---

## 1. Executive Summary

This report establishes the baseline analytical posture of Badr University in Assiut's capital equipment inventory, tracking 110+ physical assets across multiple specialized categories (HVAC systems, electrical generators, medical imaging/diagnostic units, specialized engineering laboratories, server clusters, and campus elevators).

### Core Executive KPIs:
- **Total Registered Assets:** 104 units across 2 campus facilities.
- **In-Service Rate:** **90.4%** (94 assets actively operational; 10 under planned servicing; 0 untracked).
- **Active Maintenance Work Orders:** 3 open work orders (1 critical corrective, 2 routine preventive).
- **Physical Reconciliation Audit Discrepancies:** 4 open discrepancies (2 location room deviations, 1 ghost asset flagged for physical search, 1 condition status update).
- **Critical AI Failure Risk Alerts:** 2 units exhibiting anomalous vibration and thermal signatures exceeding ISO-10816 thresholds.

---

## 2. Inventory Distribution & Campus Allocation

### Allocation by Facility:
| Campus Facility | Asset Count | Asset Value (EGP) | High-Risk Units | Open WO Count |
| :--- | :--- | :--- | :--- | :--- |
| **Main Engineering Complex** | 62 | 8,450,000 | 1 | 2 |
| **Healthcare Technology Facility** | 42 | 14,200,000 | 1 | 1 |
| **Total Fleet** | **104** | **22,650,000** | **2** | **3** |

### Category Breakdown:
1. **Medical & Healthcare Units (28% of total value):** High-capital units (MRI chiller, autoclaves, hemodialysis test stations) requiring strict 60-day preventive maintenance cycles.
2. **Heavy HVAC & Environmental Control (32% of total value):** Central chillers and rooftop air handling units. High thermal fatigue due to Upper Egypt summer temperature swings.
3. **Emergency Power Generators (18% of total value):** Standby diesel generators with scheduled monthly run tests and fuel filter replacement cycles.
4. **Engineering Laboratories & IT Infrastructure (22% of total value):** Precision CNC mills, wind tunnel instrumentation, and server racks.

---

## 3. Maintenance Operational Efficiency: MTBF & MTTR

- **Mean Time to Repair (MTTR):** Average corrective repair completion window is **4.2 hours** across all facilities.
- **Mean Time Between Failures (MTBF):** Averaging **2,150 operating hours** per mechanical asset.
- **Planned Maintenance Percentage (PMP):** **76.5%** of all work orders executed in Q3 2026 were preventive rather than reactive corrective repairs.
- **Preventive Maintenance Cost Savings:** Proactive servicing reduced emergency downtime by an estimated **142 machine hours**, saving approximately **185,000 EGP** in secondary component damage.

---

## 4. Physical Stocktake & Audit Reconciliation Findings

During the Q3 2026 barcode/QR physical audit:
- **Scanned Accuracy:** 96.2% of assets matched their registered digital room and floor assignment.
- **Discrepancy Breakdown:**
  - **Location Deviations (2 units):** Mobile diagnostic ultrasound unit `AST-MED-014` was moved from Lab 102 to Radiology Room 204 without digital custody handoff sign-off.
  - **Ghost Asset (1 unit):** Portable calibration multimeter `AST-ENG-088` registered in Tool Crib A was physically missing during the sweep; investigation logged in custody audit trail.
  - **Condition Downgrade (1 unit):** Generator fuel transfer pump `AST-PWR-003` logged as `good` in the database was observed during visual audit to exhibit minor casing vibration and oil weep, triggering automatic work order creation.

---

## 5. Predictive AI Risk Clustering

Cross-referencing sensor telemetry against the **AST Predictive Maintenance AI model (`v1.2.0-rf-ensemble`)**:
1. **Cluster Alpha (Healthcare Facility Rooftop Chiller):**
   - Vibration RMS measured at **5.8 mm/s** (ISO-10816 Zone C - Restricted Operation).
   - Component temperature at **84°C**.
   - Model outputs **0.82 failure probability** with estimated **5-day lead time**.
   - Recommendation: Technicians dispatched for bearing lubrication and belt tensioning before bearing seizure occurs.
2. **Cluster Beta (Emergency Diesel Generator 2):**
   - Days since last PM: **165 days** (cycle overdue by 75 days).
   - High operational risk band assigned due to neglected lubrication intervals.

---

## 6. Financial Depreciation & Capital Replacement Forecast

Using 5-year straight-line depreciation with a 10% terminal salvage value:
- **Original Acquisition Capital:** 22,650,000 EGP
- **Current Depreciated Book Value:** 16,840,000 EGP
- **Projected 2027 Capital Replacement Reserve:** Recommended allocation of **2,400,000 EGP** targeting 4 assets entering their terminal 5th operating year (2 legacy rooftop condenser units and 2 older diesel transfer pumps).
