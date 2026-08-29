import json
import streamlit as st
import pandas as pd
import altair as alt
import snowflake.connector
import requests

st.set_page_config(page_title="Borrower 360 - Arthaa Finance (Public Demo)", layout="wide")

# --- Connection -------------------------------------------------------------
# Reads credentials from Streamlit secrets (st.secrets), configured in the
# Streamlit Community Cloud app settings - never hardcoded here.
# Required keys in secrets.toml:
#   [snowflake]
#   account   = "NX75692"
#   user      = "BORROWER360_DEMO_USER"
#   password  = "..."           # the BORROWER360_DEMO_ROLE demo user password
#   role      = "BORROWER360_DEMO_ROLE"
#   warehouse = "COMPUTE_WH"
#   database  = "BORROWER360"
#   schema    = "CURATED"


@st.cache_resource
def get_connection():
    cfg = st.secrets["snowflake"]
    return snowflake.connector.connect(
        account=cfg["account"],
        user=cfg["user"],
        password=cfg["password"],
        role=cfg["role"],
        warehouse=cfg["warehouse"],
        database=cfg["database"],
        schema=cfg["schema"],
    )


def run(sql, params=None):
    conn = get_connection()
    cur = conn.cursor()
    try:
        cur.execute(sql, params)
        cols = [c[0] for c in cur.description]
        return pd.DataFrame(cur.fetchall(), columns=cols)
    finally:
        cur.close()


# --- Cortex Analyst (read-only Q&A over the semantic view) -----------------
# This demo deliberately does NOT expose DecideRecommendation (approve/reject)
# or CreateTeamTasks - the public demo user has no grant on those procedures,
# so any attempt to invoke them will fail closed at the database, not just in
# the UI.
ANALYST_API_PATH = "/api/v2/cortex/analyst/message"


def call_analyst(question):
    """Calls Cortex Analyst's REST endpoint directly (public REST call, not the
    Snowflake-native _snowflake.send_snow_api_request used inside Streamlit-in-
    Snowflake). Requires a PAT stored in st.secrets['snowflake']['pat']."""
    cfg = st.secrets["snowflake"]
    host = f"https://{cfg['account']}.snowflakecomputing.com"
    url = f"{host}{ANALYST_API_PATH}"
    body = {
        "messages": [{"role": "user", "content": [{"type": "text", "text": question}]}],
        "semantic_view": f"{cfg['database']}.SEMANTIC.BORROWER_360_MODEL",
    }
    headers = {
        "Authorization": f"Bearer {cfg['pat']}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    resp = requests.post(url, headers=headers, json=body, timeout=60)
    if resp.status_code != 200:
        return f"Analyst call failed (status {resp.status_code}): {resp.text}", None
    data = resp.json()
    sql_text, text_reply = None, None
    for item in data.get("message", {}).get("content", []):
        if item.get("type") == "text":
            text_reply = item.get("text")
        if item.get("type") == "sql":
            sql_text = item.get("statement")
    return text_reply, sql_text


# --- UI ----------------------------------------------------------------------
st.title("Borrower 360 - Public Demo (Read-Only)")
st.caption(
    "Public demo build. Connects with a dedicated read-only Snowflake role "
    "(BORROWER360_DEMO_ROLE) - no approve/reject or team-task actions are "
    "available here. Use the Snowflake-hosted app for the full experience."
)

tab_overview, tab_lookup, tab_ask = st.tabs(["Portfolio Overview", "Borrower Lookup", "Ask (Cortex Analyst)"])

with tab_overview:
    st.subheader("Portfolio by RBI asset classification")
    df = run(
        "SELECT BORROWER_ASSET_CLASS, COUNT(*) AS BORROWERS "
        "FROM BORROWER360.CURATED.BORROWER_360 GROUP BY BORROWER_ASSET_CLASS"
    )
    if not df.empty:
        chart = alt.Chart(df).mark_bar().encode(x="BORROWER_ASSET_CLASS", y="BORROWERS")
        st.altair_chart(chart, use_container_width=True)
        st.dataframe(df, use_container_width=True)

    st.subheader("Balance-transfer flight risk vs lifetime value")
    df2 = run(
        "SELECT BORROWER_ID, FULL_NAME, LTV_EXPECTED_INTEREST_INR, BT_RISK_SCORE "
        "FROM BORROWER360.CURATED.BORROWER_360 WHERE BT_IS_A_FLIGHT_RISK = TRUE "
        "ORDER BY LTV_EXPECTED_INTEREST_INR DESC LIMIT 20"
    )
    st.dataframe(df2, use_container_width=True)

with tab_lookup:
    borrower_id = st.text_input("Borrower ID", placeholder="e.g. BRW002563")
    if borrower_id:
        b = run(
            "SELECT * FROM BORROWER360.CURATED.BORROWER_360 WHERE BORROWER_ID = %(bid)s",
            {"bid": borrower_id},
        )
        if b.empty:
            st.warning("No borrower found with that ID.")
        else:
            st.dataframe(b, use_container_width=True)
            recs = run(
                "SELECT ACTION_CODE, RULE_BASIS, MODEL_CONTRIBUTION, EXPECTED_VALUE_INR, STATUS "
                "FROM BORROWER360.AI.NBA_RECOMMENDATION WHERE BORROWER_ID = %(bid)s "
                "ORDER BY CREATED_AT DESC",
                {"bid": borrower_id},
            )
            st.subheader("Pending / historical NBA recommendations")
            st.dataframe(recs, use_container_width=True)

with tab_ask:
    st.caption("Ask a question in plain English. Answered via Cortex Analyst over BORROWER_360_MODEL.")
    q = st.text_input("Question", placeholder="Which borrowers are at highest risk of balance transfer?")
    if st.button("Ask") and q:
        with st.spinner("Querying Cortex Analyst..."):
            text_reply, sql_text = call_analyst(q)
        if text_reply:
            st.write(text_reply)
        if sql_text:
            st.code(sql_text, language="sql")
            try:
                st.dataframe(run(sql_text), use_container_width=True)
            except Exception as e:
                st.error(f"Could not execute generated SQL: {e}")
