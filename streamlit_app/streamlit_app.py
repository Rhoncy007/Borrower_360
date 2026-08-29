import json
import streamlit as st
import pandas as pd
import altair as alt
import _snowflake
from snowflake.snowpark.context import get_active_session

st.set_page_config(page_title="Borrower 360 - Arthaa Finance", layout="wide")

session = get_active_session()

def run(sql, params=None):
    return session.sql(sql, params=params).to_pandas()

AGENT_API_PATH = "/api/v2/databases/BORROWER360/schemas/SEMANTIC/agents/BORROWER_360_AGENT:run"

def call_agent(messages):
    """Call the Cortex Agent :run endpoint from inside Streamlit-in-Snowflake and
    return (text_reply, tables) parsed out of the SSE response body.
    tables is a list of (columns, rows) pulled from response.table events -
    this is how structured recommendation rows (action_code, rule_basis, etc.)
    come back, separate from the free-text reply.
    """
    body = {"messages": messages}
    resp = _snowflake.send_snow_api_request(
        "POST", AGENT_API_PATH, {}, {}, body, None, 60000,
    )
    text_parts, tables = [], []
    if resp.get("status") != 200:
        return f"Agent call failed (status {resp.get('status')}): {resp.get('content')}", []
    raw = resp.get("content", "")
    try:
        events = json.loads(raw) if isinstance(raw, str) else raw
    except json.JSONDecodeError:
        events = []
    if not isinstance(events, list):
        events = [events]
    delta_parts, full_text = [], None
    tool_events = []
    for event in events:
        if not isinstance(event, dict):
            continue
        kind = event.get("event")
        data = event.get("data", {})
        if kind == "response.text.delta":
            delta_parts.append(data.get("text", ""))
        elif kind == "response.text":
            full_text = data.get("text", "")
        elif kind == "response.table":
            result_set = data.get("result_set", {})
            cols = [c["name"] for c in result_set.get("resultSetMetaData", {}).get("rowType", [])]
            rows = result_set.get("data", [])
            if cols and rows:
                tables.append((cols, rows))
        elif kind in ("response.tool_use", "response.tool_result", "response.status", "error"):
            tool_events.append({"event": kind, "data": data})
    reply = (full_text if full_text is not None else "".join(delta_parts)).strip()
    if not reply and not tables:
        reply = (
            f"DEBUG - status={resp.get('status')} raw_len={len(raw)} "
            f"tool_events={json.dumps(tool_events)} raw_full={raw}"
        )
    return reply, tables

st.title("Borrower 360")
st.caption("Arthaa Finance | Indian mixed-NBFC retail lending | Track 2 FSI demo")

page = st.sidebar.radio(
    "View",
    ["Portfolio Overview", "Borrower Lookup", "NBA Action Queue", "Ask the Agent", "Demo: BT Risk Contrast"],
)

# ---------------------------------------------------------------------------
# PORTFOLIO OVERVIEW
# ---------------------------------------------------------------------------
if page == "Portfolio Overview":
    st.header("Portfolio Overview")

    dist = run("""
        SELECT borrower_asset_class, COUNT(*) AS n
        FROM BORROWER360.CURATED.BORROWER_360
        GROUP BY 1 ORDER BY 1
    """)
    gnpa = run("SELECT * FROM BORROWER360.UTIL.V_GNPA_BLEND_SUMMARY")
    bt = run("""
        SELECT
            COUNT_IF(bt_is_a_flight_risk) AS flight_risks,
            COUNT_IF(has_retention_offer) AS retention_offers,
            SUM(bt_retention_value_if_offered_inr) AS total_retention_value_inr,
            SUM(ltv_expected_interest_inr) AS total_ltv_inr
        FROM BORROWER360.CURATED.BORROWER_360
    """)

    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Blended GNPA", f"{gnpa['BLENDED_GNPA_VALUE_WEIGHTED_PCT'][0]}%",
              help=f"System benchmark: {gnpa['SYSTEM_BENCHMARK_PCT'][0]}%")
    c2.metric("Genuine BT flight risks", int(bt["FLIGHT_RISKS"][0]))
    c3.metric("Pending retention offers", int(bt["RETENTION_OFFERS"][0]))
    c4.metric("Portfolio LTV (expected interest)", f"Rs {bt['TOTAL_LTV_INR'][0]/1e7:.1f} Cr")

    st.subheader("RBI Asset Classification")
    chart = alt.Chart(dist).mark_bar().encode(
        x=alt.X("BORROWER_ASSET_CLASS:N", sort=["STANDARD", "SMA-0", "SMA-1", "SMA-2", "NPA"], title="Asset Class"),
        y=alt.Y("N:Q", title="Borrowers"),
        color=alt.Color("BORROWER_ASSET_CLASS:N", legend=None),
    )
    st.altair_chart(chart, use_container_width=True)

    st.caption("Blended GNPA is value-weighted across products (LAP/MSME/PL/TW/CD). "
               "Above the system benchmark by design - this is an unsecured-heavy NBFC portfolio, not deteriorating asset quality.")

# ---------------------------------------------------------------------------
# BORROWER LOOKUP
# ---------------------------------------------------------------------------
elif page == "Borrower Lookup":
    st.header("Borrower Lookup")

    search = st.text_input("Borrower ID or name contains", value="BRW000002")
    df = run("""
        SELECT borrower_id, full_name, city, borrower_asset_class, bt_risk_score,
               bt_is_a_flight_risk, ltv_expected_interest_inr, overall_sentiment_direction,
               any_ptp_made_then_missed, n_pending_recommendations
        FROM BORROWER360.CURATED.BORROWER_360
        WHERE borrower_id ILIKE ? OR full_name ILIKE ?
        LIMIT 25
    """, params=[f"%{search}%", f"%{search}%"])

    if df.empty:
        st.info("No borrower matched.")
    else:
        st.dataframe(df, use_container_width=True)
        chosen = st.selectbox("Select borrower for full 360", df["BORROWER_ID"].tolist())

        b360 = run("SELECT * FROM BORROWER360.CURATED.BORROWER_360 WHERE borrower_id = ?",
                    params=[chosen]).iloc[0]

        st.subheader(f"{b360['FULL_NAME']} ({chosen}) - {b360['CITY']}")
        if b360["IS_DEMO_CASE"]:
            st.info(f"Demo case: {b360['DEMO_CASE_LABEL']}")

        cc1, cc2, cc3 = st.columns(3)
        with cc1:
            st.markdown("**Credit risk**")
            st.write(f"Asset class: `{b360['BORROWER_ASSET_CLASS']}`")
            st.write(f"NPA: {b360['IS_NPA']}  |  Upgrade eligible: {b360['NPA_UPGRADE_ELIGIBLE']}")
            st.write(f"Outstanding: Rs {b360['TOTAL_OUTSTANDING_INR']:,.0f}  |  Arrears: Rs {b360['TOTAL_ARREARS_INR']:,.0f}")
            st.write(f"Loan stacked: {b360['IS_LOAN_STACKED']}  ({b360['TOTAL_LENDER_COUNT']} lenders)")
        with cc2:
            st.markdown("**Balance-transfer risk** _(separate from credit risk)_")
            st.write(f"BT risk score: {b360['BT_RISK_SCORE']}")
            st.write(f"Genuine flight risk: **{b360['BT_IS_A_FLIGHT_RISK']}**")
            st.write(f"Retention value if offered: Rs {b360['BT_RETENTION_VALUE_IF_OFFERED_INR']:,.0f}")
            st.write(f"LTV (expected future interest): Rs {b360['LTV_EXPECTED_INTEREST_INR']:,.0f}")
        with cc3:
            st.markdown("**Behavioral trajectory**")
            st.write(f"Interactions: {b360['N_INTERACTIONS']}")
            st.write(f"Sentiment direction: {b360['OVERALL_SENTIMENT_DIRECTION']}")
            st.write(f"PTP made then missed: {b360['ANY_PTP_MADE_THEN_MISSED']}")
            st.write(f"Reason changed across calls: {b360['ANY_REASON_CHANGE']}")

        st.subheader("Pending recommendations")
        recs = run("""
            SELECT recommendation_id, action_code, action_family, rule_basis, expected_value_inr,
                   bureau_disclosure, status
            FROM BORROWER360.AI.NBA_RECOMMENDATION
            WHERE borrower_id = ? AND status = 'PENDING_APPROVAL'
        """, params=[chosen])

        if recs.empty:
            st.write("No pending recommendations.")
        else:
            for _, r in recs.iterrows():
                with st.container():
                    st.markdown(f"**{r['ACTION_CODE']}** ({r['ACTION_FAMILY']}) - Expected value: Rs {r['EXPECTED_VALUE_INR']:,.0f}")
                    st.caption(r["RULE_BASIS"])
                    if r["BUREAU_DISCLOSURE"]:
                        st.warning(f"Bureau impact: {r['BUREAU_DISCLOSURE']}")
                    a1, a2, _ = st.columns([1, 1, 4])
                    if a1.button("Approve", key=f"appr_{r['RECOMMENDATION_ID']}"):
                        run("CALL BORROWER360.AI.SP_DECIDE_RECOMMENDATION(?, 'APPROVED', ?)",
                            params=[r["RECOMMENDATION_ID"], "streamlit_reviewer"])
                        st.success("Approved.")
                        st.experimental_rerun()
                    if a2.button("Reject", key=f"rej_{r['RECOMMENDATION_ID']}"):
                        run("CALL BORROWER360.AI.SP_DECIDE_RECOMMENDATION(?, 'REJECTED', ?)",
                            params=[r["RECOMMENDATION_ID"], "streamlit_reviewer"])
                        st.warning("Rejected.")
                        st.experimental_rerun()

        st.subheader("Recent call transcripts")
        calls = run("""
            SELECT transcript_sequence_number, contact_date, transcript_text
            FROM BORROWER360.CURATED.CALL_TRANSCRIPT
            WHERE borrower_id = ? ORDER BY transcript_sequence_number
        """, params=[chosen])
        for _, c in calls.iterrows():
            with st.expander(f"Call {c['TRANSCRIPT_SEQUENCE_NUMBER']} - {c['CONTACT_DATE']}"):
                st.text(c["TRANSCRIPT_TEXT"])

# ---------------------------------------------------------------------------
# NBA ACTION QUEUE
# ---------------------------------------------------------------------------
elif page == "NBA Action Queue":
    st.header("Next-Best-Action Queue")

    family = st.selectbox("Action family", ["All", "COLLECTIONS", "RETENTION", "GROWTH", "SERVICE"])
    where = "" if family == "All" else "AND action_family = ?"
    q = f"""
        SELECT recommendation_id, borrower_id, action_code, action_family, expected_value_inr, rule_basis
        FROM BORROWER360.AI.NBA_RECOMMENDATION
        WHERE status = 'PENDING_APPROVAL' {where}
        ORDER BY expected_value_inr DESC LIMIT 200
    """
    params = [] if family == "All" else [family]
    queue = run(q, params=params)
    st.write(f"{len(queue)} pending recommendations (top 200 by expected value)")
    st.dataframe(queue, use_container_width=True)

# ---------------------------------------------------------------------------
# ASK THE AGENT
# ---------------------------------------------------------------------------
elif page == "Ask the Agent":
    st.header("Ask the Agent")
    st.caption("Natural-language question in, recommended action out - routed through "
               "BORROWER360.SEMANTIC.BORROWER_360_AGENT. Any recommendation the agent surfaces "
               "still needs Approve/Reject below; nothing is auto-sent to a borrower.")

    if "agent_messages" not in st.session_state:
        st.session_state.agent_messages = []

    def render_agent_tables(cols, rows, msg_idx):
        df = pd.DataFrame(rows, columns=cols)
        st.dataframe(df, use_container_width=True)
        if "RECOMMENDATION_ID" not in cols:
            return
        for row_idx, row in enumerate(rows):
            rec = dict(zip(cols, row))
            rec_id = rec.get("RECOMMENDATION_ID")
            if not rec_id:
                continue
            label = rec.get("ACTION_CODE", rec_id)
            st.caption(f"Recommendation `{rec_id}` - {label}")
            a1, a2, _ = st.columns([1, 1, 4])
            if a1.button("Approve", key=f"agent_appr_{msg_idx}_{row_idx}"):
                run("CALL BORROWER360.AI.SP_DECIDE_RECOMMENDATION(?, 'APPROVED', ?)",
                    params=[rec_id, "streamlit_reviewer"])
                st.success(f"Approved {rec_id}.")
                st.experimental_rerun()
            if a2.button("Reject", key=f"agent_rej_{msg_idx}_{row_idx}"):
                run("CALL BORROWER360.AI.SP_DECIDE_RECOMMENDATION(?, 'REJECTED', ?)",
                    params=[rec_id, "streamlit_reviewer"])
                st.warning(f"Rejected {rec_id}.")
                st.experimental_rerun()

    for i, msg in enumerate(st.session_state.agent_messages):
        st.markdown(f"**{msg['role'].capitalize()}:** {msg['text']}")
        for cols, rows in msg.get("tables", []):
            render_agent_tables(cols, rows, i)

    with st.form("ask_agent_form", clear_on_submit=True):
        question = st.text_input("Your question", placeholder="e.g. What's the recommended action for BRW002563?")
        submitted = st.form_submit_button("Ask")

    if submitted and question:
        st.session_state.agent_messages.append({"role": "user", "text": question, "tables": []})

        api_messages = [
            {"role": m["role"], "content": [{"type": "text", "text": m["text"]}]}
            for m in st.session_state.agent_messages
        ]
        with st.spinner("Asking the agent..."):
            reply_text, tables = call_agent(api_messages)

        st.session_state.agent_messages.append({
            "role": "assistant",
            "text": reply_text if reply_text else "(no text reply - see table below)",
            "tables": tables,
        })
        st.experimental_rerun()

    if st.button("Clear conversation"):
        st.session_state.agent_messages = []
        st.experimental_rerun()

# ---------------------------------------------------------------------------
# DEMO CONTRAST
# ---------------------------------------------------------------------------
else:
    st.header("Demo: The Balance-Transfer Contrast")
    st.write("Two borrowers, both current on payments, both mention a competitor's lower rate. "
             "The structured loan economics - not sentiment, not the transcript alone - decide what happens next.")

    demo = run("""
        SELECT borrower_id, full_name, borrower_asset_class, bt_risk_score, bt_is_a_flight_risk,
               ltv_expected_interest_inr, has_retention_offer, demo_case_label
        FROM BORROWER360.CURATED.BORROWER_360 WHERE is_demo_case ORDER BY borrower_id
    """)
    for _, d in demo.iterrows():
        with st.container():
            st.subheader(f"{d['FULL_NAME']} ({d['BORROWER_ID']})")
            st.write(d["DEMO_CASE_LABEL"])
            m1, m2, m3 = st.columns(3)
            m1.metric("BT risk score", d["BT_RISK_SCORE"])
            m2.metric("Genuine flight risk", str(d["BT_IS_A_FLIGHT_RISK"]))
            m3.metric("Retention offer made", str(d["HAS_RETENTION_OFFER"]))

            calls = run("""
                SELECT transcript_text FROM BORROWER360.CURATED.CALL_TRANSCRIPT
                WHERE borrower_id = ? ORDER BY transcript_sequence_number LIMIT 1
            """, params=[d["BORROWER_ID"]])
            if not calls.empty:
                with st.expander("Read the call"):
                    st.text(calls.iloc[0]["TRANSCRIPT_TEXT"])
