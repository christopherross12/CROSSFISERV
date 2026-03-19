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

        // Load what we need to compute dependent fields.
        // Note: We intentionally do NOT perform any DML updates here; RLM Place Sales Transaction will do the update.
        Quote q = [
            SELECT Id, StartDate, Term_Months__c
            FROM Quote
            WHERE Id = :quoteId
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];

        // These variables allow us to compute EndDate when the user changes StartDate and/or Term_Months__c.
        Date startDateFinal;
        Integer termMonthsFinal;

        // Build the PATCH payload for the Place Sales Transaction graph.
        // The connect-api sample request uses Quote header keys: StartDate and EndDate.
        Map<String, Object> quotePatchFieldValues = new Map<String, Object>();
        for (String key : fieldValues.keySet()) {
            Object val = fieldValues.get(key);
            if (val == null) {
                continue;
            }

            // The LWC sends StartDate as a YYYY-MM-DD string (sometimes including a time component).
            // We normalize it into a Date and then send it back as a string in the graph payload.
            if (key == 'StartDate') {
                String s = String.valueOf(val);
                // Be defensive if a time component is present.
                if (s != null && s.contains('T')) {
                    s = s.substring(0, s.indexOf('T'));
                }
                startDateFinal = Date.valueOf(s);
                // Connect API sample requests use ISO date strings.
                quotePatchFieldValues.put('StartDate', String.valueOf(startDateFinal));
            } else if (key == 'EndDate') {
                // If the UI provides EndDate, use it directly to ensure
                // the server writes the exact value the user sees.
                String s = String.valueOf(val);
                if (s != null && s.contains('T')) {
                    s = s.substring(0, s.indexOf('T'));
                }
                Date endDateFinal = Date.valueOf(s);
                quotePatchFieldValues.put('EndDate', String.valueOf(endDateFinal));
            } else if (key == 'Overall_Deal_Type__c') {
                quotePatchFieldValues.put('Overall_Deal_Type__c', String.valueOf(val));
            } else if (key == 'Pan_Fiserv__c') {
                quotePatchFieldValues.put('Pan_Fiserv__c', String.valueOf(val));
            } else if (key == 'VAR_Takeaway__c') {
                // The LWC provides a boolean for checkbox fields.
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
                // Number field -> integer month math.
                Decimal dec = Decimal.valueOf(String.valueOf(val));
                termMonthsFinal = dec.intValue();
                quotePatchFieldValues.put('Term_Months__c', termMonthsFinal);
            }
        }

        // Ensure we have enough to compute EndDate.
        // If the user didn't supply StartDate/Term_Months__c explicitly, fall back to existing Quote values.
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

        // Compute EndDate and send it under the key expected by the Place Sales Transaction API.
        // The LWC computes End Date as: (StartDate + Term_Months months) - 1 day.
        // If EndDate was provided explicitly by the client, don't recompute.
        if (!quotePatchFieldValues.containsKey('EndDate') && startDateFinal != null && termMonthsFinal != null) {
            // Mirror the LWC behavior:
            // JS does: end = addMonths(start, term); end = end - 1 (ms) => previous day.
            Date expirationDate = startDateFinal.addMonths(termMonthsFinal).addDays(-1);
            // The RLM Connect API sample uses "EndDate" as the request key.
            // (In this UI, we display that value as the End/Expiration date.)
            quotePatchFieldValues.put('EndDate', String.valueOf(expirationDate));
        }

        if (quotePatchFieldValues.isEmpty()) {
            throw new AuraHandledException('No Quote fields to update.');
        }

        // Create the RevSalesTrxn GraphRequest to PATCH the Quote header (quote-level fields).
        // This is the replacement for direct Salesforce DML.
        RevSalesTrxn.RecordResource quoteRecord =
            new RevSalesTrxn.RecordResource(Quote.getSobjectType(), 'PATCH', quoteId);
        quoteRecord.fieldValues = quotePatchFieldValues;

        // Wrap the record in a reference request, then add it to a graph.
        // (We only PATCH the quote header here; line-item updates would require additional records.)
        RevSalesTrxn.RecordWithReferenceRequest quoteItemRecords =
            new RevSalesTrxn.RecordWithReferenceRequest('refQuote', quoteRecord);

        List<RevSalesTrxn.RecordWithReferenceRequest> listOfRecords =
            new List<RevSalesTrxn.RecordWithReferenceRequest>();
        listOfRecords.add(quoteItemRecords);

        // Graph name: arbitrary identifier for tracing the request.
        RevSalesTrxn.GraphRequest graph = new RevSalesTrxn.GraphRequest('quoteDealInput', listOfRecords);

        // Use the executor in the "SYSTEM" mode (example signature from the docs).
        RevSalesTrxn.PricingPreferenceEnum pricingPrefEnum = RevSalesTrxn.PricingPreferenceEnum.SYSTEM;
        RevSalesTrxn.ConfigurationExecutionEnum configurationExecutionEnum = RevSalesTrxn.ConfigurationExecutionEnum.SYSTEM;

        // There are multiple executor signatures. This mirrors the documented example signature.
        RevSalesTrxn.PlaceSalesTransactionResponse resp;
        try {
            resp =
                RevSalesTrxn.PlaceSalesTransactionExecutor.execute(
                    graph,
                    pricingPrefEnum,
                    configurationExecutionEnum,
                    new RevSalesTrxn.ConfigurationOptionsInput(),
                    null
                );
        } catch (Exception ex) {
            // Surface executor errors to the LWC.
            throw new AuraHandledException('Failed to execute Place Sales Transaction: ' + ex.getMessage());
        }

        // Helpful for debugging in Apex logs (verify that the PATCH payload was accepted).
        System.debug('PlaceSalesTransactionResponse=' + resp);

        // If the executor didn't return a response object, treat it as a failure.
        if (resp == null) {
            throw new AuraHandledException('Failed to place sales transaction.');
        }
    }
}
