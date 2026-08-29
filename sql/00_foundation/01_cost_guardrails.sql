/* =====================================================================
   BORROWER360 | Phase 1 | 01_cost_guardrails.sql
   ---------------------------------------------------------------------
   Purpose : Stop unattended spend before any data work begins.
   Safe to re-run: yes (CREATE OR REPLACE / IF EXISTS throughout).

   Context :
     Account   XM85110 (org KQLOEJP), Enterprise
     Region    AWS_AP_SOUTHEAST_7  = AWS Asia Pacific (Thailand)
     Rates     Platform Credit  $3.60  (Consumption Table 2a, Enterprise)
               AI Credit        $2.20  (Consumption Table 2b, regional)
     Budget    $400 trial free-usage balance, 10 days

   NOTE ON COVERAGE:
     Resource monitors track PLATFORM (warehouse) credits ONLY.
     They do NOT cap AI Credits (Cortex inference) or Cortex Code usage.
     Those are tracked by the views in 03_cost_tracking.sql instead.
   ===================================================================== */

USE ROLE ACCOUNTADMIN;

-- ---------------------------------------------------------------------
-- 1. Warehouse hygiene.
--    XSMALL, 60s auto-suspend, no query acceleration (QAS bills extra).
--    Explicitly re-asserted here so this script alone restores the
--    intended state on a fresh or drifted account.
-- ---------------------------------------------------------------------
ALTER WAREHOUSE IF EXISTS COMPUTE_WH SET
    WAREHOUSE_SIZE            = 'XSMALL'
    AUTO_SUSPEND              = 60
    AUTO_RESUME               = TRUE
    ENABLE_QUERY_ACCELERATION = FALSE
    STATEMENT_TIMEOUT_IN_SECONDS = 1800   -- 30 min: kills runaway queries
    COMMENT = 'BORROWER360 build warehouse. Do not resize.';

-- Suspend the warehouses we are not using, so nothing idles.
ALTER WAREHOUSE IF EXISTS SNOWFLAKE_LEARNING_WH SUSPEND;

-- ---------------------------------------------------------------------
-- 2. Resource monitor: hard backstop on warehouse credits.
--    Quota 50 credits/month = ~$180 at $3.60/credit.
--    Expected whole-project usage is 15-30 credits, so this should
--    never fire. It exists to catch a runaway loop, not normal work.
-- ---------------------------------------------------------------------
CREATE OR REPLACE RESOURCE MONITOR BORROWER360_RM
    WITH
        CREDIT_QUOTA    = 50
        FREQUENCY       = MONTHLY
        START_TIMESTAMP = IMMEDIATELY
    TRIGGERS
        ON 50  PERCENT DO NOTIFY
        ON 75  PERCENT DO NOTIFY
        ON 90  PERCENT DO NOTIFY
        ON 95  PERCENT DO SUSPEND
        ON 100 PERCENT DO SUSPEND_IMMEDIATE;

-- Re-assert assignment (CREATE OR REPLACE clears it).
ALTER WAREHOUSE IF EXISTS COMPUTE_WH SET RESOURCE_MONITOR = BORROWER360_RM;

-- ---------------------------------------------------------------------
-- 3. Session defaults for cost attribution.
--    Query tag lets us isolate this project's spend in QUERY_HISTORY
--    without paying for a second warehouse.
-- ---------------------------------------------------------------------
ALTER SESSION SET QUERY_TAG = 'BORROWER360';

-- ---------------------------------------------------------------------
-- 4. Verification
-- ---------------------------------------------------------------------
SHOW RESOURCE MONITORS LIKE 'BORROWER360_RM';
