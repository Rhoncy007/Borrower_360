-- BORROWER360.CURATED schema: conformed entities (borrower, loan, schedule, payments, DPD, LOAN_ECONOMICS)
-- Extracted via GET_DDL('SCHEMA','BORROWER360.CURATED') on 2026-08-29.

create or replace schema CURATED COMMENT='Conformed entities: borrower, loan, schedule, payments, monthly DPD snapshots, interactions.';

create or replace TABLE BORROWER (
	BORROWER_ID VARCHAR(16777216),
	FULL_NAME VARCHAR(16777216),
	GENDER VARCHAR(1),
	DATE_OF_BIRTH DATE,
	AGE NUMBER(20,0),
	OCCUPATION_TYPE VARCHAR(14),
	MONTHLY_INCOME_INR NUMBER(28,0),
	CITY VARCHAR(16777216),
	STATE VARCHAR(16777216),
	REGION VARCHAR(16777216),
	CITY_TIER NUMBER(1,0),
	PINCODE VARCHAR(16777216),
	PRIMARY_LANGUAGE VARCHAR(16777216),
	PAN_MASKED VARCHAR(16777216),
	AADHAAR_LINKED BOOLEAN,
	KYC_STATUS VARCHAR(22),
	BUREAU_SCORE NUMBER(20,0),
	BUREAU_SCORE_BAND VARCHAR(9),
	ONBOARD_DATE DATE,
	IS_DEMO_CASE BOOLEAN,
	DEMO_CASE_LABEL VARCHAR(16777216)
);

create or replace TABLE BORROWER_360 (
	BORROWER_ID VARCHAR(16777216),
	FULL_NAME VARCHAR(16777216),
	CITY VARCHAR(16777216),
	STATE VARCHAR(16777216),
	CITY_TIER NUMBER(1,0),
	OCCUPATION_TYPE VARCHAR(14),
	MONTHLY_INCOME_INR NUMBER(28,0),
	BUREAU_SCORE NUMBER(20,0),
	BUREAU_SCORE_BAND VARCHAR(9),
	OWN_LOAN_COUNT NUMBER(18,0),
	OWN_PRODUCT_COUNT NUMBER(18,0),
	TOTAL_OUTSTANDING_INR FLOAT,
	TOTAL_ARREARS_INR FLOAT,
	BORROWER_ASSET_CLASS VARCHAR(8),
	IS_NPA BOOLEAN,
	NPA_UPGRADE_ELIGIBLE BOOLEAN,
	ARREARS_TO_CLEAR_FOR_UPGRADE_INR FLOAT,
	PERFORMING_LOANS_DRAGGED_TO_NPA NUMBER(18,0),
	IS_LOAN_STACKED BOOLEAN,
	TOTAL_LENDER_COUNT NUMBER(19,0),
	FOIR_TRUE_PCT FLOAT,
	EARLY_WARNING_MANDATES NUMBER(13,0),
	BT_RISK_SCORE NUMBER(38,1),
	BT_IS_A_FLIGHT_RISK BOOLEAN,
	BT_RETENTION_VALUE_IF_OFFERED_INR FLOAT,
	LTV_EXPECTED_INTEREST_INR FLOAT,
	N_INTERACTIONS NUMBER(18,0),
	OVERALL_SENTIMENT_DIRECTION VARCHAR(13),
	ANY_PTP_MADE_THEN_MISSED BOOLEAN,
	ANY_REASON_CHANGE BOOLEAN,
	DAYS_GAP_TREND VARCHAR(29),
	N_PENDING_RECOMMENDATIONS NUMBER(18,0),
	HAS_COLLECTIONS_ACTION BOOLEAN,
	HAS_RETENTION_OFFER BOOLEAN,
	HAS_GROWTH_OFFER BOOLEAN,
	IS_DEMO_CASE BOOLEAN,
	DEMO_CASE_LABEL VARCHAR(16777216)
);

create or replace TABLE BORROWER_STATE (
	BORROWER_ID VARCHAR(16777216),
	FULL_NAME VARCHAR(16777216),
	CITY VARCHAR(16777216),
	STATE VARCHAR(16777216),
	CITY_TIER NUMBER(1,0),
	PRIMARY_LANGUAGE VARCHAR(16777216),
	OCCUPATION_TYPE VARCHAR(14),
	MONTHLY_INCOME_INR NUMBER(28,0),
	BUREAU_SCORE NUMBER(20,0),
	BUREAU_SCORE_BAND VARCHAR(9),
	OWN_LOAN_COUNT NUMBER(18,0),
	OWN_PRODUCT_COUNT NUMBER(18,0),
	TOTAL_OUTSTANDING_INR FLOAT,
	TOTAL_ARREARS_INR FLOAT,
	OWN_EMI_INR FLOAT,
	MAX_DPD_OWN NUMBER(38,0),
	MIN_RESIDUAL_MONTHS NUMBER(38,0),
	MAX_RESIDUAL_MONTHS NUMBER(38,0),
	MAX_RATE_GAP_VS_BANK_PCT NUMBER(8,3),
	BORROWER_ASSET_CLASS VARCHAR(8),
	IS_NPA BOOLEAN,
	NPA_UPGRADE_ELIGIBLE BOOLEAN,
	ARREARS_TO_CLEAR_FOR_UPGRADE_INR FLOAT,
	PERFORMING_LOANS_DRAGGED_TO_NPA NUMBER(18,0),
	EXTERNAL_TRADELINE_COUNT NUMBER(18,0),
	EXTERNAL_LENDER_COUNT NUMBER(18,0),
	TOTAL_LENDER_COUNT NUMBER(19,0),
	IS_LOAN_STACKED BOOLEAN,
	EXTERNAL_BALANCE_INR NUMBER(38,0),
	EXTERNAL_EMI_INR NUMBER(38,0),
	EXTERNAL_MAX_DPD NUMBER(20,0),
	FINTECH_TRADELINES NUMBER(13,0),
	MFI_TRADELINES NUMBER(13,0),
	TOTAL_EMI_INR FLOAT,
	FOIR_OWN_BOOK_PCT FLOAT,
	FOIR_TRUE_PCT FLOAT,
	EARLY_WARNING_MANDATES NUMBER(13,0),
	TECHNICAL_MANDATE_FAILURES NUMBER(13,0),
	CAPACITY_MANDATE_FAILURES NUMBER(13,0),
	INTENT_MANDATE_FAILURES NUMBER(13,0),
	IS_PRE_DELINQUENT_WARNING BOOLEAN,
	IS_DEMO_CASE BOOLEAN,
	DEMO_CASE_LABEL VARCHAR(16777216)
);

create or replace TABLE BUREAU_TRADELINE (
	TRADELINE_ID VARCHAR(16777216),
	BORROWER_ID VARCHAR(16777216),
	LENDER_NAME VARCHAR(16777216),
	LENDER_TYPE VARCHAR(16777216),
	PRODUCT_TYPE VARCHAR(16),
	IS_OWN_BOOK BOOLEAN,
	SANCTIONED_AMOUNT_INR NUMBER(24,0),
	ROI_PCT NUMBER(27,2),
	TENOR_MONTHS NUMBER(20,0),
	OPENED_DATE DATE,
	CURRENT_BALANCE_INR NUMBER(38,0),
	EMI_AMOUNT_INR NUMBER(38,0),
	CURRENT_DPD NUMBER(20,0),
	TRADELINE_STATUS VARCHAR(6),
	LAST_REPORTED_DATE DATE
);

create or replace TABLE CALL_TRANSCRIPT (
	INTERACTION_ID VARCHAR(16777216),
	BORROWER_ID VARCHAR(16777216),
	LOAN_ID VARCHAR(16777216),
	CHANNEL VARCHAR(4),
	TRANSCRIPT_SEQUENCE_NUMBER NUMBER(11,0),
	TOTAL_SEQUENCE_LENGTH NUMBER(1,0),
	CONTACT_DATE DATE,
	DAYS_SINCE_PREVIOUS_CONTACT NUMBER(2,0),
	TRANSCRIPT_TEXT VARIANT,
	IS_TRUNCATED BOOLEAN,
	CREATED_AT TIMESTAMP_LTZ(9),
	IS_STUB BOOLEAN
);

create or replace TABLE CRM_CONTACT (
	CONTACT_ID VARCHAR(16777216),
	BORROWER_ID VARCHAR(16777216),
	CONTACT_DATE DATE,
	CHANNEL VARCHAR(14),
	INITIATED_BY VARCHAR(8),
	CONTACT_TYPE VARCHAR(19),
	AGENT_ID VARCHAR(16777216),
	RESOLUTION_STATUS VARCHAR(9),
	RESOLUTION_DATE DATE,
	SATISFACTION_SCORE NUMBER(1,0),
	NOTES_SUMMARY VARCHAR(16777216)
);

create or replace TABLE DIM_ACTION (
	ACTION_CODE VARCHAR(16777216) NOT NULL,
	ACTION_NAME VARCHAR(16777216) NOT NULL,
	ACTION_FAMILY VARCHAR(16777216) NOT NULL,
	BUREAU_REPORTING_IMPACT VARCHAR(16777216) NOT NULL,
	MARGIN_IMPACT_BPS NUMBER(8,2) NOT NULL,
	OPEX_COST_INR NUMBER(10,2) NOT NULL,
	REQUIRES_HUMAN_APPROVAL BOOLEAN NOT NULL,
	IS_LAST_RESORT BOOLEAN NOT NULL,
	MIN_DPD NUMBER(5,0),
	MAX_DPD NUMBER(5,0),
	MIN_RESIDUAL_MONTHS NUMBER(4,0),
	MIN_RATE_GAP_PCT NUMBER(6,3),
	MANDATORY_DISCLOSURE VARCHAR(16777216),
	ELIGIBILITY_NOTE VARCHAR(16777216)
)COMMENT='Next-best-action catalogue. Eligibility is DETERMINISTIC - the LLM may not invent or bypass these gates. bureau_reporting_impact drives mandatory borrower disclosure under FPC.'
;

create or replace TABLE DIM_AGENCY (
	AGENCY_ID VARCHAR(16777216) NOT NULL,
	AGENCY_NAME VARCHAR(16777216) NOT NULL,
	IS_OUTSOURCED BOOLEAN NOT NULL,
	BASE_CITY VARCHAR(16777216),
	FPC_TRAINING_CURRENT BOOLEAN NOT NULL,
	ONBOARDED_DATE DATE
)COMMENT='Collections agencies. RBI FPC: the LENDER is accountable for agent conduct - outsourcing does not outsource liability. Hence agency-level breach tracking.'
;

create or replace TABLE DIM_AGENT (
	AGENT_ID VARCHAR(16777216) NOT NULL,
	AGENT_NAME VARCHAR(16777216) NOT NULL,
	AGENCY_ID VARCHAR(16777216) NOT NULL,
	IS_OUTSOURCED BOOLEAN NOT NULL,
	AGENT_ROLE VARCHAR(16777216) NOT NULL,
	PRIMARY_LANGUAGE VARCHAR(16777216) NOT NULL,
	BASE_CITY VARCHAR(16777216) NOT NULL,
	IS_ACTIVE BOOLEAN NOT NULL
)COMMENT='Servicing and collections agents. is_outsourced denormalised from agency for query convenience.'
;

create or replace TABLE DIM_GEOGRAPHY (
	CITY VARCHAR(16777216) NOT NULL,
	STATE VARCHAR(16777216) NOT NULL,
	REGION VARCHAR(16777216) NOT NULL,
	CITY_TIER NUMBER(1,0) NOT NULL,
	PINCODE_PREFIX VARCHAR(16777216) NOT NULL,
	PRIMARY_LANGUAGE VARCHAR(16777216) NOT NULL
)COMMENT='Indian city reference. Tier 2/3 weighted, matching an NBFC semi-urban footprint.'
;

create or replace TABLE LOAN_ACCOUNT (
	LOAN_ID VARCHAR(16777216),
	BORROWER_ID VARCHAR(16777216),
	PRODUCT_CODE VARCHAR(16777216),
	PRODUCT_NAME VARCHAR(16777216),
	IS_SECURED BOOLEAN,
	SANCTION_AMOUNT_INR NUMBER(38,0),
	DISBURSED_AMOUNT_INR NUMBER(38,0),
	ROI_PCT NUMBER(7,3),
	BANK_BENCHMARK_ROI_PCT NUMBER(6,3),
	RATE_GAP_VS_BANK_PCT NUMBER(8,3),
	RATE_TYPE VARCHAR(8),
	IS_REPO_LINKED BOOLEAN,
	TENOR_MONTHS NUMBER(33,0),
	EMI_AMOUNT_INR FLOAT,
	DISBURSAL_DATE DATE,
	MATURITY_DATE DATE,
	MONTHS_ELAPSED NUMBER(38,0),
	RESIDUAL_MONTHS NUMBER(38,0),
	OUTSTANDING_PRINCIPAL_INR FLOAT,
	CURRENT_DPD NUMBER(38,0),
	UNPAID_EMI_COUNT NUMBER(38,0),
	ARREARS_AMOUNT_INR FLOAT,
	SOURCING_CHANNEL VARCHAR(7),
	HAS_NACH_MANDATE BOOLEAN,
	IS_ACTIVE BOOLEAN
);

create or replace TABLE MANDATE (
	MANDATE_ID VARCHAR(16777216),
	LOAN_ID VARCHAR(16777216),
	BORROWER_ID VARCHAR(16777216),
	MANDATE_TYPE VARCHAR(11),
	SPONSOR_BANK VARCHAR(16777216),
	REGISTRATION_DATE DATE,
	MANDATE_STATUS VARCHAR(21),
	LAST_FAILURE_REASON VARCHAR(16777216),
	LAST_FAILURE_DATE DATE,
	CONSECUTIVE_FAILURES NUMBER(20,0),
	FAILURE_ATTRIBUTION VARCHAR(9),
	IS_EARLY_WARNING BOOLEAN
);

create or replace TABLE PAYMENT_TXN (
	TXN_ID VARCHAR(16777216),
	LOAN_ID VARCHAR(16777216),
	BORROWER_ID VARCHAR(16777216),
	INSTALLMENT_NUMBER NUMBER(11,0),
	DUE_DATE DATE,
	PAYMENT_STATUS VARCHAR(12),
	AMOUNT_PAID_INR FLOAT,
	PAYMENT_DATE DATE,
	PAYMENT_MODE VARCHAR(11),
	FAILURE_REASON VARCHAR(16777216)
);

create or replace TABLE REPAYMENT_SCHEDULE (
	SCHEDULE_ID VARCHAR(16777216),
	LOAN_ID VARCHAR(16777216),
	BORROWER_ID VARCHAR(16777216),
	INSTALLMENT_NUMBER NUMBER(11,0),
	DUE_DATE DATE,
	DUE_AMOUNT_INR FLOAT,
	INTEREST_COMPONENT_INR FLOAT,
	PRINCIPAL_COMPONENT_INR FLOAT,
	OPENING_BALANCE_INR FLOAT,
	CLOSING_BALANCE_INR FLOAT
);

-- LOAN_ECONOMICS: the view where BT risk is forced to zero at credit distress, at the score itself.
create or replace view LOAN_ECONOMICS(
	LOAN_ID,
	BORROWER_ID,
	PRODUCT_CODE,
	IS_SECURED,
	SANCTION_AMOUNT_INR,
	OUTSTANDING_PRINCIPAL_INR,
	EMI_AMOUNT_INR,
	ROI_PCT,
	BANK_BENCHMARK_ROI_PCT,
	RATE_GAP_VS_BANK_PCT,
	RATE_TYPE,
	IS_REPO_LINKED,
	COST_OF_FUNDS_PCT,
	GROSS_SPREAD_PCT,
	NIM_PCT,
	TENOR_MONTHS,
	MONTHS_ELAPSED,
	RESIDUAL_MONTHS,
	CURRENT_DPD,
	ARREARS_AMOUNT_INR,
	BT_MIN_RESIDUAL,
	SWITCHING_COST_ASSUMPTION,
	BORROWER_MAX_DPD_OWN,
	BORROWER_ASSET_CLASS,
	RETAINED_NIM_VALUE_INR,
	BT_RISK_SCORE,
	BT_IS_ECONOMICALLY_RATIONAL,
	BT_REDUCTION_NEEDED_PCT,
	BT_OFFER_COST_INR,
	BT_NET_VALUE_IF_OFFERED_INR,
	BT_RECOMMENDED_STANCE,
	BT_RATIONALE
) as
WITH cfg AS (
    SELECT MAX(CASE WHEN param_key='cost_of_funds_blended_pct' THEN param_value END) AS cof_pct,
           MAX(CASE WHEN param_key='bt_min_rate_gap_pct'       THEN param_value END) AS bt_min_gap
    FROM BORROWER360.UTIL.CONFIG_ECONOMIC_ASSUMPTION),
econ AS (
    SELECT l.*, c.target_gnpa_pct, g.cof_pct, g.bt_min_gap, t.min_residual_months AS bt_min_residual,
           t.switching_cost_assumption,
           bs.max_dpd_own AS borrower_max_dpd_own, bs.borrower_asset_class,
        ROUND(l.roi_pct - g.cof_pct, 3) AS gross_spread_pct,
        ROUND(l.roi_pct - g.cof_pct - (c.target_gnpa_pct * 0.60) - 1.0, 3) AS nim_pct
    FROM BORROWER360.CURATED.LOAN_ACCOUNT l
    JOIN BORROWER360.UTIL.CONFIG_PRODUCT_CALIBRATION c ON c.product_code = l.product_code
    JOIN BORROWER360.UTIL.CONFIG_BT_THRESHOLD t ON t.product_code = l.product_code
    JOIN BORROWER360.CURATED.BORROWER_STATE bs ON bs.borrower_id = l.borrower_id
    CROSS JOIN cfg g
    WHERE l.is_active),
bt AS (
    SELECT e.*,
        ROUND(e.outstanding_principal_inr * (e.nim_pct/100.0) * (e.residual_months/12.0), 0) AS retained_nim_value_inr,
        (e.borrower_max_dpd_own = 0 AND e.rate_gap_vs_bank_pct >= e.bt_min_gap AND e.residual_months >= e.bt_min_residual) AS bt_is_economically_rational,
        (e.borrower_max_dpd_own = 0 AND e.rate_gap_vs_bank_pct >= e.bt_min_gap) AS bt_has_incentive,
        CASE WHEN e.borrower_max_dpd_own >= 1 THEN 0
             ELSE GREATEST(e.rate_gap_vs_bank_pct - e.bt_min_gap, 0) END AS bt_reduction_needed_pct
    FROM econ e)
SELECT loan_id, borrower_id, product_code, is_secured,
    sanction_amount_inr, outstanding_principal_inr, emi_amount_inr,
    roi_pct, bank_benchmark_roi_pct, rate_gap_vs_bank_pct, rate_type, is_repo_linked,
    cof_pct AS cost_of_funds_pct, gross_spread_pct, nim_pct,
    tenor_months, months_elapsed, residual_months, current_dpd, arrears_amount_inr,
    bt_min_residual, switching_cost_assumption,
    borrower_max_dpd_own, borrower_asset_class,
    retained_nim_value_inr,
    CASE WHEN borrower_max_dpd_own >= 1 THEN 0
         WHEN NOT bt_has_incentive THEN 0
         WHEN NOT bt_is_economically_rational THEN 0
         ELSE ROUND(LEAST(rate_gap_vs_bank_pct / 5.0, 1.0) * LEAST(residual_months / 84.0, 1.0) * 100, 1)
    END AS bt_risk_score,
    bt_is_economically_rational,
    ROUND(bt_reduction_needed_pct,3) AS bt_reduction_needed_pct,
    ROUND(outstanding_principal_inr*(bt_reduction_needed_pct/100.0)*(residual_months/12.0),0) AS bt_offer_cost_inr,
    ROUND(retained_nim_value_inr - outstanding_principal_inr*(bt_reduction_needed_pct/100.0)*(residual_months/12.0),0) AS bt_net_value_if_offered_inr,
    CASE
        WHEN borrower_max_dpd_own >= 1 THEN 'ZERO_CREDIT_DISTRESS'
        WHEN NOT bt_has_incentive THEN 'NO_SIGNAL'
        WHEN NOT bt_is_economically_rational THEN 'SIGNAL_BUT_NOT_RATIONAL'
        WHEN retained_nim_value_inr - outstanding_principal_inr*(bt_reduction_needed_pct/100.0)*(residual_months/12.0) > 0
            THEN 'COUNTER_OFFER_JUSTIFIED'
        ELSE 'LET_GO_RETENTION_UNPROFITABLE'
    END AS bt_recommended_stance,
    CASE
        WHEN borrower_max_dpd_own >= 1
            THEN 'RULE: borrower is in credit distress (own-book DPD >= 1, asset class ' || borrower_asset_class ||
                 '). Credit risk and balance-transfer risk are separate; no rival refinances a delinquent borrower, so BT risk is forced to zero regardless of rate gap or residual tenor.'
        WHEN NOT bt_has_incentive THEN 'Rate gap below the ' || bt_min_gap || 'pp threshold. No transfer incentive exists.'
        WHEN NOT bt_is_economically_rational
            THEN 'Rate gap of ' || rate_gap_vs_bank_pct || 'pp exists, but residual tenor of ' || residual_months ||
                 ' months is below the ' || bt_min_residual || '-month threshold for ' || product_code ||
                 ' (' || switching_cost_assumption || '). Interest saved cannot cover switching costs - not a genuine flight risk.'
        ELSE 'Rate gap of ' || rate_gap_vs_bank_pct || 'pp with ' || residual_months || ' months residual, above the '
             || bt_min_residual || '-month ' || product_code || ' threshold - transfer is economically rational.'
    END AS bt_rationale
FROM bt;
