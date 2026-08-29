# BORROWER360

A borrower-360 lending intelligence system for an Indian mixed-NBFC retail lender (two-wheeler, personal, consumer durable, MSME, and loan-against-property products), built on Snowflake with Cortex AI.

It unifies structured loan/credit data with LLM-derived signals from collections call transcripts, and turns that into governed, human-approved next-best-action (NBA) recommendations — surfaced through a Cortex Agent and a Streamlit dashboard.

## What it does

- **Credit risk classification** — borrower-level RBI IRAC asset classification (Standard / SMA-0 / SMA-1 / SMA-2 / NPA) computed from real DPD (days-past-due) data.
- **Balance-transfer (BT) flight-risk scoring** — structurally *separate* from credit risk: a borrower in credit distress always scores zero BT risk, regardless of competitor rate gap. See `.cortex/skills/credit-vs-bt-risk-separation` conceptually, or `sql/02_curated/20_curated_schema.sql` (`LOAN_ECONOMICS` view) for the actual logic.
- **Call transcript enrichment** — an incremental Dynamic Table (`AI.TRANSCRIPT_INSIGHT`) runs `AI_EXTRACT`, `AI_SENTIMENT`, `AI_CLASSIFY`, and `AI_FILTER` over ~2,700 collections call transcripts to extract promise-to-pay commitments, sentiment, stated reasons, and competitor mentions.
- **Sentiment/behavioral trajectory** — pairwise call-to-call transitions detect broken promises (promise made, then missed) and reason-changes across a borrower's call history, which can escalate their NBA tier.
- **Deterministic next-best-action engine** — every recommendation traces to a named SQL rule (`rule_basis`), not a model guess. An LLM (`mistral-7b`) only writes a persona-appropriate explanation (`model_contribution`) — it never decides or overrides the action.
- **Human-in-the-loop approval** — recommendations are always created `PENDING_APPROVAL`. The only way status changes is `SP_DECIDE_RECOMMENDATION`, called explicitly by a human (via the Streamlit app or the Cortex Agent).
- **Cortex Agent** (`BORROWER_360_AGENT`) — a conversational interface backed by a Cortex Analyst semantic view (`BORROWER_360_MODEL`), plus tools to approve/reject recommendations and push approved actions to a team task queue (respecting the RBI Fair Practices Code 08:00–19:00 IST contact window).
- **Streamlit app** — Portfolio Overview, Borrower Lookup (inline approve/reject), NBA Action Queue, and a Demo Contrast page.

## Architecture

```
RAW            Landing zone: synthetic borrower/loan/transcript data, demo PDFs
CURATED        Conformed entities: BORROWER, LOAN_ACCOUNT, MANDATE, BORROWER_STATE,
               BORROWER_360, LOAN_ECONOMICS (credit risk + BT risk, separated)
AI             LLM enrichment: TRANSCRIPT_INSIGHT (dynamic table), CALL_TRANSITION,
               BORROWER_TRAJECTORY_SUMMARY, NBA_RECOMMENDATION, NBA_DECISION_LOG
UTIL           Config tables, cost/spend tracking views, V_STANDING_ASSERTIONS
               (9 SQL guardrail checks that must all return violation_count = 0)
APP            TEAM_TASK_QUEUE, SP_CREATE_TEAM_TASKS, MCP server, Streamlit app
SEMANTIC       BORROWER_360_MODEL (Cortex Analyst semantic view),
               BORROWER_360_AGENT (Cortex Agent)
```

Refresh flow: new transcripts land → `TRANSCRIPT_INSIGHT` (dynamic table, 1-minute target lag) enriches them → a stream surfaces only the new rows → `TASK_REFRESH_TRAJECTORY_AND_NBA` (1-minute schedule, created suspended) calls `SP_REFRESH_TRAJECTORY_AND_NBA`, which updates trajectory signals, regenerates NBA recommendations (carrying forward existing human decisions and AI rationale for unchanged rows), and rematerializes `BORROWER_360`.

## Repository layout

```
sql/                  DDL, organized by schema/build order (00_foundation → 06_semantic)
cortex_project/        Agent + semantic view project files (deploy via cortex/snow CLI)
agents/                Cortex Agent YAML definition
proto/                 Semantic view + agent prototyping artifacts
streamlit_app/         The Streamlit-in-Snowflake app (streamlit_app.py, snowflake.yml)
scripts/               Synthetic data / demo document generation scripts
documents/             Synthetic demo documents for the document-intelligence flow
evidence/              Build log, object inventory, evaluation reports (project documentation)
```

## Running it

1. Deploy the SQL in `sql/` in order (`00_foundation` → `06_semantic`) against a Snowflake account.
2. Deploy the semantic view and agent from `cortex_project/` (or `agents/`) using the Cortex CLI / `snow` CLI.
3. Deploy the Streamlit app: `streamlit_app/snowflake.yml` defines it as `BORROWER360.APP.BORROWER_360_APP`.
4. Resume `AI.TASK_REFRESH_TRAJECTORY_AND_NBA` (created suspended by default) to enable live refresh.

## Compliance guardrails

- `UTIL.V_STANDING_ASSERTIONS` — 9 named SQL assertions (A1–A5, B1–B2, C1, D1) verifying credit/BT risk separation, rule traceability, mandatory bureau disclosure, decision logging, and data integrity.
- `AI.NBA_DECISION_LOG` — one row per recommendation, written at generation time, so no recommendation exists without an audit trail.
