-- BORROWER360.UTIL schema: config tables, cost/spend views, standing guardrail assertions,
-- SP_REBUILD_SPINE lives in 02_curated/21_sp_rebuild_spine.sql (owned there for readability).
-- Extracted via GET_DDL('SCHEMA','BORROWER360.UTIL') on 2026-08-29.

create or replace schema UTIL COMMENT='Ops: cost tracking views, generation run log, held-out evaluation ground truth.';

create or replace TABLE CONFIG_BT_THRESHOLD (
	PRODUCT_CODE VARCHAR(16777216) NOT NULL,
	MIN_RESIDUAL_MONTHS NUMBER(4,0) NOT NULL,
	SWITCHING_COST_ASSUMPTION VARCHAR(16777216) NOT NULL,
	SOURCE_STATUS VARCHAR(16777216) NOT NULL
)COMMENT='Product-dependent BT residual-tenor threshold, driven by actual switching cost. The flat 5-7yr rule is a HOME LOAN figure and does not apply to unsecured lending.'
;

create or replace TABLE CONFIG_ECONOMIC_ASSUMPTION (
	PARAM_KEY VARCHAR(16777216) NOT NULL,
	PARAM_VALUE NUMBER(14,4) NOT NULL,
	UNIT VARCHAR(16777216) NOT NULL,
	SOURCE_STATUS VARCHAR(16777216) NOT NULL,
	SOURCE_NOTE VARCHAR(16777216)
)COMMENT='Single source of truth for economic constants. SOURCE_STATUS separates sourced facts from stated assumptions.'
;

create or replace TABLE CONFIG_PRODUCT_CALIBRATION (
	PRODUCT_CODE VARCHAR(16777216) NOT NULL,
	PRODUCT_NAME VARCHAR(16777216) NOT NULL,
	IS_SECURED BOOLEAN NOT NULL,
	COUNT_WEIGHT_PCT NUMBER(6,3) NOT NULL,
	TICKET_MIN_INR NUMBER(12,0) NOT NULL,
	TICKET_MAX_INR NUMBER(12,0) NOT NULL,
	TENOR_MIN_MONTHS NUMBER(4,0) NOT NULL,
	TENOR_MAX_MONTHS NUMBER(4,0) NOT NULL,
	BASE_ROI_PCT NUMBER(6,3) NOT NULL,
	BANK_BENCHMARK_ROI_PCT NUMBER(6,3) NOT NULL,
	TARGET_GNPA_PCT NUMBER(6,3) NOT NULL,
	NACH_MANDATE_SHARE_PCT NUMBER(6,3) NOT NULL,
	SOURCE_STATUS VARCHAR(16777216) NOT NULL,
	CALIBRATION_NOTE VARCHAR(16777216)
)COMMENT='Per-product generation targets. Blends to portfolio GNPA via V_GNPA_BLEND.'
;

create or replace TABLE CONFIG_TRANSCRIPT_MODEL (
	GROUND_TRUTH_LABEL VARCHAR(16777216) NOT NULL,
	MODEL_NAME VARCHAR(16777216) NOT NULL,
	REASON VARCHAR(16777216) NOT NULL,
	DECIDED_AT TIMESTAMP_NTZ(9) NOT NULL
)COMMENT='Model choice per transcript persona, with the reason visible in-schema rather than only in conversation history. Populated from a 50-row pilot that found llama3.1-8b degrading in three distinct ways: degenerate repetition, content-emptied adversarial cases, and - most seriously - an agent unilaterally negotiating rate commitments it has no authority to make (an RBI Fair Practices Code violation in generated content). A single re-pilot with explicit negative constraints was run before finalizing this table.'
;

create or replace TABLE DETERMINISM_TEST_RUN1 (
	BORROWER_ID VARCHAR(16777216),
	LOAN_ID VARCHAR(16777216),
	ACTION_CODE VARCHAR(16777216)
);

create or replace TABLE GROUND_TRUTH_HIDDEN (
	INTERACTION_ID VARCHAR(16777216) NOT NULL,
	GROUND_TRUTH_LABEL VARCHAR(16777216) NOT NULL,
	GENERATION_MODEL VARCHAR(16777216) NOT NULL,
	GENERATED_AT TIMESTAMP_NTZ(9) NOT NULL
)COMMENT='Hidden ground truth for the synthetic call transcript corpus (see CURATED.CALL_TRANSCRIPT). Each interaction was generated FROM a known persona (genuine hardship, technical bounce, wilful default, rate-shopper, etc.) so that AI enrichment accuracy can be MEASURED against a real answer key, not asserted. This table is deliberately isolated from CURATED.CALL_TRANSCRIPT and from the enrichment pipeline: the role that runs enrichment (BORROWER360_ENRICHMENT_ROLE) has no grant on this table or on the UTIL schema at all. The separation is structural, not procedural - enrichment cannot see these labels even if someone tried to join them, which is what makes the resulting accuracy numbers a proof rather than a claim. generation_model is stored here (not in CALL_TRANSCRIPT) because it correlates near-perfectly with ground_truth_label in this corpus and would itself be a label leak if exposed to enrichment.'
;

create or replace view V_AI_SPEND_BY_TAG(
	QUERY_TAG,
	FUNCTION_NAME,
	MODEL_NAME,
	TOKENS,
	AI_CREDITS,
	USD
) as
SELECT COALESCE(NULLIF(query_tag,''),'(untagged)') AS query_tag,
       function_name, model_name,
       SUM(tokens) AS tokens,
       ROUND(SUM(token_credits),6) AS ai_credits,
       ROUND(SUM(token_credits)*2.20,4) AS usd
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
GROUP BY 1,2,3;

create or replace view V_CREDIT_RATES(
	SERVICE_TYPE,
	USD_PER_CREDIT,
	RATE_NOTE
) as
SELECT * FROM VALUES
    ('WAREHOUSE_METERING',        3.60, 'Platform credit - XSMALL warehouse compute'),
    ('CLOUD_SERVICES',            3.60, 'Platform credit - cloud services layer'),
    ('PIPE',                      3.60, 'Platform credit - serverless pipe'),
    ('TELEMETRY_DATA_INGEST',     3.60, 'Platform credit - telemetry'),
    ('AI_FUNCTIONS',              2.20, 'AI credit - Cortex AISQL inference'),
    ('AI_SERVICES',               2.20, 'AI credit - other Cortex AI services'),
    ('SNOWFLAKE_COCO_CLI',        2.00, 'AI credit - Cortex Code CLI (this agent)'),
    ('SNOWFLAKE_COCO_SNOWSIGHT',  2.00, 'AI credit - Cortex Code in Snowsight'),
    ('SNOWFLAKE_COCO_DESKTOP',    2.00, 'AI credit - Cortex Code desktop')
AS t(service_type, usd_per_credit, rate_note);

create or replace view V_DELINQUENCY_DISTRIBUTION(
	BORROWER_ASSET_CLASS,
	BORROWERS,
	PCT_OF_BORROWERS,
	RBI_DEFINITION,
	BENCHMARK_PAR_31_180_PCT,
	BENCHMARK_SYSTEM_GNPA_PCT
) as
SELECT
    borrower_asset_class,
    COUNT(*) AS borrowers,
    ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (),2) AS pct_of_borrowers,
    CASE borrower_asset_class
        WHEN 'STANDARD' THEN 'n/a - performing'
        WHEN 'SMA-0'    THEN '1-30 DPD, early warning, most self-cure'
        WHEN 'SMA-1'    THEN '31-60 DPD'
        WHEN 'SMA-2'    THEN '61-90 DPD, one step from NPA'
        WHEN 'NPA'      THEN '90+ DPD, borrower-level per RBI IRAC'
    END AS rbi_definition,
    (SELECT param_value FROM BORROWER360.UTIL.CONFIG_ECONOMIC_ASSUMPTION WHERE param_key='benchmark_retail_par_31_180_pct') AS benchmark_par_31_180_pct,
    (SELECT param_value FROM BORROWER360.UTIL.CONFIG_ECONOMIC_ASSUMPTION WHERE param_key='benchmark_system_gnpa_pct') AS benchmark_system_gnpa_pct
FROM BORROWER360.CURATED.BORROWER_STATE
GROUP BY borrower_asset_class;

create or replace view V_GNPA_BLEND(
	PRODUCT_CODE,
	PRODUCT_NAME,
	COUNT_WEIGHT_PCT,
	AVG_TICKET_INR,
	VALUE_WEIGHT_PCT,
	TARGET_GNPA_PCT,
	CONTRIB_COUNT_WEIGHTED_PCT,
	CONTRIB_VALUE_WEIGHTED_PCT
) as
WITH base AS (
    SELECT product_code, product_name, count_weight_pct,
           (ticket_min_inr + ticket_max_inr)/2 AS avg_ticket_inr, target_gnpa_pct,
           count_weight_pct/100 * ((ticket_min_inr + ticket_max_inr)/2) AS value_units
    FROM BORROWER360.UTIL.CONFIG_PRODUCT_CALIBRATION),
tot AS (SELECT SUM(value_units) AS tv FROM base)
SELECT b.product_code, b.product_name, b.count_weight_pct, b.avg_ticket_inr,
       ROUND(100.0*b.value_units/t.tv,3) AS value_weight_pct, b.target_gnpa_pct,
       ROUND(b.count_weight_pct/100*b.target_gnpa_pct,4) AS contrib_count_weighted_pct,
       ROUND((b.value_units/t.tv)*b.target_gnpa_pct,4) AS contrib_value_weighted_pct
FROM base b CROSS JOIN tot t;

create or replace view V_GNPA_BLEND_SUMMARY(
	BLENDED_GNPA_VALUE_WEIGHTED_PCT,
	BLENDED_GNPA_COUNT_WEIGHTED_PCT,
	SYSTEM_BENCHMARK_PCT,
	INTERPRETATION
) as
SELECT ROUND(SUM(contrib_value_weighted_pct),2) AS blended_gnpa_value_weighted_pct,
       ROUND(SUM(contrib_count_weighted_pct),2) AS blended_gnpa_count_weighted_pct,
       (SELECT param_value FROM BORROWER360.UTIL.CONFIG_ECONOMIC_ASSUMPTION WHERE param_key='benchmark_system_gnpa_pct') AS system_benchmark_pct,
       'Value-weighted is the regulatory definition and the headline. Above system benchmark because this book is unsecured-heavy NBFC, not because asset quality is deteriorating.' AS interpretation
FROM BORROWER360.UTIL.V_GNPA_BLEND;

create or replace view V_SPEND_BY_CATEGORY(
	SERVICE_TYPE,
	RATE_NOTE,
	CREDITS,
	USD,
	PCT_OF_SPEND
) as
SELECT service_type, rate_note,
       ROUND(SUM(credits),4) AS credits,
       ROUND(SUM(usd),2) AS usd,
       ROUND(100.0*SUM(usd)/SUM(SUM(usd)) OVER (),1) AS pct_of_spend
FROM BORROWER360.UTIL.V_SPEND_DAILY
GROUP BY service_type, rate_note
ORDER BY usd DESC;

create or replace view V_SPEND_DAILY(
	USAGE_DATE,
	SERVICE_TYPE,
	RATE_NOTE,
	CREDITS,
	USD_PER_CREDIT,
	USD
) as
SELECT m.usage_date, m.service_type,
       COALESCE(r.rate_note,'unmapped - rate assumed 2.20') AS rate_note,
       ROUND(m.credits_used,6) AS credits,
       COALESCE(r.usd_per_credit,2.20) AS usd_per_credit,
       ROUND(m.credits_used * COALESCE(r.usd_per_credit,2.20),4) AS usd
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY m
LEFT JOIN BORROWER360.UTIL.V_CREDIT_RATES r ON r.service_type = m.service_type
WHERE m.credits_used > 0;

create or replace view V_SPEND_SUMMARY(
	TRIAL_BUDGET_USD,
	SPENT_USD,
	REMAINING_USD,
	PCT_USED,
	ACTIVE_DAYS,
	USD_PER_ACTIVE_DAY
) as
WITH agg AS (SELECT SUM(usd) AS total_usd, COUNT(DISTINCT usage_date) AS active_days
             FROM BORROWER360.UTIL.V_SPEND_DAILY)
SELECT 400.00 AS trial_budget_usd,
       ROUND(total_usd,2) AS spent_usd,
       ROUND(400.00-total_usd,2) AS remaining_usd,
       ROUND(100.0*total_usd/400.00,1) AS pct_used,
       active_days,
       ROUND(total_usd/NULLIF(active_days,0),2) AS usd_per_active_day
FROM agg;

-- V_STANDING_ASSERTIONS: the single guardrail-verification surface. 9 named checks (A1-A5, B1-B2, C1, D1),
-- each must return violation_count = 0.
create or replace view V_STANDING_ASSERTIONS(
	ASSERTION,
	RULE_INTENT,
	VIOLATION_COUNT
) as
SELECT 'A1_distress_borrower_got_retention_offer' AS assertion, 'Rule 1: credit risk must zero out BT risk' AS rule_intent,
    (SELECT COUNT(*) FROM BORROWER360.AI.NBA_RECOMMENDATION r JOIN BORROWER360.CURATED.BORROWER_STATE bs ON bs.borrower_id=r.borrower_id
     WHERE r.action_code='BT_COUNTER' AND bs.max_dpd_own>=1) AS violation_count
UNION ALL SELECT 'A2_null_rule_basis', 'Rule 1: rules decide, every action traces to a named rule',
    (SELECT COUNT(*) FROM BORROWER360.AI.NBA_RECOMMENDATION WHERE rule_basis IS NULL)
UNION ALL SELECT 'A3_ots_restructure_missing_disclosure', 'FPC: bureau impact must be disclosed for restructure/settlement',
    (SELECT COUNT(*) FROM BORROWER360.AI.NBA_RECOMMENDATION WHERE action_code IN ('OTS_SETTLE','RESTRUCT_TENOR','RESTRUCT_MORAT','EMI_REDUCE') AND bureau_disclosure IS NULL)
UNION ALL SELECT 'A4_missing_decision_log', 'No silent paths: every recommendation is logged',
    (SELECT COUNT(*) FROM BORROWER360.AI.NBA_RECOMMENDATION r LEFT JOIN BORROWER360.AI.NBA_DECISION_LOG l ON l.recommendation_id=r.recommendation_id WHERE l.recommendation_id IS NULL)
UNION ALL SELECT 'A5_action_code_nondeterministic_vs_baseline',
    'Rule 2: rules decide - the deciding half must be deterministic given fixed inputs. Baseline captured after two consecutive regenerations matched exactly (0 mismatches). Refresh DETERMINISM_TEST_RUN1 deliberately after any legitimate rule/data change - a nonzero count here means the SAME inputs produced a DIFFERENT action, not that inputs changed.',
    (SELECT COUNT(*) FROM BORROWER360.UTIL.DETERMINISM_TEST_RUN1 run1
     JOIN BORROWER360.AI.NBA_RECOMMENDATION r USING (borrower_id, loan_id)
     WHERE run1.action_code <> r.action_code)
UNION ALL SELECT 'B1_distressed_nonzero_bt_risk_score', 'Credit risk zeroes BT risk at the score itself, not just the action',
    (SELECT COUNT(*) FROM BORROWER360.CURATED.LOAN_ECONOMICS WHERE borrower_max_dpd_own >= 1 AND bt_risk_score <> 0)
UNION ALL SELECT 'B2_distressed_stance_not_zero_credit_distress', 'Same as B1, stance label consistency',
    (SELECT COUNT(*) FROM BORROWER360.CURATED.LOAN_ECONOMICS WHERE borrower_max_dpd_own >= 1 AND bt_recommended_stance <> 'ZERO_CREDIT_DISTRESS')
UNION ALL SELECT 'C1_impossible_dpd_vs_age', 'A loan cannot be more delinquent than it is old',
    (SELECT COUNT(*) FROM BORROWER360.CURATED.LOAN_ACCOUNT WHERE unpaid_emi_count > months_elapsed)
UNION ALL SELECT 'D1_growth_call_triggered_retention_without_structural_bt_signal',
    'A cross-sell/growth transcript misread as rate-shopping must never trigger a retention offer without the structural loan-economics signal - prevents wasting retention budget on borrowers who were never leaving',
    (SELECT COUNT(*) FROM BORROWER360.AI.NBA_RECOMMENDATION r JOIN BORROWER360.CURATED.LOAN_ECONOMICS le ON le.loan_id = r.loan_id
     WHERE r.action_code = 'BT_COUNTER' AND NOT le.bt_is_economically_rational);
