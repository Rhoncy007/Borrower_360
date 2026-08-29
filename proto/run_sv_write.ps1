$yaml = Get-Content -Raw "C:\Users\rakes\borrower360\proto\borrower_360.sv.yaml"
cortex agent-studio sv-write --yaml-content $yaml --source-object BORROWER360.SEMANTIC.BORROWER_360_MODEL
