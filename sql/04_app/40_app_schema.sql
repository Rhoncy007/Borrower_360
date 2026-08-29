-- BORROWER360.APP schema: Streamlit app, team-task queue, MCP-wrapped procedure.
-- Extracted via GET_DDL('SCHEMA','BORROWER360.APP') on 2026-08-29.

create or replace schema APP COMMENT='Streamlit in Snowflake app objects and stages.';

create or replace TABLE TEAM_TASK_QUEUE (
	TASK_ID VARCHAR(16777216) NOT NULL,
	RECOMMENDATION_ID VARCHAR(16777216) NOT NULL,
	BORROWER_ID VARCHAR(16777216) NOT NULL,
	ACTION_CODE VARCHAR(16777216) NOT NULL,
	OWNING_TEAM VARCHAR(16777216) NOT NULL,
	STATUS VARCHAR(16777216) NOT NULL,
	CREATED_AT TIMESTAMP_NTZ(9) NOT NULL,
	FPC_WINDOW_OK BOOLEAN NOT NULL,
	CONFIRMED_AT TIMESTAMP_NTZ(9),
	constraint UQ_RECOMMENDATION unique (RECOMMENDATION_ID)
)COMMENT='Internal task queue for approved NBA recommendations, routed by owning team. No external ticketing system is reachable on this trial account (no EAI). Reads ONLY status=APPROVED rows from NBA_RECOMMENDATION; enforces the RBI FPC 08:00-19:00 IST contact window in SQL, not a prompt; idempotent via the unique constraint on recommendation_id (MERGE, not INSERT).'
;

CREATE OR REPLACE PROCEDURE "SP_CREATE_TEAM_TASKS"()
RETURNS VARCHAR
LANGUAGE SQL
COMMENT='Reads ONLY status=APPROVED rows from NBA_RECOMMENDATION and creates/updates a row in TEAM_TASK_QUEUE for each, routed to the owning team by action_family. Enforces the RBI FPC 08:00-19:00 IST contact window in SQL - outside the window, the task is still created but flagged fpc_window_ok=FALSE so the owning team knows not to actually contact the borrower until the window reopens; this is never decided by a prompt. Idempotent via MERGE keyed on recommendation_id - re-running does not create duplicate tasks. Writes back confirmed_at once the task exists.'
EXECUTE AS OWNER
AS '
DECLARE
    v_hour_ist INTEGER;
    v_in_window BOOLEAN;
BEGIN
    v_hour_ist := HOUR(CONVERT_TIMEZONE(''Asia/Kolkata'', CURRENT_TIMESTAMP()));
    v_in_window := (v_hour_ist >= 8 AND v_hour_ist < 19);

    MERGE INTO BORROWER360.APP.TEAM_TASK_QUEUE t
    USING (
        SELECT recommendation_id, borrower_id, action_code, action_family,
            CASE action_family
                WHEN ''COLLECTIONS'' THEN ''Collections Team''
                WHEN ''RETENTION'' THEN ''Retention Desk''
                WHEN ''GROWTH'' THEN ''Relationship & Growth Team''
                WHEN ''SERVICE'' THEN ''Servicing Operations''
                ELSE ''General Queue''
            END AS owning_team
        FROM BORROWER360.AI.NBA_RECOMMENDATION
        WHERE status = ''APPROVED''
    ) s
    ON t.recommendation_id = s.recommendation_id
    WHEN NOT MATCHED THEN INSERT (task_id, recommendation_id, borrower_id, action_code, owning_team,
        status, created_at, fpc_window_ok, confirmed_at)
        VALUES (UUID_STRING(), s.recommendation_id, s.borrower_id, s.action_code, s.owning_team,
            ''QUEUED'', CURRENT_TIMESTAMP(), :v_in_window, CURRENT_TIMESTAMP());

    RETURN ''Team tasks created for approved recommendations (FPC window check: '' ||
        CASE WHEN v_in_window THEN ''within window'' ELSE ''outside window - flagged, not actioned yet'' END || '').'';
END;
';

create or replace streamlit BORROWER_360_APP
	main_file='streamlit_app.py'
	query_warehouse='COMPUTE_WH';

-- MCP_TEAM_TASKS: native MCP server wrapping SP_CREATE_TEAM_TASKS.
-- Re-create with (uncomment and run once the APP schema objects above exist):
-- CREATE OR REPLACE MCP SERVER MCP_TEAM_TASKS
--   FROM SPECIFICATION $$
--     tools:
--       - name: create_team_tasks
--         type: procedure
--         identifier: BORROWER360.APP.SP_CREATE_TEAM_TASKS
--   $$;
