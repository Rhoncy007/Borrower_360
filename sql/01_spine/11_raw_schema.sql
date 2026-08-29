-- BORROWER360.RAW schema: landing zone (stage for synthetic demo documents).
-- Extracted via GET_DDL('SCHEMA','BORROWER360.RAW') on 2026-08-29.
-- Note: the DEMO_DOCUMENTS stage object itself is not captured by GET_DDL('SCHEMA',...);
-- recreate with:
-- CREATE OR REPLACE STAGE BORROWER360.RAW.DEMO_DOCUMENTS
--   DIRECTORY = (ENABLE = TRUE)
--   COMMENT = 'Synthetic salary slip / bank statement / hardship letter PDFs for the document-intelligence demo.';

create or replace schema RAW COMMENT='Landing zone. Generated structured spine + raw transcripts. Append-only in spirit.';
