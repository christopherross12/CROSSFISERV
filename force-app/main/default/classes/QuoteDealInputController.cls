/**
 * Controller for Quote Deal Input LWC.
 * Per plan: all Quote/quote-level updates must use the Revenue Lifecycle Management
 * Connect API - Place Sales Transaction. This class is the server entry point;
 * replace the direct update below with invocation of that API (e.g. RevSalesTrxn_PlaceSalesTransactionExecutor
 * or the documented REST resource) when RLM is configured.
 * @see https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/connect_resources_place_sales_transaction.htm
 */
public with sharing class QuoteDealInputController {
    @AuraEnabled(cacheable=false)
    public static void saveQuoteDealFields(Id quoteId, Map<String, Object> fieldValues) {
        if (quoteId == null || fieldValues == null || fieldValues.isEmpty()) {
            throw new AuraHandledException('Quote Id and field values are required.');
        }

        // Load what we need to compute dependent fields (not DML).
        Quote q = [
            SELECT Id, StartDate, Term_Months__c
            FROM Quote
            WHERE Id = :quoteId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        Date startDateFinal;
        Integer termMonthsFinal;

        // Build the PATCH payload for the Place Sales Transaction graph.
        Map<String, Object> quotePatchFieldValues = new Map<String, Object>();
        for (String key : fieldValues.keySet()) {
            Object val = fieldValues.get(key);
            if (val == null) {
                continue;
            }

            if (key == 'StartDate') {
                String s = String.valueOf(val);
                // LWC sends YYYY-MM-DD, but be defensive if time is present.
                if (s != null && s.contains('T')) {
                    s = s.substring(0, s.indexOf('T'));
                }
                startDateFinal = Date.valueOf(s);
                // RLM graph payloads commonly expect YYYY-MM-DD strings for date fields.
                quotePatchFieldValues.put('StartDate', String.valueOf(startDateFinal));
            } else if (key == 'Overall_Deal_Type__c') {
                quotePatchFieldValues.put('Overall_Deal_Type__c', String.valueOf(val));
            } else if (key == 'Pan_Fiserv__c') {
                quotePatchFieldValues.put('Pan_Fiserv__c', String.valueOf(val));
            } else if (key == 'VAR_Takeaway__c') {
                Boolean b = (val instanceof Boolean) ? (Boolean)val : Boolean.valueOf(String.valueOf(val));
                quotePatchFieldValues.put('VAR_Takeaway__c', b);
            } else if (key == 'VAR_Name_Specify__c') {
                quotePatchFieldValues.put('VAR_Name_Specify__c', String.valueOf(val));
            } else if (key == 'CPI_Percent__c') {
                Decimal d = Decimal.valueOf(String.valueOf(val));
                // Convert 0-100 style input to 0-1 style percent expected by some orgs/schemas.
                if (d > 1) {
                    d = d / 100;
                }
                quotePatchFieldValues.put('CPI_Percent__c', d);
            } else if (key == 'Term_Months__c') {
                Decimal dec = Decimal.valueOf(String.valueOf(val));
                termMonthsFinal = dec.intValue();
                quotePatchFieldValues.put('Term_Months__c', termMonthsFinal);
            }
        }

        // Ensure we have enough to compute ExpirationDate (End Date).
        if (startDateFinal == null) {
            startDateFinal = q.StartDate;
        }
        if (termMonthsFinal == null) {
            // Term_Months__c is a Number field; coerce to Integer for month math.
            if (q.Term_Months__c == null) {
                termMonthsFinal = null;
            } else {
                termMonthsFinal = Decimal.valueOf(String.valueOf(q.Term_Months__c)).intValue();
            }
        }

        if (startDateFinal != null && termMonthsFinal != null) {
            // Mirror the LWC behavior:
            // JS does: end = addMonths(start, term); end = end - 1 (ms) => previous day.
            Date expirationDate = startDateFinal.addMonths(termMonthsFinal).addDays(-1);
            quotePatchFieldValues.put('ExpirationDate', String.valueOf(expirationDate));
        }

        if (quotePatchFieldValues.isEmpty()) {
            throw new AuraHandledException('No Quote fields to update.');
        }

        // RevSalesTrxn GraphRequest: patch the Quote header (quote-level fields)
        // using the Place Sales Transaction flow (no Salesforce DML).
        RevSalesTrxn.RecordResource quoteRecord =
            new RevSalesTrxn.RecordResource(Quote.getSobjectType(), 'PATCH', quoteId);
        quoteRecord.fieldValues = quotePatchFieldValues;

        RevSalesTrxn.RecordWithReferenceRequest quoteItemRecords =
            new RevSalesTrxn.RecordWithReferenceRequest('refQuote', quoteRecord);

        List<RevSalesTrxn.RecordWithReferenceRequest> listOfRecords =
            new List<RevSalesTrxn.RecordWithReferenceRequest>();
        listOfRecords.add(quoteItemRecords);

        RevSalesTrxn.GraphRequest graph = new RevSalesTrxn.GraphRequest('quoteDealInput', listOfRecords);

        RevSalesTrxn.PricingPreferenceEnum pricingPrefEnum = RevSalesTrxn.PricingPreferenceEnum.SYSTEM;
        RevSalesTrxn.ConfigurationExecutionEnum configurationExecutionEnum = RevSalesTrxn.ConfigurationExecutionEnum.SYSTEM;

        // There are multiple executor signatures. This mirrors the documented example signature.
        RevSalesTrxn.PlaceSalesTransactionResponse resp =
            RevSalesTrxn.PlaceSalesTransactionExecutor.execute(
                graph,
                pricingPrefEnum,
                configurationExecutionEnum,
                new RevSalesTrxn.ConfigurationOptionsInput(),
                null,
                null,
                null,
                null
            );

        if (resp == null) {
            throw new AuraHandledException('Failed to place sales transaction.');
        }
    }
}
