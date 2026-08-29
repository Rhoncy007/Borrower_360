/* =====================================================================
   BORROWER360 | Phase 2 | 10_config.sql
   ---------------------------------------------------------------------
   Every economic constant the margin maths depends on lives HERE, with
   an explicit SOURCE_STATUS. Nothing is hardcoded downstream.

   SOURCE_STATUS values:
     SOURCED            - traceable to RBI norms or cited market data
     STATED_ASSUMPTION  - our assumption, NOT verified. Adjust freely.
     DERIVED            - computed from other config rows

   Safe to re-run: yes.
   ===================================================================== */

USE ROLE ACCOUNTADMIN;
USE DATABASE BORROWER360;
USE SCHEMA UTIL;

-- ---------------------------------------------------------------------
-- Economic and regulatory constants
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE CONFIG_ECONOMIC_ASSUMPTION (
    param_key       VARCHAR    NOT NULL,
    param_value     NUMBER(12,4) NOT NULL,
    unit            VARCHAR    NOT NULL,
    source_status   VARCHAR    NOT NULL,
    source_note     VARCHAR
) COMMENT = 'Single source of truth for economic constants. SOURCE_STATUS distinguishes sourced facts from stated assumptions.';

INSERT INTO CONFIG_ECONOMIC_ASSUMPTION (param_key, param_value, unit, source_status, source_note) VALUES
-- Rate environment
 ('repo_rate_pct',                    5.2500, 'pct',     'SOURCED',           'RBI repo rate after 125bps of cuts through 2025'),
-- FUNDING - THE KEY UNVERIFIED NUMBER
 ('cost_of_funds_blended_pct',        9.0000, 'pct',     'STATED_ASSUMPTION', 'Mid-size NBFC blended borrowing cost, midpoint of an 8.5-9.5 range. NOT SOURCED. All margin maths depends on this row - change it here and every NIM recomputes.'),
 ('opex_cost_per_collection_call_inr', 45.0000,'INR',    'STATED_ASSUMPTION', 'Fully loaded cost of one outbound collections call. Not sourced.'),
 ('opex_cost_per_field_visit_inr',    350.0000,'INR',    'STATED_ASSUMPTION', 'Cost of one field visit. Not sourced.'),
 ('opex_cost_per_sms_inr',              0.2500,'INR',    'STATED_ASSUMPTION', 'Not sourced.'),
-- RBI IRAC delinquency ladder (borrower level - see note)
 ('dpd_sma0_min',                      1.0000, 'days',   'SOURCED',           'SMA-0 = 1-30 DPD'),
 ('dpd_sma0_max',                     30.0000, 'days',   'SOURCED',           'SMA-0 upper bound'),
 ('dpd_sma1_min',                     31.0000, 'days',   'SOURCED',           'SMA-1 = 31-60 DPD'),
 ('dpd_sma1_max',                     60.0000, 'days',   'SOURCED',           'SMA-1 upper bound'),
 ('dpd_sma2_min',                     61.0000, 'days',   'SOURCED',           'SMA-2 = 61-90 DPD'),
 ('dpd_sma2_max',                     90.0000, 'days',   'SOURCED',           'SMA-2 upper bound'),
 ('dpd_npa_threshold',                90.0000, 'days',   'SOURCED',           'NPA at 90+ DPD. Classification is at BORROWER level: one facility past 90 makes every facility that borrower holds an NPA.'),
 ('npa_upgrade_requires_full_arrears',  1.0000,'boolean','SOURCED',           'Upgrade requires ENTIRE arrears of interest AND principal across ALL facilities. Not partial, not interest-only, not merely dropping below 90 DPD.'),
-- Balance transfer economics
 ('bt_min_rate_gap_pct',               0.5000, 'pct',    'SOURCED',           'BT only economically rational at >= 0.5pp gap'),
 ('bt_min_residual_months',           60.0000, 'months', 'SOURCED',           'Lower bound of the 5-7 year rule. Below this, interest saved cannot cover switching costs.'),
 ('bt_comfortable_residual_months',   84.0000, 'months', 'SOURCED',           'Upper bound of the 5-7 year rule - BT clearly worthwhile above this.'),
 ('max_within_lender_score_spread_pct',1.5000, 'pct',    'SOURCED',           'Realistic risk-based pricing spread WITHIN one lender is 0.5-1.5pp. A 2-4pp gap only appears bank -> NBFC.'),
-- Fair Practices Code
 ('fpc_call_window_start_hour',        8.0000, 'hour',   'SOURCED',           'RBI FPC: no contact before 08:00. Computable in SQL - do not spend an LLM call on this.'),
 ('fpc_call_window_end_hour',         19.0000, 'hour',   'SOURCED',           'RBI FPC: no contact after 19:00'),
-- Early warning
 ('loan_stacking_lender_threshold',    5.0000, 'lenders','SOURCED',           'RBI flags rising impairment among borrowers with 5+ lenders. Requires bureau tradelines - own-book loan count misses it.'),
 ('bureau_reporting_frequency_days',   7.0000, 'days',   'SOURCED',           'Weekly bureau reporting from July 2026, up from bi-weekly'),
-- Market benchmarks, for calibration checks only
 ('benchmark_system_gnpa_pct',         1.8000, 'pct',    'SOURCED',           'System gross NPA, multi-decadal low'),
 ('benchmark_retail_secured_gnpa_pct', 0.7000, 'pct',    'SOURCED',           'Retail secured GNPA'),
 ('benchmark_retail_unsecured_gnpa_pct',1.7000,'pct',    'SOURCED',           'Retail unsecured GNPA'),
 ('benchmark_retail_par_31_180_pct',   2.9000, 'pct',    'SOURCED',           'Total retail PAR 31-180, midpoint of 2.7-3.1'),
 ('benchmark_small_ticket_pl_delinq_pct',6.4000,'pct',   'SOURCED',           'Small-ticket personal loan delinquency. THIS IS A PRODUCT DELINQUENCY RATE, NOT PORTFOLIO GNPA. Do not conflate.'),
-- Generation control
 ('gen_seed',                      20260821.0000,'seed', 'DERIVED',           'Fixed seed so every generation run is reproducible'),
 ('gen_borrower_count',             5000.0000, 'count',  'DERIVED',           'Target borrower population'),
 ('gen_observation_months',           18.0000, 'months', 'DERIVED',           'Months of repayment history to synthesise');

-- ---------------------------------------------------------------------
-- Per-product calibration.
-- base_roi + score-driven spread (capped at max_within_lender_score_spread)
-- keeps pricing realistic: we do NOT spread 10pp on score within a product.
-- bank_benchmark_roi is what a repo-linked BANK would offer the same
-- borrower - the gap against our NBFC rate is what drives balance transfer.
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE CONFIG_PRODUCT_CALIBRATION (
    product_code            VARCHAR      NOT NULL,
    product_name            VARCHAR      NOT NULL,
    is_secured              BOOLEAN      NOT NULL,
    count_weight_pct        NUMBER(6,3)  NOT NULL,
    ticket_min_inr          NUMBER(12,0) NOT NULL,
    ticket_max_inr          NUMBER(12,0) NOT NULL,
    tenor_min_months        NUMBER(4,0)  NOT NULL,
    tenor_max_months        NUMBER(4,0)  NOT NULL,
    base_roi_pct            NUMBER(6,3)  NOT NULL,
    bank_benchmark_roi_pct  NUMBER(6,3)  NOT NULL,
    target_gnpa_pct         NUMBER(6,3)  NOT NULL,
    nach_mandate_share_pct  NUMBER(6,3)  NOT NULL,
    source_status           VARCHAR      NOT NULL,
    calibration_note        VARCHAR
) COMMENT = 'Per-product generation targets. Blends to portfolio GNPA via V_GNPA_BLEND.';

INSERT INTO CONFIG_PRODUCT_CALIBRATION VALUES
 ('TW',  'Two-wheeler loan',      TRUE,  40.000,  45000,  140000, 12, 36, 14.500, 11.000, 2.500, 85.000, 'STATED_ASSUMPTION',
  'ROI set above the cited auto ceiling of 14pct deliberately: that figure is for CAR loans. Two-wheeler prices higher at NBFCs. Flagged as assumption, not sourced.'),
 ('CD',  'Consumer durable loan', FALSE, 25.000,  15000,   90000,  6, 24, 17.500, 13.000, 3.500, 90.000, 'STATED_ASSUMPTION',
  'Subvented (0pct) CD schemes exist and are excluded here for simplicity. Effective yield modelled as NBFC standard rate.'),
 ('PL',  'Personal loan (small ticket)', FALSE, 20.000, 50000, 500000, 12, 60, 18.500, 12.500, 6.400, 80.000, 'SOURCED',
  'target_gnpa uses the cited 6.4pct small-ticket PL delinquency rate. This is a PRODUCT rate, not portfolio GNPA.'),
 ('MSME','MSME business loan',    FALSE, 15.000, 200000, 2500000, 12, 60, 16.000, 11.500, 2.800, 70.000, 'STATED_ASSUMPTION',
  'GNPA target set below unsecured retail because MSME here is cashflow-assessed with partial collateral. Not sourced.');

-- ---------------------------------------------------------------------
-- THE BLEND ARITHMETIC, IN SQL.
-- GNPA is a VALUE ratio (NPA outstanding / gross advances), so the blend
-- must be value-weighted, not count-weighted. MSME has ~20x the ticket
-- of a consumer durable loan, so it dominates value despite being only
-- 15pct of accounts. Both weightings are shown so the difference is
-- auditable rather than asserted.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_GNPA_BLEND AS
WITH base AS (
    SELECT
        product_code,
        product_name,
        count_weight_pct,
        (ticket_min_inr + ticket_max_inr) / 2                AS avg_ticket_inr,
        target_gnpa_pct,
        count_weight_pct / 100 * ((ticket_min_inr + ticket_max_inr) / 2) AS value_units
    FROM CONFIG_PRODUCT_CALIBRATION
),
tot AS (SELECT SUM(value_units) AS total_value_units FROM base)
SELECT
    b.product_code,
    b.product_name,
    b.count_weight_pct,
    b.avg_ticket_inr,
    ROUND(100.0 * b.value_units / t.total_value_units, 3)              AS value_weight_pct,
    b.target_gnpa_pct,
    ROUND(b.count_weight_pct / 100 * b.target_gnpa_pct, 4)             AS contrib_count_weighted_pct,
    ROUND((b.value_units / t.total_value_units) * b.target_gnpa_pct, 4) AS contrib_value_weighted_pct
FROM base b CROSS JOIN tot t;

-- Headline: the single number a judge will challenge, with its derivation.
CREATE OR REPLACE VIEW V_GNPA_BLEND_SUMMARY AS
SELECT
    ROUND(SUM(contrib_value_weighted_pct), 2) AS blended_gnpa_value_weighted_pct,
    ROUND(SUM(contrib_count_weighted_pct), 2) AS blended_gnpa_count_weighted_pct,
    (SELECT param_value FROM CONFIG_ECONOMIC_ASSUMPTION WHERE param_key='benchmark_system_gnpa_pct') AS system_benchmark_pct,
    'Value-weighted is the regulatory definition and the headline. Above system benchmark because this book is unsecured-heavy NBFC, not because asset quality is deteriorating.' AS interpretation
FROM V_GNPA_BLEND;

SELECT * FROM V_GNPA_BLEND_SUMMARY;
