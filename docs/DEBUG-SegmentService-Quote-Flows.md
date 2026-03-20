# Debug: SegmentService not running / no Segment__c rows

## What runs SegmentService today

1. **Create Or Update Segments Quote After Save** (recommended)  
   Record-triggered flow: **Quote** → **After save** → **Create and update** → Apex `SegmentService` with **`$Record.Id`**.  
   This runs on normal Quote inserts/updates (including the UI).

2. **Create Or Update Segments For Quote** (legacy)  
   Subscribes to **`QuoteSaveEvent`** (Revenue Cloud platform event). That event **does not fire for every Quote DML** (e.g. some standard saves may not publish it).  
   The Apex input uses **`$Record.Quote.Id`**, which must match the **actual field names** on `QuoteSaveEvent` in your org. If the merge field is wrong, **`quoteId` can be null** and SegmentService will fail or never receive the Id.

If you see **no** `SegmentService` debug logs when saving a Quote, the platform-event flow was likely never started—use the **record-triggered** flow above or verify the event subscription in **Setup → Flows**.

## Manual test (Developer Console → Execute Anonymous)

Replace the Id with your Quote (e.g. `0Q0Wt000003MyztKAC`):

```apex
Id quoteId = '0Q0Wt000003MyztKAC';
SegmentService.InvocableRequest req = new SegmentService.InvocableRequest();
req.quoteId = quoteId;
List<SegmentService.InvocableResult> out = SegmentService.createOrUpdateSegmentsForQuote(
    new List<SegmentService.InvocableRequest>{ req }
);
System.debug(out);
```

Check **Debug Log** filter **USER_DEBUG** / **SegmentService** for:

- `SegmentService.createOrUpdateSegmentsForQuote START`
- `SegmentService.doCreateOrUpdate quote loaded` … `start=… termMonths=…`
- Early exit: `EXIT quoteStart is null` → Quote is missing **`Proposed_Start_Date__c`**
- Early exit: invalid `quoteEnd` → set **`ExpirationDate`** and/or **`Term_Months__c`**

The invocable **`message`** now states clearly when segments were **skipped** vs **created/updated**.

## Data checks on the Quote

| Field | Role |
|--------|------|
| `Proposed_Start_Date__c` | Required; if blank, SegmentService exits without creating segments. |
| `Term_Months__c` and/or `ExpirationDate` | Used to derive end date; if end cannot be determined or is before start, no segments. |
| `DDA_Share_Accounts_Count__c` | Drives KPI fields on segments (can be zero). |

## Flow interview / errors

- **Setup → Flows** → open **Create Or Update Segments Quote After Save** → **Run** (or use **Debug** on a record) to confirm it runs and Apex receives the Quote Id.
- Failed Apex: check **Paused and Failed Flow Interviews** and the error email (if enabled).

## Avoid duplicate runs

If both the **QuoteSaveEvent** flow and the **Quote After Save** flow are **Active**, SegmentService may run twice on some saves. That is usually harmless (upsert is idempotent). Deactivate one if you want a single path.
