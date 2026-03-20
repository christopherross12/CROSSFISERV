/**
 * Data for the Line Segment Revenue (Recurring Fees) grid on a Quote record page.
 */
public with sharing class LineSegmentRevenueTableController {
    @AuraEnabled(cacheable=false)
    public static RecurringFeeGrid getRecurringFeeGrid(Id quoteId) {
        RecurringFeeGrid grid = new RecurringFeeGrid();
        if (quoteId == null) {
            return grid;
        }

        List<Segment__c> segments = [
            SELECT Id, Start_Date__c, End_Date__c
            FROM Segment__c
            WHERE Quote__c = :quoteId
            WITH SECURITY_ENFORCED
            ORDER BY Start_Date__c ASC
        ];
        for (Segment__c seg : segments) {
            SegmentColumn col = new SegmentColumn();
            col.segmentId = seg.Id;
            col.yearLabel = seg.Start_Date__c != null ? String.valueOf(seg.Start_Date__c.year()) : '';
            grid.segmentColumns.add(col);
        }
        if (segments.isEmpty()) {
            return grid;
        }
        Set<Id> segmentIds = new Map<Id, Segment__c>(segments).keySet();

        List<QuoteLineItem> lines = [
            SELECT
                Id,
                UnitPrice,
                StartDate,
                EndDate,
                RLM_ProductName__c,
                Product2.Name
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate
        ];

        List<QuoteLineItem> termedLines = new List<QuoteLineItem>();
        for (QuoteLineItem li : lines) {
            if (LineSegmentRevenueService.isTermedQuoteLine(li)) {
                termedLines.add(li);
            }
        }

        Map<String, Decimal> amountByLineAndSegment = new Map<String, Decimal>();
        for (Line_Segment_Revenue__c lsr : [
            SELECT Segment__c, Quote_Line__c, Segment_Revenue_Amount__c
            FROM Line_Segment_Revenue__c
            WHERE Segment__c IN :segmentIds
            WITH SECURITY_ENFORCED
        ]) {
            String key = String.valueOf(lsr.Quote_Line__c) + '_' + String.valueOf(lsr.Segment__c);
            amountByLineAndSegment.put(key, lsr.Segment_Revenue_Amount__c);
        }

        List<Decimal> columnTotals = new List<Decimal>();
        for (Integer i = 0; i < segments.size(); i++) {
            columnTotals.add(0);
        }

        for (QuoteLineItem li : termedLines) {
            RecurringFeeRow row = new RecurringFeeRow();
            row.quoteLineId = li.Id;
            row.productName = resolveProductName(li);
            row.unitPrice = li.UnitPrice;
            Decimal rowTotal = 0;

            Integer colIndex = 0;
            for (Segment__c seg : segments) {
                String key = String.valueOf(li.Id) + '_' + String.valueOf(seg.Id);
                Decimal amt = amountByLineAndSegment.containsKey(key) ? amountByLineAndSegment.get(key) : 0;
                if (amt == null) {
                    amt = 0;
                }
                row.segmentAmounts.add(amt);
                rowTotal += amt;
                columnTotals.set(colIndex, columnTotals[colIndex] + amt);
                colIndex++;
            }
            row.rowTotal = rowTotal;
            grid.rows.add(row);
        }

        grid.columnTotals = columnTotals;
        return grid;
    }

    /**
     * Rebuilds Line_Segment_Revenue__c for the Quote using any Segment on the Quote as anchor.
     */
    @AuraEnabled(cacheable=false)
    public static SyncResult syncLineSegmentRevenueForQuote(Id quoteId) {
        SyncResult out = new SyncResult();
        if (quoteId == null) {
            out.success = false;
            out.message = 'Quote Id is required.';
            out.recordsCreated = 0;
            return out;
        }
        List<Segment__c> segs = [
            SELECT Id
            FROM Segment__c
            WHERE Quote__c = :quoteId
            WITH SECURITY_ENFORCED
            ORDER BY Start_Date__c ASC
            LIMIT 1
        ];
        if (segs.isEmpty()) {
            out.success = true;
            out.message = 'No segments on this Quote; nothing to sync.';
            out.recordsCreated = 0;
            return out;
        }
        LineSegmentRevenueService.InvocableResult svcResult = LineSegmentRevenueService.syncForSegmentLWC(segs[0].Id);
        out.success = svcResult.success;
        out.message = svcResult.message;
        out.recordsCreated = svcResult.recordsCreated;
        return out;
    }

    public class SyncResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Integer recordsCreated;
    }

    private static String resolveProductName(QuoteLineItem li) {
        if (String.isNotBlank(li.RLM_ProductName__c)) {
            return li.RLM_ProductName__c.trim();
        }
        if (li.Product2 != null && String.isNotBlank(li.Product2.Name)) {
            return li.Product2.Name.trim();
        }
        return 'Line Item';
    }

    public class RecurringFeeGrid {
        @AuraEnabled public List<SegmentColumn> segmentColumns = new List<SegmentColumn>();
        @AuraEnabled public List<RecurringFeeRow> rows = new List<RecurringFeeRow>();
        @AuraEnabled public List<Decimal> columnTotals = new List<Decimal>();
    }

    public class SegmentColumn {
        @AuraEnabled public String segmentId;
        @AuraEnabled public String yearLabel;
    }

    public class RecurringFeeRow {
        @AuraEnabled public String quoteLineId;
        @AuraEnabled public String productName;
        @AuraEnabled public Decimal unitPrice;
        @AuraEnabled public List<Decimal> segmentAmounts = new List<Decimal>();
        @AuraEnabled public Decimal rowTotal;
    }
}
