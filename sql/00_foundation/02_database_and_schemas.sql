/* =====================================================================
   BORROWER360 | Phase 1 | 02_database_and_schemas.sql
   ---------------------------------------------------------------------
   Purpose : Create the project database and layered schemas.
   Safe to re-run: yes (IF NOT EXISTS throughout - deliberately NOT
   "CREATE OR REPLACE DATABASE", which would silently destroy data on
   a re-run once tables exist).

   Layering rationale:
     RAW       Generated / landed data, never edited in place.
     CURATED   Conformed, typed, business-keyed entities. The 360 spine.
     AI        LLM-derived enrichment. Kept separate so AI output is
               never confused with source-of-truth facts, and so it can
               be dropped and rebuilt without touching CURATED.
     SEMANTIC  Semantic views + Cortex Analyst / Agent surface.
     APP       Streamlit app objects.
     UTIL      Ops: cost tracking, run logs, evaluation ground truth.

   Cost note: DATA_RETENTION_TIME_IN_DAYS = 1 (the minimum) on every
   schema. Time Travel on ~150k synthetic rows is not worth storage
   spend on a 10-day trial budget.
   ===================================================================== */

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE COMPUTE_WH;

CREATE DATABASE IF NOT EXISTS BORROWER360
    DATA_RETENTION_TIME_IN_DAYS = 1
    COMMENT = 'Unified borrower 360 + next-best-action. Indian retail lending (mixed NBFC). Snowflake CoCo Hackathon GCC, Track 2 FSI.';

USE DATABASE BORROWER360;

CREATE SCHEMA IF NOT EXISTS RAW
    DATA_RETENTION_TIME_IN_DAYS = 1
    COMMENT = 'Landing zone. Generated structured spine + raw transcripts. Append-only in spirit.';

CREATE SCHEMA IF NOT EXISTS CURATED
    DATA_RETENTION_TIME_IN_DAYS = 1
    COMMENT = 'Conformed entities: borrower, loan, schedule, payments, monthly DPD snapshots, interactions.';

CREATE SCHEMA IF NOT EXISTS AI
    DATA_RETENTION_TIME_IN_DAYS = 1
    COMMENT = 'LLM-derived enrichment: transcript insights, features, NBA recommendations. Rebuildable.';

CREATE SCHEMA IF NOT EXISTS SEMANTIC
    DATA_RETENTION_TIME_IN_DAYS = 1
    COMMENT = 'Semantic views and Cortex Analyst / Agent surface.';

CREATE SCHEMA IF NOT EXISTS APP
    DATA_RETENTION_TIME_IN_DAYS = 1
    COMMENT = 'Streamlit in Snowflake app objects and stages.';

CREATE SCHEMA IF NOT EXISTS UTIL
    DATA_RETENTION_TIME_IN_DAYS = 1
    COMMENT = 'Ops: cost tracking views, generation run log, held-out evaluation ground truth.';

-- Drop the default PUBLIC schema to keep the namespace honest.
DROP SCHEMA IF EXISTS PUBLIC;

-- ---------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------
SHOW SCHEMAS IN DATABASE BORROWER360;
