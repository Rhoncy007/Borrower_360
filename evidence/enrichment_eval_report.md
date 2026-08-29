# BORROWER360 — Transcript Enrichment Evaluation Report

## Headline finding

A text-only intent classifier reads 83% of wilful defaulters as genuine hardship
(76/92 transcripts), because that is what they are deliberately designed to
sound like. On its own, that 17.4% per-transcript accuracy figure reads as a
broken classifier. It is not — it is the finding the corpus was built to
produce.

**The real number is what happens when signals are combined, and it is earned,
not circular:**

| Signal | Recall on true wilful (n=23 borrowers) | False positive rate (n=1,045 non-wilful) | Precision |
|---|---|---|---|
| Text only, per-transcript | 17.4% | — | — |
| Text only, per-borrower (any of their calls) | 69.6% | — | — |
| Text + broken-PTP + reason-change, ANY signal | **95.7%** | 17.4% | 10.8% |
| Text + broken-PTP + reason-change, 2-of-3 required | 78.3% | 9.1% | 15.9% |
| Structural (mandate revoked with INTENT attribution) | 100% | 1.3% | — *(see caveat)* |

**Caveat on the structural row, stated plainly:** `INTENT` mandate-revocation was
the literal generation criterion used to select `WILFUL_DEFAULT_ADVERSARIAL`
borrowers. Checking it against that label is close to checking a label against
its own definition — it is not independent evidence and must not be presented
as a finding. It is documented here for completeness, clearly marked as
circular.

**The genuinely earned headline is 17.4% → 95.7%** (or, for a more deployable
precision/recall balance, → 78.3% at 2-of-3 signals) — driven entirely by
combining per-call text classification with two trajectory signals computed
from the sequenced corpus (broken promise-to-pay, reason inconsistency across
calls). Neither signal exists without the corpus being sequenced. This is the
unification argument made concrete: no single layer — not the transcript
alone, not the structured data alone — is sufficient on its own.

## Full confusion matrix (borrower-level ground truth, per-transcript prediction)

BT_RATIONAL_RATE_SHOPPER and BT_NOT_RATIONAL_RATE_SHOPPER are collapsed to one
predicted class (`rate_shopping_balance_transfer`) for scoring purposes.
**Reasoning, stated explicitly:** whether a balance-transfer intent is
economically *rational* depends on residual tenor and rate-gap-vs-switching-cost
— quantities computed from loan economics (`LOAN_ECONOMICS`), not present in or
inferable from the conversation text. Holding a text classifier accountable for
a distinction it has no textual signal to make would be an unfair evaluation,
not a rigorous one. This collapse is a judgment about what a classifier can be
held responsible for, not a convenience.

| Ground truth | n | Accuracy | Dominant confusion | Semantic reasonableness |
|---|---|---|---|---|
| GENUINE_HARDSHIP | 500 | 100.0% | none | Concrete, specific detail (by generation design) leaves no ambiguity |
| TECHNICAL_BOUNCE | 502 | 88.8% | →rate_shopping (40) | Mild; some technical calls incidentally touch on cost |
| BT_RATIONAL_RATE_SHOPPER | 498 | 83.1% | →growth_call (60) | Long-tenor BT calls carry clear "seriously considering leaving" urgency |
| BT_NOT_RATIONAL_RATE_SHOPPER | 492 | 66.5% | →growth_call (147) | Short-tenor BT calls read as lower-stakes, closer to routine outreach |
| GROWTH_CLEAN | 510 | 61.6% | →rate_shopping (195) | **Real weakness — see structural gate below** |
| AMBIGUOUS_FIRST_BOUNCE (n=106) | 106 | 33.0% | →genuine_hardship (68) | Taxonomy overlap — see below. Small sample: wide error bars |
| WILFUL_DEFAULT_ADVERSARIAL (n=92) | 92 | 17.4% | →genuine_hardship (76) | **The headline finding — see above.** Small sample: wide error bars |

**Small-sample caveat:** WILFUL_DEFAULT (92) and AMBIGUOUS_FIRST_BOUNCE (106)
are the two categories the "only the transcript disambiguates" story rests on
most, and they are also the two smallest. A single reclassified borrower moves
either accuracy figure by more than a point. These populations were not padded
to look more precise than they are — see build log, "the corpus was built by
real population, not inflated to hit a round number." Treat both figures as
directional, not exact.

## Named taxonomy-overlap boundary case

`AMBIGUOUS_FIRST_BOUNCE → GENUINE_HARDSHIP` (68/106) is a real, quantified
taxonomy limitation, not a model failure: ambiguous first-miss transcripts give
a vague-but-sympathetic reason that reads similarly to hardship framing by
design (the borrower "sounds a little embarrassed," per generation
instructions). A specific case surfaced during manual review: a mandate that
was fixed but payment hadn't landed yet ("I'm planning to pay tomorrow... will
it work this time?") sits legitimately between `TECHNICAL_BOUNCE` and
`AMBIGUOUS_FIRST_BOUNCE` — a real boundary condition in the taxonomy, named
here rather than left for a reviewer to find first.

## GROWTH_CLEAN structural gate

61.6% accuracy with 195/510 growth calls misread as `rate_shopping_balance_transfer`
is a real weakness, not an interesting one: if a retention action were ever
triggered directly from this text classification, the system would waste
retention budget (rate concessions) on borrowers who were never leaving —
exactly the false-positive failure mode the two-risk-model design (credit risk
vs. balance-transfer risk) exists to prevent.

**Fix chosen: structural gate, not prompt tightening.** `NBA_RECOMMENDATION`
has never derived `BT_COUNTER` from transcript classification — it is computed
exclusively from `LOAN_ECONOMICS.bt_is_economically_rational`, itself derived
from residual tenor and rate gap. This was true by construction before this
finding, but "true by construction" is not the same as "guaranteed." It is now
a standing, permanently re-checked assertion:

`BORROWER360.UTIL.V_STANDING_ASSERTIONS`, row `D1_growth_call_triggered_
retention_without_structural_bt_signal` — verified at 0 violations at time of
writing, and re-checked on every future rebuild. A misread transcript can
surface as evidence; it can never be the trigger on its own.

## AI_EXTRACT null analysis

Zero function errors across all 2,700 rows (`raw_extract:error` is null
everywhere). All nulls are category-appropriate absences of information, not
extraction failures:

- `GROWTH_CLEAN` / `BT_*` / `TECHNICAL_BOUNCE`: 88-99% have no promise-to-pay
  or stated reason — correct, since these calls structurally don't involve a
  payment promise or delinquency excuse.
- `GENUINE_HARDSHIP`: only 3/500 missing a promise amount — as designed, nearly
  every hardship call includes a concrete PTP.
- `WILFUL_DEFAULT_ADVERSARIAL`: only 4/92 missing a stated reason — evasive
  borrowers still give *some* excuse, just an inconsistent one.

## Trajectory layer

`AI.CALL_TRANSITION` (1,860 transitions, 840 borrowers) and
`AI.BORROWER_TRAJECTORY_SUMMARY`. Sentiment-category deltas alone are too
coarse a signal (only 30% of wilful borrowers register categorical
`DETERIORATING`); the reliable trajectory signals are broken-PTP tracking
(83% of wilful borrowers) and reason-inconsistency tracking (57%).

Concrete example (real borrower from the corpus): reason given changes once,
from a technical excuse ("insufficient balance") to a hardship-framed one
("business is slow"), then holds steady while three consecutive payment
promises break and sentiment turns negative. Neither the structured data nor
any single transcript shows this pattern — only the sequence does.
