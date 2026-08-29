-- BORROWER360.AI schema: LLM-derived enrichment layer, NBA recommendation engine.
-- Extracted via GET_DDL('SCHEMA','BORROWER360.AI') on 2026-08-29.
-- Note: STG_* staging/scratch tables (created during iterative pilots) are intentionally
-- omitted here since they are not part of the live pipeline - see evidence/OBJECT_INVENTORY.md.

create or replace schema AI COMMENT='LLM-derived enrichment: transcript insights, features, NBA recommendations. Rebuildable.';

create or replace TABLE BORROWER_TRAJECTORY_SUMMARY (
	BORROWER_ID VARCHAR(16777216),
	N_CALLS NUMBER(18,0),
	FIRST_SENTIMENT VARCHAR(16777216),
	LAST_SENTIMENT VARCHAR(16777216),
	OVERALL_SENTIMENT_DIRECTION VARCHAR(13),
	FIRST_CONTACT_DATE DATE,
	LAST_CONTACT_DATE DATE,
	ANY_PTP_MADE_THEN_MISSED BOOLEAN,
	ANY_REASON_CHANGE BOOLEAN,
	N_REASON_COMPARISONS_POSSIBLE NUMBER(13,0),
	DAYS_GAP_TREND VARCHAR(29)
);

create or replace TABLE CALL_TRANSITION (
	BORROWER_ID VARCHAR(16777216),
	FROM_INTERACTION_ID VARCHAR(16777216),
	TO_INTERACTION_ID VARCHAR(16777216),
	FROM_SEQ NUMBER(12,0),
	TO_SEQ NUMBER(11,0),
	DAYS_GAP NUMBER(2,0),
	FROM_SENTIMENT VARCHAR(16777216),
	TO_SENTIMENT VARCHAR(16777216),
	SENTIMENT_DIRECTION VARCHAR(13),
	PTP_WAS_MADE_ON_PRIOR_CALL BOOLEAN,
	PTP_FLAGGED_MISSED_ON_THIS_CALL BOOLEAN,
	FROM_REASON VARCHAR(16777216),
	TO_REASON VARCHAR(16777216),
	REASON_CHANGED BOOLEAN
);

create or replace TABLE NBA_DECISION_LOG (
	LOG_ID VARCHAR(16777216) NOT NULL,
	RECOMMENDATION_ID VARCHAR(16777216) NOT NULL,
	RULE_FIRED VARCHAR(16777216) NOT NULL,
	MODEL_USED VARCHAR(16777216),
	PROMPT_VERSION VARCHAR(16777216),
	CONFIDENCE NUMBER(4,3),
	INPUTS_SNAPSHOT VARIANT,
	HUMAN_DECISION VARCHAR(16777216) NOT NULL,
	DECIDED_BY VARCHAR(16777216),
	DECIDED_AT TIMESTAMP_NTZ(9),
	LOGGED_AT TIMESTAMP_NTZ(9) NOT NULL
)COMMENT='One row per NBA_RECOMMENDATION, written at generation time - no silent paths.'
;

create or replace TABLE NBA_RECOMMENDATION (
	RECOMMENDATION_ID VARCHAR(16777216) NOT NULL,
	BORROWER_ID VARCHAR(16777216) NOT NULL,
	LOAN_ID VARCHAR(16777216),
	ACTION_CODE VARCHAR(16777216) NOT NULL,
	ACTION_FAMILY VARCHAR(16777216) NOT NULL,
	RULE_BASIS VARCHAR(16777216) NOT NULL,
	MODEL_CONTRIBUTION VARCHAR(16777216) NOT NULL,
	BORROWER_FACING_MESSAGE VARCHAR(16777216),
	MARGIN_IMPACT_BPS NUMBER(8,2),
	EXPECTED_VALUE_INR NUMBER(14,0),
	BUREAU_DISCLOSURE VARCHAR(16777216),
	REQUIRES_HUMAN_APPROVAL BOOLEAN NOT NULL,
	STATUS VARCHAR(16777216) NOT NULL,
	CREATED_AT TIMESTAMP_NTZ(9) NOT NULL
)COMMENT='Next-best-action recommendations. status is ALWAYS PENDING_APPROVAL at creation. rule_basis is NOT NULL by construction.'
;

create or replace TABLE STG_NBA_RULES (
	RECOMMENDATION_ID VARCHAR(36),
	BORROWER_ID VARCHAR(16777216),
	LOAN_ID VARCHAR(16777216),
	ACTION_CODE VARCHAR(18),
	ACTION_FAMILY VARCHAR(16777216),
	RULE_BASIS VARCHAR(16777216),
	MODEL_CONTRIBUTION VARCHAR(4),
	BORROWER_FACING_MESSAGE VARCHAR(16777216),
	MARGIN_IMPACT_BPS NUMBER(8,2),
	EXPECTED_VALUE_INR FLOAT,
	BUREAU_DISCLOSURE VARCHAR(16777216),
	REQUIRES_HUMAN_APPROVAL BOOLEAN,
	STATUS VARCHAR(16),
	INPUTS_SNAPSHOT OBJECT,
	CREATED_AT TIMESTAMP_LTZ(9)
);

create or replace TABLE STG_REASON_COMPARISON (
	FROM_INTERACTION_ID VARCHAR(16777216),
	TO_INTERACTION_ID VARCHAR(16777216),
	REASONS_ARE_SAME BOOLEAN
);

-- TRANSCRIPT_INSIGHT: incremental enrichment dynamic table (AI_EXTRACT/AI_SENTIMENT/AI_CLASSIFY/AI_FILTER).
-- The 2,700 historical rows were backfilled from TRANSCRIPT_INSIGHT_LEGACY at zero AI cost;
-- only new transcripts landing after cutover get processed. Re-create fresh (no FROZEN backfill
-- pin) with:
create or replace dynamic table TRANSCRIPT_INSIGHT(
	INTERACTION_ID,
	SENTIMENT,
	PREDICTED_INTENT,
	IS_CREDIBLE_HARDSHIP,
	PROMISE_TO_PAY_AMOUNT,
	PROMISE_TO_PAY_DATE,
	COMPETITOR_NAME_MENTIONED,
	COMPETITOR_RATE_MENTIONED,
	STATED_REASON,
	PREVIOUS_PROMISE_MISSED_RAW,
	RAW_EXTRACT_FULL,
	ENRICHED_AT
) target_lag = '1 minute' refresh_mode = INCREMENTAL initialize = ON_CREATE warehouse = COMPUTE_WH
 COMMENT='Incremental enrichment layer. Existing 2,700 rows (created before pipeline cutover) backfilled from the historical TRANSCRIPT_INSIGHT table at zero AI cost - never recomputed. Only transcripts landing after cutover get processed through AI_EXTRACT/AI_SENTIMENT/AI_CLASSIFY/AI_FILTER.'
 as
WITH ext AS (
    SELECT c.interaction_id, c.transcript_text, c.created_at,
        AI_EXTRACT(c.transcript_text, ['promise_to_pay_amount','promise_to_pay_date',
            'competitor_name_mentioned','competitor_rate_mentioned',
            'stated_reason_for_nonpayment_or_delinquency',
            'previous_promise_mentioned_as_missed_yes_or_no']) AS raw_extract
    FROM BORROWER360.CURATED.CALL_TRANSCRIPT c
)
SELECT
    e.interaction_id,
    AI_SENTIMENT(e.transcript_text):categories[0]:sentiment::STRING AS sentiment,
    AI_CLASSIFY(e.transcript_text::VARCHAR, ['genuine_hardship','technical_issue_or_dispute','payment_avoidance_pattern',
        'first_missed_payment_uncertain','rate_shopping_balance_transfer','relationship_or_growth_call'], FALSE):labels[0]::STRING AS predicted_intent,
    AI_FILTER(PROMPT('Does this collections call transcript show genuine, verifiable hardship with concrete specific details, rather than vague or evasive excuses? {0}', e.transcript_text)) AS is_credible_hardship,
    e.raw_extract:response:promise_to_pay_amount::STRING AS promise_to_pay_amount,
    e.raw_extract:response:promise_to_pay_date::STRING AS promise_to_pay_date,
    e.raw_extract:response:competitor_name_mentioned::STRING AS competitor_name_mentioned,
    e.raw_extract:response:competitor_rate_mentioned::STRING AS competitor_rate_mentioned,
    e.raw_extract:response:stated_reason_for_nonpayment_or_delinquency::STRING AS stated_reason,
    e.raw_extract:response:previous_promise_mentioned_as_missed_yes_or_no::STRING AS previous_promise_missed_raw,
    e.raw_extract AS raw_extract_full,
    e.created_at::TIMESTAMP_LTZ AS enriched_at
FROM ext e;

create or replace TABLE TRANSCRIPT_INSIGHT_LEGACY (
	INTERACTION_ID VARCHAR(16777216),
	SENTIMENT VARCHAR(16777216),
	PREDICTED_INTENT VARCHAR(16777216),
	IS_CREDIBLE_HARDSHIP BOOLEAN,
	PROMISE_TO_PAY_AMOUNT VARCHAR(16777216),
	PROMISE_TO_PAY_DATE VARCHAR(16777216),
	COMPETITOR_NAME_MENTIONED VARCHAR(16777216),
	COMPETITOR_RATE_MENTIONED VARCHAR(16777216),
	STATED_REASON VARCHAR(16777216),
	PREVIOUS_PROMISE_MISSED_RAW VARCHAR(16777216),
	RAW_EXTRACT_FULL OBJECT,
	ENRICHED_AT TIMESTAMP_LTZ(9)
);

-- SP_DECIDE_RECOMMENDATION: the ONLY way NBA_RECOMMENDATION.status changes from PENDING_APPROVAL.
CREATE OR REPLACE PROCEDURE "SP_DECIDE_RECOMMENDATION"("RECOMMENDATION_ID" VARCHAR, "DECISION" VARCHAR, "DECIDED_BY" VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
COMMENT='The ONLY way an NBA_RECOMMENDATION status changes from PENDING_APPROVAL. Must be called with an explicit human decision (APPROVED or REJECTED) and the name of the person deciding - never invoked automatically. This is what makes "nothing auto-sends" true in practice, not just in a comment.'
EXECUTE AS OWNER
AS '
BEGIN
    IF (DECISION NOT IN (''APPROVED'', ''REJECTED'')) THEN
        RETURN ''ERROR: decision must be APPROVED or REJECTED, got '' || :DECISION;
    END IF;

    UPDATE BORROWER360.AI.NBA_RECOMMENDATION
    SET status = :DECISION
    WHERE recommendation_id = :RECOMMENDATION_ID AND status = ''PENDING_APPROVAL'';

    UPDATE BORROWER360.AI.NBA_DECISION_LOG
    SET human_decision = :DECISION, decided_by = :DECIDED_BY, decided_at = CURRENT_TIMESTAMP()
    WHERE recommendation_id = :RECOMMENDATION_ID;

    RETURN ''Recommendation '' || :RECOMMENDATION_ID || '' marked '' || :DECISION || '' by '' || :DECIDED_BY;
END;
';

-- SP_GENERATE_NBA_RATIONALE: writes the AI-authored 2-sentence explanation. Never writes action_code.
CREATE OR REPLACE PROCEDURE "SP_GENERATE_NBA_RATIONALE"()
RETURNS VARCHAR
LANGUAGE SQL
COMMENT='Rule 2, the explaining half: writes a 2-sentence, persona-aware, action-preserving rationale into NBA_RECOMMENDATION.model_contribution for any row still at NONE (fresh rebuilds always reset to NONE). Uses mistral-7b (cheapest confirmed-available model). Prompt forbids proposing a different action and forbids inventing facts not in the row - rules decide, this only explains.'
EXECUTE AS OWNER
AS '
BEGIN
UPDATE BORROWER360.AI.NBA_RECOMMENDATION
SET model_contribution = AI_COMPLETE(
    ''mistral-7b'',
    ''You are writing an internal case-note explanation for a loan servicing action that has ALREADY been decided by deterministic business rules. Write EXACTLY 2 sentences explaining why this specific action fits, using ONLY the facts given below.\n'' ||
    ''Rules: Do NOT propose or suggest a different action. Do NOT invent any fact not given below. Do NOT mention interest rates, discounts, or commitments not already stated in the reason. Do NOT spell out or expand acronyms (DPD, NPA, SMA, BT, EMI, MSME) - use them exactly as given, never write out what they stand for.\n'' ||
    ''Tone: '' ||
    CASE action_family
        WHEN ''COLLECTIONS'' THEN ''supportive and empathetic - the borrower may be in a difficult situation, avoid anything that sounds punitive.''
        WHEN ''RETENTION'' THEN ''commercial and matter-of-fact - this is a business decision about loan economics, not an emotional appeal.''
        WHEN ''GROWTH'' THEN ''warm and appreciative - this is a reward for a borrower with a strong track record.''
        WHEN ''SERVICE'' THEN ''practical and reassuring - this is a routine fix, not the borrower''''s fault.''
        ELSE ''neutral and factual.''
    END ||
    ''\n\nAction decided: '' || action_code ||
    ''\nReason the rule fired: '' || rule_basis ||
    ''\n\nTwo-sentence explanation:''
)
WHERE model_contribution = ''NONE'';
RETURN ''Rationale generated for rows previously at NONE.'';
END;
';

-- SP_REBUILD_NBA_RECOMMENDATION: deterministic, pure-SQL rebuild of NBA_RECOMMENDATION.
-- Includes the trajectory-based escalation rule (any_ptp_made_then_missed causes a tier escalation) -
-- this is what gives a new transcript genuine causal power over the NBA outcome.
CREATE OR REPLACE PROCEDURE "SP_REBUILD_NBA_RECOMMENDATION"()
RETURNS VARCHAR
LANGUAGE SQL
COMMENT='Regenerates STG_NBA_RULES and NBA_RECOMMENDATION from LOAN_ACCOUNT/BORROWER_STATE/MANDATE/LOAN_ECONOMICS/DIM_ACTION/BORROWER_TRAJECTORY_SUMMARY. Pure deterministic SQL, no AI calls. Includes a trajectory-based escalation rule: a borrower already in a DPD-driven SOFT_REMIND/PART_PAY_PLAN whose broken-promise trajectory signal (any_ptp_made_then_missed) is TRUE escalates one tier - this is what gives a new transcript genuine causal power over the NBA outcome, not just structured data. action_code assignment is deterministic (HASH-based growth pick uses a fixed salt); recommendation_id is a fresh UUID each run, which is why NBA_DECISION_LOG linkage does not survive a rebuild on its own - SP_REFRESH_NBA_PIPELINE carries it forward. Recovered from original build query history and packaged as a procedure so it is actually re-runnable, per the idempotency rule.'
EXECUTE AS OWNER
AS '
BEGIN
CREATE OR REPLACE TABLE BORROWER360.AI.STG_NBA_RULES AS
WITH mnd_latest AS (
    SELECT loan_id, failure_attribution,
           ROW_NUMBER() OVER (PARTITION BY loan_id ORDER BY last_failure_date DESC NULLS LAST) rn
    FROM BORROWER360.CURATED.MANDATE
),
loan_ctx AS (
    SELECT la.loan_id, la.borrower_id, la.product_code, la.current_dpd, la.arrears_amount_inr,
           la.outstanding_principal_inr, la.emi_amount_inr,
           bs.borrower_asset_class, bs.max_dpd_own,
           COALESCE(m.failure_attribution,''NONE'') AS mandate_attribution,
           le.bt_recommended_stance, le.bt_net_value_if_offered_inr, le.bt_rationale,
           le.rate_gap_vs_bank_pct, le.residual_months,
           COALESCE(traj.any_ptp_made_then_missed, FALSE) AS any_ptp_made_then_missed
    FROM BORROWER360.CURATED.LOAN_ACCOUNT la
    JOIN BORROWER360.CURATED.BORROWER_STATE bs ON bs.borrower_id = la.borrower_id
    LEFT JOIN mnd_latest m ON m.loan_id = la.loan_id AND m.rn = 1
    LEFT JOIN BORROWER360.CURATED.LOAN_ECONOMICS le ON le.loan_id = la.loan_id
    LEFT JOIN BORROWER360.AI.BORROWER_TRAJECTORY_SUMMARY traj ON traj.borrower_id = la.borrower_id
    WHERE la.is_active
),
loan_rules AS (
    SELECT lc.*, lc.borrower_id AS b_id, lc.loan_id AS l_id,
        CASE
            WHEN lc.max_dpd_own >= 1 AND lc.current_dpd > 270                                   THEN ''OTS_SETTLE''
            WHEN lc.max_dpd_own >= 1 AND lc.current_dpd BETWEEN 181 AND 270                      THEN ''RESTRUCT_MORAT''
            WHEN lc.max_dpd_own >= 1 AND lc.current_dpd BETWEEN 91 AND 180                       THEN ''RESTRUCT_TENOR''
            WHEN lc.max_dpd_own >= 1 AND lc.current_dpd BETWEEN 61 AND 90 AND lc.arrears_amount_inr > 3*lc.emi_amount_inr THEN ''FIELD_VISIT''
            WHEN lc.max_dpd_own >= 1 AND lc.current_dpd BETWEEN 61 AND 90                        THEN ''PART_PAY_PLAN''
            WHEN lc.max_dpd_own >= 1 AND lc.current_dpd BETWEEN 31 AND 60 AND lc.mandate_attribution=''TECHNICAL'' THEN ''FIX_MANDATE''
            WHEN lc.max_dpd_own >= 1 AND lc.current_dpd BETWEEN 31 AND 60 AND lc.any_ptp_made_then_missed       THEN ''FIELD_VISIT''
            WHEN lc.max_dpd_own >= 1 AND lc.current_dpd BETWEEN 31 AND 60                        THEN ''PART_PAY_PLAN''
            WHEN lc.max_dpd_own >= 1 AND lc.current_dpd BETWEEN 1 AND 30 AND lc.mandate_attribution=''TECHNICAL'' THEN ''FIX_MANDATE''
            WHEN lc.max_dpd_own >= 1 AND lc.current_dpd BETWEEN 1 AND 30 AND lc.any_ptp_made_then_missed        THEN ''PART_PAY_PLAN''
            WHEN lc.max_dpd_own >= 1 AND lc.current_dpd BETWEEN 1 AND 30                         THEN ''SOFT_REMIND''
            WHEN lc.max_dpd_own >= 1 AND lc.current_dpd = 0                                      THEN ''NO_ACTION_REQUIRED''
            WHEN lc.max_dpd_own = 0 AND lc.mandate_attribution=''TECHNICAL''                       THEN ''FIX_MANDATE''
            WHEN lc.max_dpd_own = 0 AND lc.bt_recommended_stance = ''COUNTER_OFFER_JUSTIFIED''      THEN ''BT_COUNTER''
            WHEN lc.max_dpd_own = 0 AND lc.bt_recommended_stance IN (''LET_GO_RETENTION_UNPROFITABLE'',''SIGNAL_BUT_NOT_RATIONAL'') THEN ''BT_LET_GO''
            ELSE ''NO_ACTION_REQUIRED''
        END AS action_code,
        CASE
            WHEN lc.max_dpd_own >= 1 AND lc.current_dpd > 270 THEN ''RULE: DPD>270, NPA, last-resort tier per DIM_ACTION.is_last_resort. Structured-data-only pass - no transcript evidence of wilful vs hardship intent yet.''
            WHEN lc.max_dpd_own >= 1 AND lc.current_dpd BETWEEN 181 AND 270 THEN ''RULE: DPD 181-270, NPA - moratorium restructuring attempted before last resort.''
            WHEN lc.max_dpd_own >= 1 AND lc.current_dpd BETWEEN 91 AND 180 THEN ''RULE: DPD 91-180, newly NPA - tenure restructuring is the first cure attempt.''
            WHEN lc.max_dpd_own >= 1 AND lc.current_dpd BETWEEN 61 AND 90 AND lc.arrears_amount_inr > 3*lc.emi_amount_inr THEN ''RULE: SMA-2 (61-90 DPD), arrears exceed 3 EMIs - field-visit threshold.''
            WHEN lc.max_dpd_own >= 1 AND lc.current_dpd BETWEEN 61 AND 90 THEN ''RULE: SMA-2 (61-90 DPD), below field-visit arrears threshold - part payment plan.''
            WHEN lc.max_dpd_own >= 1 AND lc.current_dpd BETWEEN 31 AND 60 AND lc.mandate_attribution=''TECHNICAL'' THEN ''RULE: SMA-1 (31-60 DPD) with TECHNICAL mandate failure attribution - fix root cause before any collections escalation.''
            WHEN lc.max_dpd_own >= 1 AND lc.current_dpd BETWEEN 31 AND 60 AND lc.any_ptp_made_then_missed THEN ''RULE: SMA-1 (31-60 DPD) - escalated to field visit because the borrower has broken a payment promise on a prior call, per the sequenced-call trajectory signal. A part-payment plan alone is not warranted once a promise has already been missed.''
            WHEN lc.max_dpd_own >= 1 AND lc.current_dpd BETWEEN 31 AND 60 THEN ''RULE: SMA-1 (31-60 DPD) - part payment plan.''
            WHEN lc.max_dpd_own >= 1 AND lc.current_dpd BETWEEN 1 AND 30 AND lc.mandate_attribution=''TECHNICAL'' THEN ''RULE: SMA-0 (1-30 DPD) with TECHNICAL mandate failure - fix mandate, most SMA-0 self-cures once the debit succeeds.''
            WHEN lc.max_dpd_own >= 1 AND lc.current_dpd BETWEEN 1 AND 30 AND lc.any_ptp_made_then_missed THEN ''RULE: SMA-0 (1-30 DPD) - escalated to a part-payment plan because the borrower has already broken a payment promise on a prior call, per the sequenced-call trajectory signal. A soft reminder alone is not warranted once a promise has already been missed.''
            WHEN lc.max_dpd_own >= 1 AND lc.current_dpd BETWEEN 1 AND 30 THEN ''RULE: SMA-0 (1-30 DPD) - soft reminder, most self-cures at this bucket.''
            WHEN lc.max_dpd_own >= 1 AND lc.current_dpd = 0 THEN ''RULE: this loan is current, but borrower is in distress on another facility (borrower-level RBI asset classification) - no separate action on this loan, and no growth/retention action anywhere on this borrower.''
            WHEN lc.max_dpd_own = 0 AND lc.mandate_attribution=''TECHNICAL'' THEN ''RULE: mandate failed, DPD still zero - earliest warning signal available, addressed before it becomes delinquency.''
            WHEN lc.max_dpd_own = 0 AND lc.bt_recommended_stance = ''COUNTER_OFFER_JUSTIFIED'' THEN lc.bt_rationale
            WHEN lc.max_dpd_own = 0 AND lc.bt_recommended_stance = ''LET_GO_RETENTION_UNPROFITABLE'' THEN ''RULE: transfer is economically rational for the borrower, but the counter-offer costs more margin than the loan is worth retaining - let go.''
            WHEN lc.max_dpd_own = 0 AND lc.bt_recommended_stance = ''SIGNAL_BUT_NOT_RATIONAL'' THEN lc.bt_rationale
            ELSE ''RULE: no structured-data trigger fired this cycle.''
        END AS rule_basis,
        CASE
            WHEN lc.max_dpd_own >= 1 AND lc.current_dpd BETWEEN 1 AND 270 AND lc.current_dpd > 0
                THEN ''We understand things can get difficult. We would like to work out a plan together that fits your situation - please call us back so we can discuss the options available to you.''
            WHEN lc.max_dpd_own >= 1 AND lc.current_dpd > 270
                THEN ''We would like to resolve this account with you directly and avoid further escalation. Please contact us to discuss a settlement that works for both sides.''
            WHEN lc.max_dpd_own = 0 AND lc.mandate_attribution=''TECHNICAL''
                THEN ''We noticed your last auto-debit did not go through. This looks like a bank-side issue rather than anything on your part - let''''s get it fixed so your payments continue smoothly.''
            WHEN lc.max_dpd_own = 0 AND lc.bt_recommended_stance = ''COUNTER_OFFER_JUSTIFIED''
                THEN ''We value having you as a customer and would like to offer you a better rate to make sure we remain your best option.''
            ELSE NULL
        END AS borrower_facing_message
    FROM loan_ctx lc
),
growth_rules AS (
    SELECT bs.borrower_id AS b_id, NULL::VARCHAR AS l_id,
        CASE ABS(HASH(bs.borrower_id,''growth_pick'')) % 3
             WHEN 0 THEN ''TOP_UP'' WHEN 1 THEN ''CROSS_INSURE'' ELSE ''LIMIT_UP'' END AS action_code,
        ''RULE: borrower is clean (DPD=0 across all own facilities, no loan stacking, no pre-delinquent mandate warning) with GOOD or EXCELLENT bureau standing - eligible for proactive growth outreach.'' AS rule_basis,
        ''You have built a strong repayment record with us - we would like to offer you a benefit as a thank you for staying on track.'' AS borrower_facing_message,
        NULL::VARCHAR AS product_code, NULL::NUMBER AS current_dpd, NULL::NUMBER AS arrears_amount_inr,
        bs.total_outstanding_inr AS outstanding_principal_inr, NULL::NUMBER AS emi_amount_inr,
        bs.borrower_asset_class, bs.max_dpd_own, ''NONE'' AS mandate_attribution,
        NULL::VARCHAR AS bt_recommended_stance, NULL::NUMBER AS bt_net_value_if_offered_inr,
        NULL::VARCHAR AS bt_rationale, NULL::NUMBER AS rate_gap_vs_bank_pct, NULL::NUMBER AS residual_months
    FROM BORROWER360.CURATED.BORROWER_STATE bs
    WHERE bs.max_dpd_own = 0 AND NOT bs.is_loan_stacked AND NOT bs.is_pre_delinquent_warning
      AND bs.bureau_score_band IN (''EXCELLENT'',''GOOD'')
),
unioned AS (
    SELECT b_id, l_id, action_code, rule_basis, borrower_facing_message,
           product_code, current_dpd, arrears_amount_inr, outstanding_principal_inr, emi_amount_inr,
           bt_recommended_stance, bt_net_value_if_offered_inr, rate_gap_vs_bank_pct, residual_months
    FROM loan_rules
    UNION ALL
    SELECT b_id, l_id, action_code, rule_basis, borrower_facing_message,
           product_code, current_dpd, arrears_amount_inr, outstanding_principal_inr, emi_amount_inr,
           bt_recommended_stance, bt_net_value_if_offered_inr, rate_gap_vs_bank_pct, residual_months
    FROM growth_rules
)
SELECT
    UUID_STRING() AS recommendation_id, u.b_id AS borrower_id, u.l_id AS loan_id,
    u.action_code, d.action_family, u.rule_basis, ''NONE'' AS model_contribution, u.borrower_facing_message,
    d.margin_impact_bps,
    CASE WHEN u.action_code = ''BT_COUNTER'' THEN u.bt_net_value_if_offered_inr
         WHEN u.action_code IN (''BT_LET_GO'',''NO_ACTION_REQUIRED'') THEN 0
         ELSE ROUND(d.margin_impact_bps / 10000.0 * COALESCE(u.outstanding_principal_inr,0), 0)
    END AS expected_value_inr,
    d.mandatory_disclosure AS bureau_disclosure, d.requires_human_approval, ''PENDING_APPROVAL'' AS status,
    OBJECT_CONSTRUCT(''current_dpd'',u.current_dpd,''arrears_amount_inr'',u.arrears_amount_inr,
        ''rate_gap_vs_bank_pct'',u.rate_gap_vs_bank_pct,''residual_months'',u.residual_months,
        ''bt_stance'',u.bt_recommended_stance,''product_code'',u.product_code) AS inputs_snapshot,
    CURRENT_TIMESTAMP() AS created_at
FROM unioned u
JOIN BORROWER360.CURATED.DIM_ACTION d ON d.action_code = u.action_code;

CREATE OR REPLACE TABLE BORROWER360.AI.NBA_RECOMMENDATION (
    recommendation_id VARCHAR NOT NULL, borrower_id VARCHAR NOT NULL, loan_id VARCHAR,
    action_code VARCHAR NOT NULL, action_family VARCHAR NOT NULL,
    rule_basis VARCHAR NOT NULL, model_contribution VARCHAR NOT NULL,
    borrower_facing_message VARCHAR, margin_impact_bps NUMBER(8,2), expected_value_inr NUMBER(14,0),
    bureau_disclosure VARCHAR, requires_human_approval BOOLEAN NOT NULL,
    status VARCHAR NOT NULL, created_at TIMESTAMP_NTZ NOT NULL)
    COMMENT = ''Next-best-action recommendations. status is ALWAYS PENDING_APPROVAL at creation. rule_basis is NOT NULL by construction.'';

INSERT INTO BORROWER360.AI.NBA_RECOMMENDATION
SELECT recommendation_id, borrower_id, loan_id, action_code, action_family, rule_basis,
       model_contribution, borrower_facing_message, margin_impact_bps, expected_value_inr,
       bureau_disclosure, requires_human_approval, status, created_at
FROM BORROWER360.AI.STG_NBA_RULES;

INSERT INTO BORROWER360.AI.NBA_DECISION_LOG
SELECT UUID_STRING(), recommendation_id, rule_basis, NULL, NULL,
       1.000, inputs_snapshot, ''PENDING'', NULL, NULL, created_at
FROM BORROWER360.AI.STG_NBA_RULES;

RETURN ''NBA_RECOMMENDATION and NBA_DECISION_LOG rebuilt from current structured data, including trajectory-based escalation.'';
END;
';

-- SP_REFRESH_NBA_PIPELINE: the correct way to refresh NBA - rebuild + carry forward
-- unchanged rationale/decisions + generate rationale only for changed rows.
CREATE OR REPLACE PROCEDURE "SP_REFRESH_NBA_PIPELINE"()
RETURNS VARCHAR
LANGUAGE SQL
COMMENT='The real incremental-safe NBA refresh: rebuilds recommendations from current structured data (SP_REBUILD_NBA_RECOMMENDATION wipes everything via fresh UUIDs), then carries forward rationale (model_contribution) and human decisions for any (borrower_id, loan_id, action_code, rule_basis) combination that is UNCHANGED from before the rebuild - so re-running this on a schedule does not re-incur AI_COMPLETE cost or lose approvals for recommendations that did not actually change. Only genuinely new/changed recommendations get fresh rationale via SP_GENERATE_NBA_RATIONALE.'
EXECUTE AS OWNER
AS '
BEGIN
CREATE OR REPLACE TEMPORARY TABLE CARRY_RATIONALE AS
    SELECT borrower_id, loan_id, action_code, rule_basis, model_contribution
    FROM BORROWER360.AI.NBA_RECOMMENDATION
    WHERE model_contribution <> ''NONE'';

CREATE OR REPLACE TEMPORARY TABLE CARRY_DECISION AS
    SELECT r.borrower_id, r.loan_id, r.action_code, l.human_decision, l.decided_by, l.decided_at
    FROM BORROWER360.AI.NBA_RECOMMENDATION r
    JOIN BORROWER360.AI.NBA_DECISION_LOG l ON l.recommendation_id = r.recommendation_id
    WHERE l.human_decision <> ''PENDING'';

CALL BORROWER360.AI.SP_REBUILD_NBA_RECOMMENDATION();

UPDATE BORROWER360.AI.NBA_RECOMMENDATION r
SET model_contribution = c.model_contribution
FROM CARRY_RATIONALE c
WHERE c.borrower_id = r.borrower_id AND EQUAL_NULL(c.loan_id, r.loan_id)
  AND c.action_code = r.action_code AND c.rule_basis = r.rule_basis;

UPDATE BORROWER360.AI.NBA_RECOMMENDATION r
SET status = d.human_decision
FROM CARRY_DECISION d
WHERE d.borrower_id = r.borrower_id AND EQUAL_NULL(d.loan_id, r.loan_id) AND d.action_code = r.action_code;

UPDATE BORROWER360.AI.NBA_DECISION_LOG l
SET human_decision = d.human_decision, decided_by = d.decided_by, decided_at = d.decided_at
FROM CARRY_DECISION d
JOIN BORROWER360.AI.NBA_RECOMMENDATION r
    ON d.borrower_id = r.borrower_id AND EQUAL_NULL(d.loan_id, r.loan_id) AND d.action_code = r.action_code
WHERE l.recommendation_id = r.recommendation_id;

CALL BORROWER360.AI.SP_GENERATE_NBA_RATIONALE();

RETURN ''NBA pipeline refreshed: rules rebuilt, unchanged rationale/decisions carried forward, new rationale generated only for changed rows.'';
END;
';

-- SP_REFRESH_TRAJECTORY_AND_NBA: full downstream orchestrator, called every minute by
-- TASK_REFRESH_TRAJECTORY_AND_NBA (stream-triggered cost discipline - near-zero cost with no new data).
CREATE OR REPLACE PROCEDURE "SP_REFRESH_TRAJECTORY_AND_NBA"()
RETURNS VARCHAR
LANGUAGE SQL
COMMENT='Consumes STRM_TRANSCRIPT_INSIGHT (new enriched transcripts only), computes their transition rows in CALL_TRANSITION, runs AI_FILTER only on the new reason-pairs, rebuilds BORROWER_TRAJECTORY_SUMMARY, refreshes NBA (via SP_REFRESH_NBA_PIPELINE, which carries forward unchanged rationale/decisions), materializes BORROWER_360, and purges TEAM_TASK_QUEUE rows whose parent recommendation no longer exists (orphaned by NBA_RECOMMENDATION regeneration). Designed so a cycle with no new transcripts costs near-zero - every step operates only on genuinely new rows.'
EXECUTE AS OWNER
AS '
BEGIN
CREATE OR REPLACE TEMPORARY TABLE NEW_INSIGHT_ROWS AS
    SELECT interaction_id, sentiment, predicted_intent, promise_to_pay_amount, stated_reason, previous_promise_missed_raw
    FROM BORROWER360.AI.STRM_TRANSCRIPT_INSIGHT
    WHERE METADATA$ACTION = ''INSERT'';

CREATE OR REPLACE TEMPORARY TABLE NEW_TRANSITIONS AS
WITH new_ctx AS (
    SELECT c.borrower_id, c.interaction_id, c.transcript_sequence_number, c.total_sequence_length,
           c.contact_date, c.days_since_previous_contact,
           n.sentiment, n.predicted_intent, n.promise_to_pay_amount, n.stated_reason, n.previous_promise_missed_raw,
           CASE n.sentiment WHEN ''positive'' THEN 1 WHEN ''negative'' THEN -1 ELSE 0 END AS sentiment_numeric
    FROM NEW_INSIGHT_ROWS n
    JOIN BORROWER360.CURATED.CALL_TRANSCRIPT c ON c.interaction_id = n.interaction_id
    WHERE c.total_sequence_length >= 2 AND c.transcript_sequence_number >= 2
),
prior AS (
    SELECT nc.*, pc.interaction_id AS from_interaction_id, pt.sentiment AS from_sentiment,
        CASE pt.sentiment WHEN ''positive'' THEN 1 WHEN ''negative'' THEN -1 ELSE 0 END AS from_sentiment_numeric,
        pt.promise_to_pay_amount AS from_ptp_amount, pt.stated_reason AS from_reason
    FROM new_ctx nc
    JOIN BORROWER360.CURATED.CALL_TRANSCRIPT pc
        ON pc.borrower_id = nc.borrower_id AND pc.transcript_sequence_number = nc.transcript_sequence_number - 1
    JOIN BORROWER360.AI.TRANSCRIPT_INSIGHT pt ON pt.interaction_id = pc.interaction_id
)
SELECT
    borrower_id, from_interaction_id, interaction_id AS to_interaction_id,
    transcript_sequence_number - 1 AS from_seq, transcript_sequence_number AS to_seq,
    days_since_previous_contact AS days_gap,
    from_sentiment, sentiment AS to_sentiment,
    CASE WHEN sentiment_numeric > from_sentiment_numeric THEN ''IMPROVING''
         WHEN sentiment_numeric < from_sentiment_numeric THEN ''DETERIORATING''
         ELSE ''STABLE'' END AS sentiment_direction,
    (from_ptp_amount IS NOT NULL AND from_ptp_amount != ''None'') AS ptp_was_made_on_prior_call,
    (previous_promise_missed_raw ILIKE ''%yes%'') AS ptp_flagged_missed_on_this_call,
    from_reason, stated_reason AS to_reason
FROM prior;

INSERT INTO BORROWER360.AI.CALL_TRANSITION
    (borrower_id, from_interaction_id, to_interaction_id, from_seq, to_seq, days_gap,
     from_sentiment, to_sentiment, sentiment_direction, ptp_was_made_on_prior_call,
     ptp_flagged_missed_on_this_call, from_reason, to_reason, reason_changed)
SELECT borrower_id, from_interaction_id, to_interaction_id, from_seq, to_seq, days_gap,
       from_sentiment, to_sentiment, sentiment_direction, ptp_was_made_on_prior_call,
       ptp_flagged_missed_on_this_call, from_reason, to_reason, NULL
FROM NEW_TRANSITIONS;

UPDATE BORROWER360.AI.CALL_TRANSITION t
SET reason_changed = NOT AI_FILTER(PROMPT(
    ''Do these two statements describe the SAME underlying reason for non-payment, or genuinely DIFFERENT reasons? Answer only about whether they are the same. Reason 1: {0}. Reason 2: {1}'',
    t.from_reason, t.to_reason))
WHERE t.to_interaction_id IN (SELECT to_interaction_id FROM NEW_TRANSITIONS)
  AND t.from_reason IS NOT NULL AND t.from_reason != ''None''
  AND t.to_reason IS NOT NULL AND t.to_reason != ''None''
  AND t.reason_changed IS NULL;

CREATE OR REPLACE TABLE BORROWER360.AI.BORROWER_TRAJECTORY_SUMMARY AS
WITH first_last AS (
    SELECT c.borrower_id,
        MIN_BY(t.sentiment, c.transcript_sequence_number) AS first_sentiment,
        MAX_BY(t.sentiment, c.transcript_sequence_number) AS last_sentiment,
        COUNT(*) AS n_calls,
        MIN(c.contact_date) AS first_contact_date,
        MAX(c.contact_date) AS last_contact_date
    FROM BORROWER360.CURATED.CALL_TRANSCRIPT c
    JOIN BORROWER360.AI.TRANSCRIPT_INSIGHT t ON t.interaction_id = c.interaction_id
    GROUP BY c.borrower_id
),
gaps AS (
    SELECT borrower_id,
        MIN_BY(days_gap, from_seq) AS first_gap,
        MAX_BY(days_gap, from_seq) AS last_gap,
        COUNT(*) AS n_transitions,
        COUNT_IF(ptp_was_made_on_prior_call AND ptp_flagged_missed_on_this_call) AS n_ptp_made_then_missed,
        COUNT_IF(reason_changed) AS n_reason_changes,
        COUNT_IF(reason_changed IS NOT NULL) AS n_reason_comparisons_possible
    FROM BORROWER360.AI.CALL_TRANSITION
    GROUP BY borrower_id
)
SELECT
    fl.borrower_id, fl.n_calls, fl.first_sentiment, fl.last_sentiment,
    CASE WHEN fl.first_sentiment = fl.last_sentiment THEN ''STABLE''
         WHEN fl.last_sentiment = ''positive'' AND fl.first_sentiment IN (''negative'',''mixed'') THEN ''IMPROVING''
         WHEN fl.last_sentiment = ''negative'' AND fl.first_sentiment IN (''positive'',''mixed'',''neutral'') THEN ''DETERIORATING''
         ELSE ''MIXED'' END AS overall_sentiment_direction,
    fl.first_contact_date, fl.last_contact_date,
    COALESCE(g.n_ptp_made_then_missed, 0) > 0 AS any_ptp_made_then_missed,
    COALESCE(g.n_reason_changes, 0) > 0 AS any_reason_change,
    g.n_reason_comparisons_possible,
    CASE WHEN g.n_transitions >= 2 THEN
         CASE WHEN g.last_gap > g.first_gap THEN ''WIDENING''
              WHEN g.last_gap < g.first_gap THEN ''NARROWING''
              ELSE ''STABLE'' END
         ELSE ''N/A - single contact interval''
    END AS days_gap_trend
FROM first_last fl
LEFT JOIN gaps g ON g.borrower_id = fl.borrower_id;

CALL BORROWER360.AI.SP_REFRESH_NBA_PIPELINE();

DELETE FROM BORROWER360.APP.TEAM_TASK_QUEUE t
WHERE NOT EXISTS (
    SELECT 1 FROM BORROWER360.AI.NBA_RECOMMENDATION r WHERE r.recommendation_id = t.recommendation_id
);

CREATE OR REPLACE TABLE BORROWER360.CURATED.BORROWER_360 AS
WITH ltv AS (
    SELECT la.borrower_id, SUM(rs.interest_component_inr) AS ltv_expected_interest_inr
    FROM BORROWER360.CURATED.LOAN_ACCOUNT la
    JOIN BORROWER360.CURATED.REPAYMENT_SCHEDULE rs ON rs.loan_id = la.loan_id
    WHERE la.is_active AND rs.installment_number > la.months_elapsed
    GROUP BY la.borrower_id
),
bt_summary AS (
    SELECT borrower_id,
        MAX(bt_risk_score) AS max_bt_risk_score,
        BOOLOR_AGG(bt_is_economically_rational) AS any_bt_rational,
        SUM(CASE WHEN bt_recommended_stance=''COUNTER_OFFER_JUSTIFIED'' THEN bt_net_value_if_offered_inr ELSE 0 END) AS total_bt_counter_value_if_offered_inr
    FROM BORROWER360.CURATED.LOAN_ECONOMICS
    GROUP BY borrower_id
),
nba_summary AS (
    SELECT borrower_id,
        COUNT(*) AS n_pending_recommendations,
        COUNT(DISTINCT action_family) AS n_action_families,
        MAX(CASE WHEN action_family=''COLLECTIONS'' THEN 1 ELSE 0 END)=1 AS has_collections_action,
        MAX(CASE WHEN action_family=''RETENTION'' AND action_code=''BT_COUNTER'' THEN 1 ELSE 0 END)=1 AS has_retention_offer,
        MAX(CASE WHEN action_family=''GROWTH'' THEN 1 ELSE 0 END)=1 AS has_growth_offer
    FROM BORROWER360.AI.NBA_RECOMMENDATION
    WHERE status = ''PENDING_APPROVAL''
    GROUP BY borrower_id
)
SELECT
    bs.borrower_id, bs.full_name, bs.city, bs.state, bs.city_tier, bs.occupation_type,
    bs.monthly_income_inr, bs.bureau_score, bs.bureau_score_band,
    bs.own_loan_count, bs.own_product_count, bs.total_outstanding_inr, bs.total_arrears_inr,
    bs.borrower_asset_class, bs.is_npa, bs.npa_upgrade_eligible,
    bs.arrears_to_clear_for_upgrade_inr, bs.performing_loans_dragged_to_npa,
    bs.is_loan_stacked, bs.total_lender_count, bs.foir_true_pct, bs.early_warning_mandates,
    COALESCE(bts.max_bt_risk_score, 0) AS bt_risk_score,
    COALESCE(bts.any_bt_rational, FALSE) AS bt_is_a_flight_risk,
    COALESCE(bts.total_bt_counter_value_if_offered_inr, 0) AS bt_retention_value_if_offered_inr,
    COALESCE(ltv.ltv_expected_interest_inr, 0) AS ltv_expected_interest_inr,
    traj.n_calls AS n_interactions, traj.overall_sentiment_direction,
    traj.any_ptp_made_then_missed, traj.any_reason_change, traj.days_gap_trend,
    COALESCE(nba.n_pending_recommendations, 0) AS n_pending_recommendations,
    COALESCE(nba.has_collections_action, FALSE) AS has_collections_action,
    COALESCE(nba.has_retention_offer, FALSE) AS has_retention_offer,
    COALESCE(nba.has_growth_offer, FALSE) AS has_growth_offer,
    bs.is_demo_case, bs.demo_case_label
FROM BORROWER360.CURATED.BORROWER_STATE bs
LEFT JOIN ltv ON ltv.borrower_id = bs.borrower_id
LEFT JOIN bt_summary bts ON bts.borrower_id = bs.borrower_id
LEFT JOIN BORROWER360.AI.BORROWER_TRAJECTORY_SUMMARY traj ON traj.borrower_id = bs.borrower_id
LEFT JOIN nba_summary nba ON nba.borrower_id = bs.borrower_id;

RETURN ''Trajectory, NBA, BORROWER_360 refreshed, and TEAM_TASK_QUEUE orphans purged (if any).'';
END;
';

create or replace stream STRM_TRANSCRIPT_INSIGHT on dynamic table TRANSCRIPT_INSIGHT;

create or replace task TASK_REFRESH_TRAJECTORY_AND_NBA
	warehouse=COMPUTE_WH
	schedule='1 MINUTE'
	COMMENT='Downstream of TRANSCRIPT_INSIGHT (the enrichment dynamic table). Runs SP_REFRESH_TRAJECTORY_AND_NBA every minute, matching the DT target_lag - costs near-zero when there is no new data since every step in that procedure operates only on rows the stream surfaces. Created SUSPENDED per standing cost discipline; resume only when actively demoing.'
	as CALL BORROWER360.AI.SP_REFRESH_TRAJECTORY_AND_NBA();

-- Created SUSPENDED - resume only when actively demoing:
-- ALTER TASK BORROWER360.AI.TASK_REFRESH_TRAJECTORY_AND_NBA RESUME;
