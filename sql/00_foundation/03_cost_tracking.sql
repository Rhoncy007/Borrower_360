/* =====================================================================
   BORROWER360 | Phase 1 | 03_cost_tracking.sql
   ---------------------------------------------------------------------
   Purpose : Make every dollar visible, in USD, by category and by day.
   Safe to re-run: yes (CREATE OR REPLACE VIEW).

   WHY THIS EXISTS:
     Resource monitors cap warehouse credits only. They do NOT see
     AI Credits (Cortex inference) or Cortex Code agent usage. On this
     project the agent conversation turned out to be the single largest
     cost line - far larger than warehouse or AI functions - so it must
     be tracked explicitly or it is invisible until the budget is gone.

   RATES (Snowflake Service Consumption Table, effective 2026-08-18):
     Platform Credit, AWS Asia Pacific (Thailand), Enterprise  $3.60
     AI Credit, on demand regional (conservative)              $2.20
     Cortex Code (per account rate sheet)                      $2.00

   CAVEAT ON LATENCY:
     ACCOUNT_USAGE views lag (typically minutes to a few hours).
     ORGANIZATION_USAGE.REMAINING_BALANCE_DAILY lags by up to a day and
     during testing was materially stale, so we derive spend from
     metering rather than trusting the balance snapshot.
   ===================================================================== */

USE ROLE ACCOUNTADMIN;
USE DATABASE BORROWER360;
USE SCHEMA UTIL;

-- ---------------------------------------------------------------------
-- Rate lookup, kept in one place so a price change is a one-line edit.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_CREDIT_RATES AS
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

-- ---------------------------------------------------------------------
-- Daily spend, all categories, in credits and USD.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_SPEND_DAILY AS
SELECT
    m.usage_date,
    m.service_type,
    COALESCE(r.rate_note, 'unmapped service type - rate assumed 2.20') AS rate_note,
    ROUND(m.credits_used, 6)                                  AS credits,
    COALESCE(r.usd_per_credit, 2.20)                           AS usd_per_credit,
    ROUND(m.credits_used * COALESCE(r.usd_per_credit, 2.20), 4) AS usd
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY m
LEFT JOIN V_CREDIT_RATES r
       ON r.service_type = m.service_type
WHERE m.credits_used > 0;

-- ---------------------------------------------------------------------
-- Headline position: spent, remaining, and burn rate.
-- Trial free-usage balance is hardcoded at 400.00 (USD) because the
-- balance view lags; spend is derived, which is the trustworthy side.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_SPEND_SUMMARY AS
WITH agg AS (
    SELECT
        SUM(usd)                                        AS total_usd,
        MIN(usage_date)                                 AS first_day,
        MAX(usage_date)                                 AS last_day,
        COUNT(DISTINCT usage_date)                      AS active_days
    FROM V_SPEND_DAILY
)
SELECT
    400.00                                              AS trial_budget_usd,
    ROUND(total_usd, 2)                                 AS spent_usd,
    ROUND(400.00 - total_usd, 2)                        AS remaining_usd,
    ROUND(100.0 * total_usd / 400.00, 1)                AS pct_used,
    active_days,
    ROUND(total_usd / NULLIF(active_days, 0), 2)         AS usd_per_active_day
FROM agg;

-- ---------------------------------------------------------------------
-- Where the money actually goes, ranked. This is the view to check
-- before approving any expensive step.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_SPEND_BY_CATEGORY AS
SELECT
    service_type,
    rate_note,
    ROUND(SUM(credits), 4)                              AS credits,
    ROUND(SUM(usd), 2)                                  AS usd,
    ROUND(100.0 * SUM(usd) / SUM(SUM(usd)) OVER (), 1)  AS pct_of_spend
FROM V_SPEND_DAILY
GROUP BY service_type, rate_note
ORDER BY usd DESC;

-- ---------------------------------------------------------------------
-- Cortex AI function spend attributed by query tag, so BORROWER360
-- pipeline cost can be separated from ad-hoc exploration.
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW V_AI_SPEND_BY_TAG AS
SELECT
    COALESCE(NULLIF(query_tag, ''), '(untagged)')        AS query_tag,
    function_name,
    model_name,
    SUM(tokens)                                         AS tokens,
    ROUND(SUM(token_credits), 6)                        AS ai_credits,
    ROUND(SUM(token_credits) * 2.20, 4)                 AS usd
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AISQL_USAGE_HISTORY
GROUP BY 1, 2, 3
ORDER BY usd DESC;

-- ---------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------
SELECT * FROM V_SPEND_SUMMARY;
SELECT * FROM V_SPEND_BY_CATEGORY;
