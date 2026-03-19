/**
 * Invocable Apex: creates or updates Segment records for a Quote based on
 * Quote Start/End dates. Called by a Flow triggered by QuoteSaveEvent.
 * Sets DDA, Adoption Rate, Active Users, Transactions as % of DDAs,
 * Avg Monthly Trans Volume, and Annual Trans per plan.
 */
public with sharing class SegmentService {
    private static final List<Decimal> TRANS_PCT_DEFAULTS = new List<Decimal>{
        1.4, 4.1, 8.0, 11.9, 15.3, 7.3
    };

    @InvocableMethod(
        label='Create or Update Segments for Quote'
        description='Creates or updates Segment records for the given Quote based on Start/End dates. Call from Flow on QuoteSaveEvent.'
        category='Segment'
    )
    public static List<InvocableResult> createOrUpdateSegmentsForQuote(List<InvocableRequest> requests) {
        List<InvocableResult> results = new List<InvocableResult>();
        for (InvocableRequest req : requests) {
            InvocableResult res = new InvocableResult();
            try {
                doCreateOrUpdate(req.quoteId);
                res.success = true;
                res.message = 'Segments created or updated successfully.';
            } catch (Exception e) {
                res.success = false;
                res.message = e.getMessage();
                res.errorMessage = e.getStackTraceString();
            }
            results.add(res);
        }
        return results;
    }

    public class InvocableRequest {
        @InvocableVariable(required=true label='Quote Id' description='Id of the Quote')
        public Id quoteId;
    }

    public class InvocableResult {
        @InvocableVariable(label='Success' description='True if the operation succeeded')
        public Boolean success;
        @InvocableVariable(label='Message' description='Success or error message')
        public String message;
        @InvocableVariable(label='Error details' description='Stack trace if failed')
        public String errorMessage;
    }

    private static void doCreateOrUpdate(Id quoteIdParam) {
        if (quoteIdParam == null) {
            throw new SegmentServiceException('Quote Id is required.');
        }

        Quote q = [
            SELECT Id, Proposed_Start_Date__c, Term_Months__c, ExpirationDate, DDA_Share_Accounts_Count__c
            FROM Quote
            WHERE Id = :quoteIdParam
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        Date quoteStart = q.Proposed_Start_Date__c;
        if (quoteStart == null) {
            return;
        }

        Date quoteEnd = q.ExpirationDate;
        if (quoteEnd == null && q.Term_Months__c != null) {
            quoteEnd = addMonths(quoteStart, q.Term_Months__c.intValue());
        }
        if (quoteEnd == null || quoteEnd < quoteStart) {
            return;
        }

        Decimal ddaFromQuote = q.DDA_Share_Accounts_Count__c != null ? q.DDA_Share_Accounts_Count__c : 0;

        List<SegmentRange> ranges = computeSegmentRanges(quoteStart, quoteEnd);
        List<Segment__c> existing = [
            SELECT Id, Start_Date__c, End_Date__c, Quote__c,
                DDA__c, Adoption_Rate__c, Active_Users__c, Transactions_as_Pct_of_DDAs__c,
                Avg_Monthly_Trans_Volume__c, Annual_Trans__c
            FROM Segment__c
            WHERE Quote__c = :quoteIdParam
            WITH SECURITY_ENFORCED
        ];

        Map<String, Segment__c> existingByKey = new Map<String, Segment__c>();
        for (Segment__c s : existing) {
            String key = String.valueOf(s.Start_Date__c) + '_' + String.valueOf(s.End_Date__c);
            existingByKey.put(key, s);
        }

        List<Segment__c> toUpsert = new List<Segment__c>();
        Set<Id> keepIds = new Set<Id>();
        Integer position = 0;

        for (SegmentRange r : ranges) {
            String key = String.valueOf(r.startDate) + '_' + String.valueOf(r.endDate);
            Segment__c seg = existingByKey.get(key);
            if (seg == null) {
                seg = new Segment__c(
                    Quote__c = quoteIdParam,
                    Start_Date__c = r.startDate,
                    End_Date__c = r.endDate
                );
            }
            keepIds.add(seg.Id);

            Decimal adoptionRate = 3.5 + (position * 1.5);
            seg.Adoption_Rate__c = adoptionRate;
            seg.DDA__c = ddaFromQuote;
            seg.Active_Users__c = (ddaFromQuote * adoptionRate / 100).setScale(0, RoundingMode.HALF_UP);

            Decimal transPct = position < TRANS_PCT_DEFAULTS.size()
                ? TRANS_PCT_DEFAULTS[position]
                : TRANS_PCT_DEFAULTS[TRANS_PCT_DEFAULTS.size() - 1];
            seg.Transactions_as_Pct_of_DDAs__c = transPct;
            seg.Avg_Monthly_Trans_Volume__c = (ddaFromQuote * transPct / 100).setScale(0, RoundingMode.HALF_UP);

            Integer fullMonths = fullMonthsBetween(r.startDate, r.endDate);
            seg.Annual_Trans__c = (seg.Avg_Monthly_Trans_Volume__c * fullMonths).setScale(0, RoundingMode.HALF_UP);

            toUpsert.add(seg);
            position++;
        }

        if (!toUpsert.isEmpty()) {
            upsert toUpsert;
        }

        List<Segment__c> toDelete = new List<Segment__c>();
        for (Segment__c s : existing) {
            if (!keepIds.contains(s.Id)) {
                toDelete.add(s);
            }
        }
        if (!toDelete.isEmpty()) {
            delete toDelete;
        }
    }

    private static List<SegmentRange> computeSegmentRanges(Date quoteStart, Date quoteEnd) {
        List<SegmentRange> ranges = new List<SegmentRange>();
        Integer startYear = quoteStart.year();
        Integer endYear = quoteEnd.year();

        if (startYear == endYear) {
            ranges.add(new SegmentRange(quoteStart, quoteEnd));
            return ranges;
        }

        Date firstEnd = Date.newInstance(startYear, 12, 31);
        if (quoteEnd < firstEnd) {
            firstEnd = quoteEnd;
        }
        ranges.add(new SegmentRange(quoteStart, firstEnd));

        for (Integer y = startYear + 1; y < endYear; y++) {
            ranges.add(new SegmentRange(
                Date.newInstance(y, 1, 1),
                Date.newInstance(y, 12, 31)
            ));
        }

        Date lastStart = Date.newInstance(endYear, 1, 1);
        if (lastStart < quoteEnd || ranges.isEmpty()) {
            ranges.add(new SegmentRange(lastStart, quoteEnd));
        }

        return ranges;
    }

    private static Date addMonths(Date d, Integer months) {
        return d.addMonths(months);
    }

    private static Integer fullMonthsBetween(Date startD, Date endD) {
        if (startD == null || endD == null || endD < startD) {
            return 0;
        }
        Integer months = startD.monthsBetween(endD) + 1;
        return Math.max(1, months);
    }

    private class SegmentRange {
        Date startDate;
        Date endDate;
        SegmentRange(Date s, Date e) {
            startDate = s;
            endDate = e;
        }
    }

    public class SegmentServiceException extends Exception {}
}
