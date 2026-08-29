# BORROWER360 — Object Inventory

Every deployed object, by schema, with a one-line description. For the
README and the demo script — exact names, no paraphrasing.

## RAW schema

| Object | Type | Description |
|---|---|---|
| `DEMO_DOCUMENTS` | Stage | Synthetic salary slip / bank statement / hardship letter PDFs for the document-intelligence demo. |

## CURATED schema

| Object | Type | Description |
|---|---|---|
| `BORROWER` | Table | Base borrower reference data. |
| `BORROWER_STATE` | Table | Current borrower-level state: RBI asset classification, DPD, bureau score, loan-stacking flags. Rebuilt by `SP_REBUILD_SPINE`. |
| `BORROWER_360` | Table | Unified borrower 360 — credit risk, BT risk (zeroed for distress), LTV, trajectory, pending-NBA summary. Materialized; refreshed by `SP_REFRESH_TRAJECTORY_AND_NBA`. |
| `BUREAU_TRADELINE` | Table | Bureau tradeline reference data. |
| `CALL_TRANSCRIPT` | Table | The 2,700+ transcript corpus. Stream-enabled (`CHANGE_TRACKING=TRUE`) as the ultimate source for the enrichment dynamic table. |
| `CRM_CONTACT` | Table | CRM contact reference data. |
| `DIM_ACTION` | Table | NBA action catalogue — deterministic eligibility, margin impact, mandatory bureau disclosure per action. |
| `DIM_AGENCY` | Table | Collections agency reference (RBI FPC: lender is accountable for agent conduct). |
| `DIM_AGENT` | Table | Servicing/collections agent reference. |
| `DIM_GEOGRAPHY` | Table | Indian city/geography reference. |
| `LOAN_ACCOUNT` | Table | Loan-level structured data (DPD, EMI, product, tenor). Rebuilt by `SP_REBUILD_SPINE`. |
| `LOAN_ECONOMICS` | View | Per-loan credit-risk/BT-risk economics — the view where BT risk is forced to zero at distress, at the score itself. |
| `MANDATE` | Table | NACH/UPI mandate history, incl. failure attribution (technical vs. intent). |
| `PAYMENT_TXN` | Table | Payment transaction history. |
| `REPAYMENT_SCHEDULE` | Table | Full amortization schedule per loan — source for the LTV proxy. |

## AI schema

| Object | Type | Description |
|---|---|---|
| `BORROWER_TRAJECTORY_SUMMARY` | Table | Borrower-grain trajectory aggregate — sentiment direction, broken-promise flag, reason-change flag, contact-gap trend. Rebuilt by `SP_REFRESH_TRAJECTORY_AND_NBA`. |
| `CALL_TRANSITION` | Table | Pairwise call-to-call transitions (LAG-based) — sentiment delta, PTP made-then-missed, reason-change (via `AI_FILTER`). |
| `NBA_DECISION_LOG` | Table | One row per recommendation, written at generation time — no silent paths. |
| `NBA_RECOMMENDATION` | Table | Next-best-action recommendations. `status` always starts `PENDING_APPROVAL`; `rule_basis` (deterministic) and `model_contribution` (AI-written explanation) are separate columns. |
| `STG_NBA_RULES` | Table | Staging table for NBA rule evaluation, rebuilt each cycle. |
| `STG_REASON_COMPARISON` | Table | Staging for pairwise `AI_FILTER` reason-change comparisons. |
| `TRANSCRIPT_INSIGHT` | **Dynamic Table** | Per-transcript enrichment (`AI_EXTRACT`/`AI_SENTIMENT`/`AI_CLASSIFY`/`AI_FILTER`). `INCREMENTAL`, `TARGET_LAG='1 minute'`. 2,700 historical rows backfilled at zero AI cost; only new transcripts get processed. |
| `TRANSCRIPT_INSIGHT_LEGACY` | Table | The original static enrichment table, preserved as-is after the DT swap — historical record, not read by anything live. |
| `STRM_TRANSCRIPT_INSIGHT` | **Stream** | Stream on `TRANSCRIPT_INSIGHT` (the DT), filtered to `METADATA$ACTION='INSERT'` — surfaces only newly-enriched rows, eliminating the enrichment-ordering race. |
| `TASK_REFRESH_TRAJECTORY_AND_NBA` | **Task** | 1-minute schedule. Downstream of the DT. Calls `SP_REFRESH_TRAJECTORY_AND_NBA`. **Created/left `SUSPENDED`.** |
| `SP_REBUILD_NBA_RECOMMENDATION` | Procedure | Pure-SQL rebuild of `NBA_RECOMMENDATION` from structured data + trajectory. Deterministic (verified, assertion `A5`). Fresh UUIDs each run — never call directly for a refresh cycle. |
| `SP_GENERATE_NBA_RATIONALE` | Procedure | Writes the 2-sentence, persona-aware `model_contribution` via `AI_COMPLETE` (mistral-7b) for any row at `'NONE'`. Never writes `action_code`. |
| `SP_REFRESH_NBA_PIPELINE` | Procedure | The correct way to refresh NBA: rebuild + carry forward unchanged rationale/decisions + generate rationale only for changed rows. |
| `SP_DECIDE_RECOMMENDATION` | Procedure | The **only** way `NBA_RECOMMENDATION.status` changes from `PENDING_APPROVAL`. Requires an explicit decision and decider name. |
| `SP_REFRESH_TRAJECTORY_AND_NBA` | Procedure | Full downstream orchestrator: consumes the stream, computes new transitions, runs `AI_FILTER` on new reason-pairs only, rebuilds trajectory, calls `SP_REFRESH_NBA_PIPELINE`, materializes `BORROWER_360`. Called by the task above. |

## SEMANTIC schema

| Object | Type | Description |
|---|---|---|
| `BORROWER_360_MODEL` | Semantic View | Cortex Analyst model over `BORROWER_360` + `NBA_RECOMMENDATION`, 5 verified queries. |
| `BORROWER_360_AGENT` | Cortex Agent | Tools: `BorrowerAnalyst` (the semantic view above) + `DecideRecommendation` (wraps `SP_DECIDE_RECOMMENDATION`). Tested live, incl. a real DB-write approval. |

## APP schema

| Object | Type | Description |
|---|---|---|
| `BORROWER_360_APP` | Streamlit app | Portfolio Overview, Borrower Lookup (inline approve/reject), NBA Action Queue, Demo Contrast pages. Container runtime, `snowflake.snowpark.pypi_shared_repository` artifact repo (no EAI needed). |
| `TEAM_TASK_QUEUE` | Table | Internal task queue for approved recommendations, routed by owning team. The only reachable target for MCP — no external ticketing system is reachable on this account. |
| `SP_CREATE_TEAM_TASKS` | Procedure | Reads only `status='APPROVED'` rows, enforces the RBI FPC 08:00–19:00 IST window in SQL, idempotent (`MERGE`). Verified: cannot create a task for a `PENDING_APPROVAL` row. |
| `MCP_TEAM_TASKS` | MCP Server | Native MCP server, `GENERIC` tool wrapping `SP_CREATE_TEAM_TASKS`. |

## UTIL schema

| Object | Type | Description |
|---|---|---|
| `CONFIG_BT_THRESHOLD` | Table | Product-dependent BT residual-tenor threshold (not the flat 5–7yr home-loan rule). |
| `CONFIG_ECONOMIC_ASSUMPTION` | Table | Single source of truth for economic constants (cost of funds, BT min rate gap). |
| `CONFIG_PRODUCT_CALIBRATION` | Table | Per-product generation targets, blending to portfolio GNPA. |
| `CONFIG_TRANSCRIPT_MODEL` | Table | Model choice per transcript persona, with the reason (incl. the FPC-violation pilot finding) recorded in-schema. |
| `DETERMINISM_TEST_RUN1` | Table | Baseline snapshot of `(borrower_id, loan_id, action_code)` for the `A5` determinism assertion. Refresh deliberately after any legitimate rule/data change. |
| `GROUND_TRUTH_HIDDEN` | Table | Hidden ground-truth labels for the transcript corpus, structurally isolated — the enrichment role has no grant on this table or schema at all. |
| `V_AI_SPEND_BY_TAG` | View | AI credit spend by function/model, from `ACCOUNT_USAGE`. |
| `V_CREDIT_RATES` | View | Reference credit rate table (AI vs. platform credits). |
| `V_DELINQUENCY_DISTRIBUTION` | View | Delinquency distribution check against RBI benchmarks. |
| `V_GNPA_BLEND` / `V_GNPA_BLEND_SUMMARY` | Views | Blended GNPA calculation and summary, value-weighted across products. |
| `V_SPEND_BY_CATEGORY` / `V_SPEND_DAILY` / `V_SPEND_SUMMARY` | Views | Cost visibility (resource monitors don't cover AI credits or Cortex Code CLI usage). |
| `V_STANDING_ASSERTIONS` | View | **The single guardrail-verification surface.** 9 named assertions (`A1`–`A5`, `B1`–`B2`, `C1`, `D1`), each a real SQL check that must return `violation_count = 0`. |

## Skills (registered, not bundled — `.cortex/skills/`)

| Object | Description |
|---|---|
| `credit-vs-bt-risk-separation` | Why credit risk and BT risk must never merge; points at `V_STANDING_ASSERTIONS` A1/B1/B2/D1 as the literal check. |
| `nba-playbook` | Rules decide / model explains split; points at `SP_DECIDE_RECOMMENDATION` and A2/A4/A5 as the literal check. Registered via `cortex skill add`; does not fire unprompted in a session started before registration (see build log). |

## Scratch / not part of the deployed system

`evidence/`, `proto/`, `documents/`, `streamlit_app/verify/`, `scripts/` under
the local project directory — build artifacts, generation intermediates,
and verification downloads. Not referenced by anything live.
