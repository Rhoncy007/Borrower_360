-- SP_REBUILD_SPINE: regenerates LOAN_ACCOUNT, MANDATE, BORROWER_STATE from CONFIG.
-- Dynamic product weighting, partial-arrears clearance, DPD clamped to months_elapsed,
-- deterministic demo borrower overrides. Idempotent.
-- Extracted via GET_DDL('SCHEMA','BORROWER360.CURATED') on 2026-08-29.

CREATE OR REPLACE PROCEDURE "SP_REBUILD_SPINE"()
RETURNS VARCHAR
LANGUAGE SQL
COMMENT='Regenerates LOAN_ACCOUNT, MANDATE, BORROWER_STATE from CONFIG. Dynamic product weighting, partial-arrears clearance, DPD clamped to months_elapsed (a loan cannot be more delinquent than it is old), deterministic demo borrower overrides. Idempotent.'
EXECUTE AS OWNER
AS '
BEGIN
CREATE OR REPLACE TABLE BORROWER360.CURATED.LOAN_ACCOUNT AS
WITH prod_bounds AS (
    SELECT product_code, product_name, is_secured, ticket_min_inr, ticket_max_inr,
           tenor_min_months, tenor_max_months, base_roi_pct, bank_benchmark_roi_pct,
           target_gnpa_pct, nach_mandate_share_pct,
           SUM(count_weight_pct) OVER (ORDER BY product_code ROWS UNBOUNDED PRECEDING) * 1000 AS cum_hi,
           (SUM(count_weight_pct) OVER (ORDER BY product_code ROWS UNBOUNDED PRECEDING) - count_weight_pct) * 1000 AS cum_lo
    FROM BORROWER360.UTIL.CONFIG_PRODUCT_CALIBRATION
),
b AS (
    SELECT borrower_id, bureau_score_band, monthly_income_inr, onboard_date,
           CASE WHEN ABS(HASH(borrower_id,''lc'')) % 100 < 65 THEN 1
                WHEN ABS(HASH(borrower_id,''lc'')) % 100 < 90 THEN 2
                WHEN ABS(HASH(borrower_id,''lc'')) % 100 < 98 THEN 3
                ELSE 4 END AS loan_count
    FROM BORROWER360.CURATED.BORROWER),
exploded AS (
    SELECT b.*, s.seq FROM b
    JOIN (SELECT SEQ4()+1 AS seq FROM TABLE(GENERATOR(ROWCOUNT=>4))) s ON s.seq <= b.loan_count),
assigned AS (
    SELECT e.*,
        ABS(HASH(e.borrower_id, e.seq, ''prod'')) % 100000 AS h_prod,
        ABS(HASH(e.borrower_id, e.seq, ''tick''))  % 1000  AS h_tick,
        ABS(HASH(e.borrower_id, e.seq, ''ten''))   % 1000  AS h_ten,
        ABS(HASH(e.borrower_id, e.seq, ''strs''))  % 10000 AS h_stress,
        ABS(HASH(e.borrower_id, e.seq, ''dpdv''))  % 1000  AS h_dpdv,
        ABS(HASH(e.borrower_id, e.seq, ''elap''))  % 1000  AS h_elap,
        ABS(HASH(e.borrower_id, e.seq, ''chan''))  % 100   AS h_chan,
        ABS(HASH(e.borrower_id, e.seq, ''rt''))    % 100   AS h_rt,
        ABS(HASH(e.borrower_id, e.seq, ''nach''))  % 100   AS h_nach,
        ABS(HASH(e.borrower_id, e.seq, ''clear'')) % 100   AS h_clear
    FROM exploded e),
joined AS (
    SELECT a.*, pb.product_code, pb.product_name, pb.is_secured, pb.ticket_min_inr, pb.ticket_max_inr,
           pb.tenor_min_months, pb.tenor_max_months, pb.base_roi_pct, pb.bank_benchmark_roi_pct,
           pb.target_gnpa_pct, pb.nach_mandate_share_pct,
           CASE a.bureau_score_band WHEN ''EXCELLENT'' THEN 0.00 WHEN ''GOOD'' THEN 0.50
                WHEN ''FAIR'' THEN 1.00 ELSE 1.50 END AS score_spread_pct
    FROM assigned a
    JOIN prod_bounds pb ON a.h_prod >= pb.cum_lo AND a.h_prod < pb.cum_hi),
sized AS (
    SELECT j.*,
        ROUND((j.ticket_min_inr + (j.h_tick/1000.0)*(j.ticket_max_inr - j.ticket_min_inr))/1000)*1000 AS sanction_amount_inr,
        j.tenor_min_months + FLOOR((j.h_ten/1000.0)*(j.tenor_max_months - j.tenor_min_months + 1)) AS tenor_months,
        j.base_roi_pct + j.score_spread_pct AS roi_pct
    FROM joined j),
priced AS (
    SELECT s.*, s.roi_pct/1200.0 AS r_monthly,
        LEAST(FLOOR((s.h_elap/1000.0)*s.tenor_months), s.tenor_months - 1) AS months_elapsed
    FROM sized s),
emi AS (
    SELECT p.*, ROUND(p.sanction_amount_inr*p.r_monthly*POWER(1+p.r_monthly,p.tenor_months)
              /(POWER(1+p.r_monthly,p.tenor_months)-1),0) AS emi_amount_inr
    FROM priced p),
dpd AS (
    SELECT e.*,
        /* CLAMPED: a loan cannot be more delinquent than it is old. Without
           this, DPD and months_elapsed were drawn from independent hash
           buckets and ~2.5pct of the book showed impossible states (e.g.
           12 unpaid EMIs on a loan disbursed this month). */
        LEAST(
          CASE WHEN e.h_stress < e.target_gnpa_pct*100 THEN 91 + (e.h_dpdv % 270)
               WHEN e.h_stress < e.target_gnpa_pct*200 THEN 31 + (e.h_dpdv % 60)
               WHEN e.h_stress < e.target_gnpa_pct*500 THEN  1 + (e.h_dpdv % 30)
               ELSE 0 END,
          e.months_elapsed * 30
        ) AS current_dpd
    FROM emi e)
SELECT ''LN'' || LPAD(ROW_NUMBER() OVER (ORDER BY borrower_id, seq), 7, ''0'') AS loan_id,
    borrower_id, product_code, product_name, is_secured, sanction_amount_inr,
    sanction_amount_inr AS disbursed_amount_inr, roi_pct, bank_benchmark_roi_pct,
    ROUND(roi_pct - bank_benchmark_roi_pct, 3) AS rate_gap_vs_bank_pct,
    CASE WHEN (product_code IN (''MSME'',''LAP'') AND h_rt<50) OR (product_code NOT IN (''MSME'',''LAP'') AND h_rt<15) THEN ''FLOATING'' ELSE ''FIXED'' END AS rate_type,
    CASE WHEN (product_code IN (''MSME'',''LAP'') AND h_rt<50) OR (product_code NOT IN (''MSME'',''LAP'') AND h_rt<15) THEN TRUE ELSE FALSE END AS is_repo_linked,
    tenor_months, emi_amount_inr,
    DATEADD(month, -months_elapsed, CURRENT_DATE())::DATE AS disbursal_date,
    DATEADD(month, tenor_months - months_elapsed, CURRENT_DATE())::DATE AS maturity_date,
    months_elapsed, tenor_months - months_elapsed AS residual_months,
    GREATEST(ROUND(sanction_amount_inr*POWER(1+r_monthly,months_elapsed)
             - emi_amount_inr*(POWER(1+r_monthly,months_elapsed)-1)/r_monthly,0),0) AS outstanding_principal_inr,
    current_dpd, CEIL(current_dpd/30.0) AS unpaid_emi_count,
    CASE WHEN current_dpd >= 90 AND h_clear < 12 THEN 0
         WHEN current_dpd >= 90 AND h_clear < 35 THEN ROUND(CEIL(current_dpd/30.0)*emi_amount_inr * (0.2 + MOD(h_clear,23)/100.0), 0)
         ELSE ROUND(CEIL(current_dpd/30.0)*emi_amount_inr, 0) END AS arrears_amount_inr,
    CASE WHEN h_chan<30 THEN ''DEALER'' WHEN h_chan<55 THEN ''DSA'' WHEN h_chan<80 THEN ''DIGITAL'' ELSE ''BRANCH'' END AS sourcing_channel,
    CASE WHEN h_nach < nach_mandate_share_pct THEN TRUE ELSE FALSE END AS has_nach_mandate,
    TRUE AS is_active
FROM dpd;

DELETE FROM BORROWER360.CURATED.LOAN_ACCOUNT
WHERE borrower_id IN (''BRW000001'',''BRW000002'')
  AND loan_id NOT IN (SELECT MIN(loan_id) FROM BORROWER360.CURATED.LOAN_ACCOUNT
                      WHERE borrower_id IN (''BRW000001'',''BRW000002'') GROUP BY borrower_id);

UPDATE BORROWER360.CURATED.LOAN_ACCOUNT
SET product_code=''PL'', product_name=''Personal loan (small ticket)'', is_secured=FALSE,
    sanction_amount_inr=200000, disbursed_amount_inr=200000,
    roi_pct=15.50, bank_benchmark_roi_pct=12.50, rate_gap_vs_bank_pct=3.00,
    rate_type=''FLOATING'', is_repo_linked=TRUE,
    tenor_months=24, months_elapsed=10, residual_months=14,
    emi_amount_inr = ROUND(200000*(15.50/1200)*POWER(1+15.50/1200,24)/(POWER(1+15.50/1200,24)-1),0),
    outstanding_principal_inr = ROUND(200000*POWER(1+15.50/1200,10)
        - ROUND(200000*(15.50/1200)*POWER(1+15.50/1200,24)/(POWER(1+15.50/1200,24)-1),0)*(POWER(1+15.50/1200,10)-1)/(15.50/1200),0),
    disbursal_date = DATEADD(month,-10,CURRENT_DATE()), maturity_date = DATEADD(month,14,CURRENT_DATE()),
    current_dpd=0, unpaid_emi_count=0, arrears_amount_inr=0, has_nach_mandate=TRUE, is_active=TRUE
WHERE borrower_id=''BRW000001'';

UPDATE BORROWER360.CURATED.LOAN_ACCOUNT
SET product_code=''LAP'', product_name=''Loan against property'', is_secured=TRUE,
    sanction_amount_inr=1200000, disbursed_amount_inr=1200000,
    roi_pct=12.50, bank_benchmark_roi_pct=11.00, rate_gap_vs_bank_pct=1.50,
    rate_type=''FLOATING'', is_repo_linked=TRUE,
    tenor_months=84, months_elapsed=12, residual_months=72,
    emi_amount_inr = ROUND(1200000*(12.50/1200)*POWER(1+12.50/1200,84)/(POWER(1+12.50/1200,84)-1),0),
    outstanding_principal_inr = ROUND(1200000*POWER(1+12.50/1200,12)
        - ROUND(1200000*(12.50/1200)*POWER(1+12.50/1200,84)/(POWER(1+12.50/1200,84)-1),0)*(POWER(1+12.50/1200,12)-1)/(12.50/1200),0),
    disbursal_date = DATEADD(month,-12,CURRENT_DATE()), maturity_date = DATEADD(month,72,CURRENT_DATE()),
    current_dpd=0, unpaid_emi_count=0, arrears_amount_inr=0, has_nach_mandate=TRUE, is_active=TRUE
WHERE borrower_id=''BRW000002'';

UPDATE BORROWER360.CURATED.BORROWER SET is_demo_case=TRUE,
    demo_case_label=''DEMO: BT_NOT_RATIONAL_SHORT_TENOR - competitor rate gap (3.0pp) exists but residual tenor (14mo) is below the PL switching-cost threshold (18mo). Correct action: BT_LET_GO, protect margin.''
 WHERE borrower_id=''BRW000001'';
UPDATE BORROWER360.CURATED.BORROWER SET is_demo_case=TRUE,
    demo_case_label=''DEMO: BT_RATIONAL_LONG_TENOR - LAP with 72mo residual, gap 1.5pp >= threshold. Retention counter-offer is economically justified.''
 WHERE borrower_id=''BRW000002'';

CREATE OR REPLACE TABLE BORROWER360.CURATED.MANDATE AS
WITH l AS (
    SELECT loan_id, borrower_id, product_code, current_dpd, emi_amount_inr, disbursal_date,
           ABS(HASH(loan_id,''mstat'')) % 1000 AS h_stat, ABS(HASH(loan_id,''mrsn'')) % 100 AS h_rsn,
           ABS(HASH(loan_id,''mbank'')) % 12 AS h_bank, ABS(HASH(loan_id,''mfail'')) % 60 AS h_fail,
           ABS(HASH(loan_id,''mcons'')) % 100 AS h_cons, ABS(HASH(loan_id,''mtype'')) % 100 AS h_type
    FROM BORROWER360.CURATED.LOAN_ACCOUNT WHERE has_nach_mandate = TRUE AND borrower_id NOT IN (''BRW000001'',''BRW000002'')),
banks AS (SELECT ARRAY_CONSTRUCT(''State Bank of India'',''HDFC Bank'',''ICICI Bank'',''Axis Bank'',''Bank of Baroda'',
    ''Punjab National Bank'',''Kotak Mahindra Bank'',''Canara Bank'',''Union Bank of India'',''IndusInd Bank'',
    ''Bank of Maharashtra'',''Federal Bank'') AS bl),
classified AS (
    SELECT l.*, CASE
        WHEN l.current_dpd = 0 AND l.h_stat < 70 THEN ''FAILED_DPD_ZERO''
        WHEN l.current_dpd = 0 THEN ''ACTIVE''
        WHEN l.current_dpd BETWEEN 1 AND 60 AND l.h_stat < 820 THEN ''FAILED_ACTIVE_ARREARS''
        WHEN l.current_dpd > 60 AND l.h_stat < 700 THEN ''REVOKED''
        WHEN l.current_dpd > 60 THEN ''FAILED_ACTIVE_ARREARS''
        ELSE ''ACTIVE'' END AS mandate_status
    FROM l)
SELECT ''MND'' || LPAD(ROW_NUMBER() OVER (ORDER BY c.loan_id),7,''0'') AS mandate_id,
    c.loan_id, c.borrower_id,
    CASE WHEN c.h_type < 78 THEN ''NACH_DEBIT'' ELSE ''UPI_AUTOPAY'' END AS mandate_type,
    GET(b.bl, c.h_bank)::STRING AS sponsor_bank,
    DATEADD(day,-3,c.disbursal_date)::DATE AS registration_date, c.mandate_status,
    CASE c.mandate_status WHEN ''ACTIVE'' THEN NULL
        WHEN ''FAILED_DPD_ZERO'' THEN CASE WHEN c.h_rsn<45 THEN ''MANDATE_NOT_REGISTERED''
             WHEN c.h_rsn<78 THEN ''TECHNICAL_DECLINE'' ELSE ''PAYER_ACCOUNT_INOPERATIVE'' END
        WHEN ''FAILED_ACTIVE_ARREARS'' THEN CASE WHEN c.h_rsn<82 THEN ''INSUFFICIENT_FUNDS''
             WHEN c.h_rsn<92 THEN ''ACCOUNT_CLOSED'' ELSE ''TECHNICAL_DECLINE'' END
        WHEN ''REVOKED'' THEN ''MANDATE_REVOKED_BY_CUSTOMER'' END AS last_failure_reason,
    CASE c.mandate_status WHEN ''ACTIVE'' THEN NULL ELSE DATEADD(day,-c.h_fail,CURRENT_DATE())::DATE END AS last_failure_date,
    CASE c.mandate_status WHEN ''ACTIVE'' THEN 0 WHEN ''FAILED_DPD_ZERO'' THEN 1
        WHEN ''FAILED_ACTIVE_ARREARS'' THEN 1 + (c.h_cons % 4) WHEN ''REVOKED'' THEN 1 + (c.h_cons % 3) END AS consecutive_failures,
    CASE WHEN c.mandate_status=''ACTIVE'' THEN ''NONE'' WHEN c.mandate_status=''FAILED_DPD_ZERO'' THEN ''TECHNICAL''
         WHEN c.mandate_status=''REVOKED'' THEN ''INTENT'' ELSE ''CAPACITY'' END AS failure_attribution,
    (c.mandate_status=''FAILED_DPD_ZERO'') AS is_early_warning
FROM classified c CROSS JOIN banks b
UNION ALL
SELECT ''MND'' || LPAD(9000000 + ROW_NUMBER() OVER (ORDER BY borrower_id), 7, ''0''), la.loan_id, la.borrower_id,
    ''NACH_DEBIT'', ''HDFC Bank'', DATEADD(day,-3,la.disbursal_date)::DATE, ''ACTIVE'',
    NULL, NULL, 0, ''NONE'', FALSE
FROM BORROWER360.CURATED.LOAN_ACCOUNT la WHERE la.borrower_id IN (''BRW000001'',''BRW000002'');

CREATE OR REPLACE TABLE BORROWER360.CURATED.BORROWER_STATE AS
WITH own AS (
    SELECT borrower_id, COUNT(*) AS own_loan_count, COUNT(DISTINCT product_code) AS own_product_count,
           SUM(outstanding_principal_inr) AS total_outstanding_inr, SUM(arrears_amount_inr) AS total_arrears_inr,
           SUM(emi_amount_inr) AS own_emi_inr, MAX(current_dpd) AS max_dpd_own,
           MIN(residual_months) AS min_residual_months, MAX(residual_months) AS max_residual_months,
           MAX(rate_gap_vs_bank_pct) AS max_rate_gap_vs_bank_pct
    FROM BORROWER360.CURATED.LOAN_ACCOUNT WHERE is_active GROUP BY borrower_id),
ext AS (
    SELECT borrower_id, COUNT(*) AS external_tradeline_count, COUNT(DISTINCT lender_name) AS external_lender_count,
           SUM(current_balance_inr) AS external_balance_inr, SUM(emi_amount_inr) AS external_emi_inr,
           MAX(current_dpd) AS external_max_dpd, COUNT_IF(lender_type=''FINTECH'') AS fintech_tradelines,
           COUNT_IF(lender_type=''MFI'') AS mfi_tradelines
    FROM BORROWER360.CURATED.BUREAU_TRADELINE WHERE tradeline_status=''ACTIVE''
      AND borrower_id NOT IN (''BRW000001'',''BRW000002'') GROUP BY borrower_id),
mnd AS (
    SELECT borrower_id, COUNT_IF(is_early_warning) AS early_warning_mandates,
           COUNT_IF(failure_attribution=''TECHNICAL'') AS technical_failures,
           COUNT_IF(failure_attribution=''CAPACITY'') AS capacity_failures,
           COUNT_IF(failure_attribution=''INTENT'') AS intent_failures
    FROM BORROWER360.CURATED.MANDATE GROUP BY borrower_id)
SELECT b.borrower_id, b.full_name, b.city, b.state, b.city_tier, b.primary_language,
    b.occupation_type, b.monthly_income_inr, b.bureau_score, b.bureau_score_band,
    o.own_loan_count, o.own_product_count, o.total_outstanding_inr, o.total_arrears_inr, o.own_emi_inr,
    o.max_dpd_own, o.min_residual_months, o.max_residual_months, o.max_rate_gap_vs_bank_pct,
    CASE WHEN o.max_dpd_own > 90 THEN ''NPA'' WHEN o.max_dpd_own > 60 THEN ''SMA-2''
         WHEN o.max_dpd_own > 30 THEN ''SMA-1'' WHEN o.max_dpd_own >= 1 THEN ''SMA-0''
         ELSE ''STANDARD'' END AS borrower_asset_class,
    (o.max_dpd_own >= 90) AS is_npa,
    CASE WHEN o.max_dpd_own >= 90 AND COALESCE(o.total_arrears_inr,0) = 0 THEN TRUE ELSE FALSE END AS npa_upgrade_eligible,
    CASE WHEN o.max_dpd_own >= 90 THEN o.total_arrears_inr ELSE 0 END AS arrears_to_clear_for_upgrade_inr,
    CASE WHEN o.max_dpd_own >= 90 THEN (SELECT COUNT(*) FROM BORROWER360.CURATED.LOAN_ACCOUNT la
         WHERE la.borrower_id = b.borrower_id AND la.current_dpd < 90 AND la.is_active) ELSE 0 END AS performing_loans_dragged_to_npa,
    COALESCE(e.external_tradeline_count,0) AS external_tradeline_count,
    COALESCE(e.external_lender_count,0) AS external_lender_count,
    1 + COALESCE(e.external_lender_count,0) AS total_lender_count,
    CASE WHEN 1 + COALESCE(e.external_lender_count,0) >= (SELECT param_value FROM BORROWER360.UTIL.CONFIG_ECONOMIC_ASSUMPTION
         WHERE param_key=''loan_stacking_lender_threshold'') THEN TRUE ELSE FALSE END AS is_loan_stacked,
    COALESCE(e.external_balance_inr,0) AS external_balance_inr,
    COALESCE(e.external_emi_inr,0) AS external_emi_inr,
    COALESCE(e.external_max_dpd,0) AS external_max_dpd,
    COALESCE(e.fintech_tradelines,0) AS fintech_tradelines,
    COALESCE(e.mfi_tradelines,0) AS mfi_tradelines,
    o.own_emi_inr + COALESCE(e.external_emi_inr,0) AS total_emi_inr,
    ROUND(100.0*o.own_emi_inr/NULLIF(b.monthly_income_inr,0),1) AS foir_own_book_pct,
    ROUND(100.0*(o.own_emi_inr + COALESCE(e.external_emi_inr,0))/NULLIF(b.monthly_income_inr,0),1) AS foir_true_pct,
    COALESCE(m.early_warning_mandates,0) AS early_warning_mandates,
    COALESCE(m.technical_failures,0) AS technical_mandate_failures,
    COALESCE(m.capacity_failures,0) AS capacity_mandate_failures,
    COALESCE(m.intent_failures,0) AS intent_mandate_failures,
    CASE WHEN COALESCE(m.early_warning_mandates,0) > 0 AND o.max_dpd_own = 0 THEN TRUE ELSE FALSE END AS is_pre_delinquent_warning,
    b.is_demo_case, b.demo_case_label
FROM BORROWER360.CURATED.BORROWER b
JOIN own o ON o.borrower_id = b.borrower_id
LEFT JOIN ext e ON e.borrower_id = b.borrower_id
LEFT JOIN mnd m ON m.borrower_id = b.borrower_id;

RETURN ''spine rebuilt with DPD clamped to months_elapsed'';
END;
';
