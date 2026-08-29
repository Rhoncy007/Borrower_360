"""
Access control proof: connect as BORROWER360_ENRICHMENT_SVC (a real, separate
authenticated session - not a USE ROLE switch inside a shared connection) and
attempt to read UTIL.GROUND_TRUTH_HIDDEN. Captures actual success/failure and
error text as evidence, not just grant-table inspection.
"""
import snowflake.connector
import json
from datetime import datetime, timezone

ACCOUNT = "xm85110.ap-southeast-7.aws"
USER = "BORROWER360_ENRICHMENT_SVC"
PASSWORD = "Br360_Enrch_Svc_9247_Kx!"
ROLE = "BORROWER360_ENRICHMENT_ROLE"
WAREHOUSE = "COMPUTE_WH"
DATABASE = "BORROWER360"

QUERIES = [
    ("Q1_count_hidden_labels", "SELECT COUNT(*) FROM UTIL.GROUND_TRUTH_HIDDEN"),
    ("Q2_select_star_hidden", "SELECT * FROM UTIL.GROUND_TRUTH_HIDDEN LIMIT 1"),
    ("Q3_show_tables_util", "SHOW TABLES IN SCHEMA UTIL"),
    ("Q4_cross_schema_join", """SELECT c.interaction_id, g.ground_truth_label
        FROM CURATED.CALL_TRANSCRIPT c
        JOIN UTIL.GROUND_TRUTH_HIDDEN g USING (interaction_id) LIMIT 1"""),
    ("Q0_control_can_read_transcripts", "SELECT COUNT(*) FROM CURATED.CALL_TRANSCRIPT"),
]

results = []
conn = snowflake.connector.connect(
    account=ACCOUNT, user=USER, password=PASSWORD,
    role=ROLE, warehouse=WAREHOUSE, database=DATABASE,
)
cur = conn.cursor()

# Confirm identity of this session before running anything else
cur.execute("SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_ACCOUNT()")
identity = cur.fetchone()
print(f"CONNECTED AS: user={identity[0]} role={identity[1]} account={identity[2]}")

for name, sql in QUERIES:
    entry = {"query_name": name, "sql": sql.strip()}
    try:
        cur.execute(sql)
        rows = cur.fetchall()
        entry["outcome"] = "SUCCEEDED"
        entry["row_sample"] = str(rows[:3])
        print(f"[{name}] SUCCEEDED - rows: {rows[:3]}")
    except snowflake.connector.errors.ProgrammingError as e:
        entry["outcome"] = "DENIED"
        entry["error_code"] = getattr(e, "errno", None)
        entry["error_text"] = str(e)
        print(f"[{name}] DENIED - {e}")
    except Exception as e:
        entry["outcome"] = "ERROR_OTHER"
        entry["error_text"] = str(e)
        print(f"[{name}] ERROR - {e}")
    results.append(entry)

cur.close()
conn.close()

output = {
    "test_run_at": datetime.now(timezone.utc).isoformat(),
    "connected_as_user": identity[0],
    "connected_as_role": identity[1],
    "account": identity[2],
    "results": results,
}
with open(r"C:\Users\rakes\borrower360\evidence\access_control_proof.json", "w") as f:
    json.dump(output, f, indent=2)
print("\nSaved to evidence/access_control_proof.json")
