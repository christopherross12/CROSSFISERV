/**
 * Builds Line_Segment_Revenue__c rows for every Segment year on a Quote × every "termed" Quote Line.
 * Invocable input: any Segment Id on the Quote (used to resolve Quote; all Segments for that Quote are processed).
 *
 * Termed line: both StartDate and EndDate set, EndDate >= StartDate, and inclusive
 * month span from those dates is at least 1 (computed in memory — no SubscriptionTerm / PricingTermCount).
 *
 * Segment Revenue Amount:
 * - Transaction-fee style products (name match): UnitPrice × Segment.Annual_Trans__c
 * - All other termed lines: UnitPrice × Quantity × inclusive months where the Quote Line date range
 *   (StartDate–EndDate) overlaps the Segment date range (Start_Date__c–End_Date__c) for that segment year.
 *   If the line has no Start/End dates, falls back to full months in the Segment date range.
 *   If the line has dates but no overlap with a segment, that cell’s month count is 0.
 */
public with sharing class LineSegmentRevenueService {
    private static final List<String> ANNUAL_TRANS_PRODUCT_PATTERNS = new List<String>{
        'send money transaction to a person',
        'request money transaction',
        'out of network receive money transaction'
    };

    @InvocableMethod(
        label='Sync Line Segment Revenue for Quote (from Segment)'
        description='Given a Segment on a Quote, recreates Line Segment Revenue for all Segment years and all termed Quote Lines on that Quote.'
        category='Segment'
    )
    public static List<InvocableResult> syncFromSegment(List<InvocableRequest> requests) {
        List<InvocableResult> results = new List<InvocableResult>();
        if (requests == null) {
            return results;
        }
        for (InvocableRequest req : requests) {
            InvocableResult res = new InvocableResult();
            try {
                Integer created = doSyncFromSegment(req.segmentId);
                res.success = true;
                res.message = 'Created ' + created + ' Line Segment Revenue record(s).';
                res.recordsCreated = created;
            } catch (Exception e) {
                res.success = false;
                res.message = e.getMessage();
                res.recordsCreated = 0;
            }
            results.add(res);
        }
        return results;
    }

    public class InvocableRequest {
        @InvocableVariable(
            required=true
            label='Segment Id'
            description='Any Segment__c Id for the Quote; all Segments on that Quote are processed.'
        )
        public Id segmentId;
    }

    public class InvocableResult {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Message')
        public String message;
        @InvocableVariable(label='Records Created')
        public Integer recordsCreated;
    }

    private static Integer doSyncFromSegment(Id segmentId) {
        if (segmentId == null) {
            throw new LineSegmentRevenueException('Segment Id is required.');
        }

        Segment__c anchor = [
            SELECT Id, Quote__c
            FROM Segment__c
            WHERE Id = :segmentId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        Id quoteId = anchor.Quote__c;
        if (quoteId == null) {
            throw new LineSegmentRevenueException('Segment has no related Quote.');
        }

        List<Segment__c> segments = [
            SELECT Id, Start_Date__c, End_Date__c, Annual_Trans__c
            FROM Segment__c
            WHERE Quote__c = :quoteId
            WITH SECURITY_ENFORCED
            ORDER BY Start_Date__c ASC
        ];
        if (segments.isEmpty()) {
            return 0;
        }

        Set<Id> segmentIds = new Map<Id, Segment__c>(segments).keySet();

        List<QuoteLineItem> lines = [
            SELECT
                Id,
                UnitPrice,
                Quantity,
                StartDate,
                EndDate,
                RLM_ProductName__c,
                Product2.Name
            FROM QuoteLineItem
            WHERE QuoteId = :quoteId
            WITH SECURITY_ENFORCED
        ];

        List<QuoteLineItem> termedLines = new List<QuoteLineItem>();
        Map<Id, Integer> lineTermMonthsInMemoryByLineId = new Map<Id, Integer>();
        for (QuoteLineItem li : lines) {
            if (isTermedLine(li)) {
                termedLines.add(li);
                lineTermMonthsInMemoryByLineId.put(li.Id, lineTermMonthsInMemory(li));
            }
        }
        if (termedLines.isEmpty()) {
            deleteExistingForSegments(segmentIds);
            return 0;
        }

        deleteExistingForSegments(segmentIds);

        List<Line_Segment_Revenue__c> toInsert = new List<Line_Segment_Revenue__c>();
        for (Segment__c seg : segments) {
            Integer monthsInSegment = fullMonthsBetween(seg.Start_Date__c, seg.End_Date__c);
            Decimal annualTrans = seg.Annual_Trans__c != null ? seg.Annual_Trans__c : 0;

            for (QuoteLineItem li : termedLines) {
                String productLabel = resolveProductLabel(li);
                Decimal unitPrice = li.UnitPrice != null ? li.UnitPrice : 0;
                Decimal qty = li.Quantity != null ? li.Quantity : 0;

                Integer lineTermMonths = lineTermMonthsInMemoryByLineId.containsKey(li.Id)
                    ? lineTermMonthsInMemoryByLineId.get(li.Id)
                    : lineTermMonthsInMemory(li);

                Integer monthsInOverlap = overlapMonthsInclusive(
                    li.StartDate,
                    li.EndDate,
                    seg.Start_Date__c,
                    seg.End_Date__c
                );
                if (monthsInOverlap <= 0) {
                    if (li.StartDate == null || li.EndDate == null) {
                        monthsInOverlap = monthsInSegment;
                    }
                }
                // Overlap cannot exceed the line's own subscription span (in memory from dates)
                if (monthsInOverlap > 0 && lineTermMonths > 0) {
                    monthsInOverlap = Math.min(monthsInOverlap, lineTermMonths);
                }

                Decimal revenueAmount;
                if (isAnnualTransProduct(productLabel)) {
                    revenueAmount = getBaseRate(li) * annualTrans;
                } else {
                    revenueAmount = unitPrice * qty * monthsInOverlap;
                }

                Line_Segment_Revenue__c lsr = new Line_Segment_Revenue__c(
                    Name = buildName(productLabel, seg.Start_Date__c),
                    Segment__c = seg.Id,
                    Quote_Line__c = li.Id,
                    Unit_Price__c = unitPrice,
                    Quantity__c = qty,
                    Segment_Revenue_Amount__c = revenueAmount.setScale(2, RoundingMode.HALF_UP)
                );
                toInsert.add(lsr);
            }
        }

        if (!toInsert.isEmpty()) {
            insert as user toInsert;
        }
        return toInsert.size();
    }

    private static void deleteExistingForSegments(Set<Id> segmentIds) {
        List<Line_Segment_Revenue__c> existing = [
            SELECT Id
            FROM Line_Segment_Revenue__c
            WHERE Segment__c IN :segmentIds
            WITH SECURITY_ENFORCED
        ];
        if (!existing.isEmpty()) {
            delete as user existing;
        }
    }

    private static Boolean isTermedLine(QuoteLineItem li) {
        return isTermedQuoteLine(li);
    }

    private static Decimal getBaseRate(QuoteLineItem li) {
        RateCard rc = [SELECT Id
                        FROM RateCard
                        WHERE Type = 'Base'].get(0);
                        
        RateCardEntry rce = [SELECT Rate, ProductSellingModel.PricingTermUnit
                                FROM RateCardEntry
                                WHERE (RateCardId = :rc.Id AND ProductId = :li.Product2Id AND ProductSellingModel.PricingTermUnit = 'Months')].get(0);
        
        return rce.Rate;
    }

    /** Exposed for LineSegmentRevenueTableController and other callers. */
    public static Boolean isTermedQuoteLine(QuoteLineItem li) {
        if (li == null) {
            return false;
        }
        if (li.StartDate == null || li.EndDate == null || li.EndDate < li.StartDate) {
            return false;
        }
        return lineTermMonthsInMemory(li) >= 1;
    }

    /**
     * Inclusive month count from QuoteLine StartDate–EndDate (in memory only; does not read SubscriptionTerm).
     */
    public static Integer lineTermMonthsInMemory(QuoteLineItem li) {
        if (li == null) {
            return 0;
        }
        return fullMonthsBetween(li.StartDate, li.EndDate);
    }

    private static String resolveProductLabel(QuoteLineItem li) {
        if (String.isNotBlank(li.RLM_ProductName__c)) {
            return li.RLM_ProductName__c.trim();
        }
        if (li.Product2 != null && String.isNotBlank(li.Product2.Name)) {
            return li.Product2.Name.trim();
        }
        return '';
    }

    private static Boolean isAnnualTransProduct(String productLabel) {
        if (String.isBlank(productLabel)) {
            return false;
        }
        String lower = productLabel.toLowerCase();
        for (String pattern : ANNUAL_TRANS_PRODUCT_PATTERNS) {
            if (lower.contains(pattern)) {
                return true;
            }
        }
        return false;
    }

    private static String buildName(String productLabel, Date segmentStart) {
        String yearPart = segmentStart != null ? String.valueOf(segmentStart.year()) : '';
        String base = String.isBlank(productLabel) ? 'Line' : productLabel;
        if (base.length() > 60) {
            base = base.substring(0, 57) + '...';
        }
        String combined = base + ' ' + yearPart;
        if (combined.length() > 80) {
            combined = combined.substring(0, 80);
        }
        return combined;
    }

    /**
     * Inclusive month count between two dates (min 1 when dates are valid and end >= start).
     * Returns 0 when dates are missing or invalid so callers can fall back (e.g. to segment months).
     */
    private static Integer fullMonthsBetween(Date startD, Date endD) {
        if (startD == null || endD == null || endD < startD) {
            return 0;
        }
        Integer months = startD.monthsBetween(endD) + 1;
        return Math.max(1, months);
    }

    /**
     * Months (inclusive) where quote line [lineStart, lineEnd] overlaps segment [segStart, segEnd].
     * Returns 0 if any bound is null or ranges do not overlap.
     */
    private static Integer overlapMonthsInclusive(Date lineStart, Date lineEnd, Date segStart, Date segEnd) {
        if (lineStart == null || lineEnd == null || segStart == null || segEnd == null) {
            return 0;
        }
        if (lineEnd < lineStart || segEnd < segStart) {
            return 0;
        }
        Date overlapStart = lineStart > segStart ? lineStart : segStart;
        Date overlapEnd = lineEnd < segEnd ? lineEnd : segEnd;
        if (overlapEnd < overlapStart) {
            return 0;
        }
        Integer months = overlapStart.monthsBetween(overlapEnd) + 1;
        return Math.max(1, months);
    }

    /**
     * Call from Line Segment Revenue LWC (or other Aura/LWC) to run the same logic as the invocable.
     */
    @AuraEnabled(cacheable=false)
    public static InvocableResult syncForSegmentLWC(Id segmentId) {
        InvocableRequest req = new InvocableRequest();
        req.segmentId = segmentId;
        List<InvocableResult> out = syncFromSegment(new List<InvocableRequest>{ req });
        return out.isEmpty() ? new InvocableResult() : out[0];
    }

    public class LineSegmentRevenueException extends Exception {}
}
