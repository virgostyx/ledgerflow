---
id: variation
title: Why did this item change?
validated: false
---
## Symptom
A heading or an account changed between two periods and the person wants to know why.
## Frequent causes
1. One large movement that does not recur.
2. A new partner or a change of the account used.
3. A calendar effect (not the same number of months).
4. Reversals and corrections.
## Checks
- `get_variation` (the accounts, the two periods, grouped by account, partner and month): the exact change and its main contributors.
- `get_financial_statements`: the change by heading.
## Interpretation
If one movement explains more than 30 percent of the change, it is the main cause, not a trend. An amount in the second period and none in the first is a new item. Periods of different lengths are not comparable as they are.
## Fix
Nothing to correct unless the contributor is an error: then follow the protocol of the anomaly. [[screen:journal]]
## Prevention
Compare periods of the same length.
## Escalate
When a large movement has no document behind it.
