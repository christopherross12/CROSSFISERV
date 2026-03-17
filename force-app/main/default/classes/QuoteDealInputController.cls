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
        Quote q = [SELECT Id FROM Quote WHERE Id = :quoteId WITH SECURITY_ENFORCED LIMIT 1];
        for (String key : fieldValues.keySet()) {
            Object val = fieldValues.get(key);
            if (val == null) { continue; }
            if (key == 'Proposed_Start_Date__c') {
                q.put('Proposed_Start_Date__c', val);
            } else if (key == 'Overall_Deal_Type__c') {
                q.put('Overall_Deal_Type__c', String.valueOf(val));
            } else if (key == 'Pan_Fiserv__c') {
                q.put('Pan_Fiserv__c', String.valueOf(val));
            } else if (key == 'VAR_Takeaway__c') {
                q.put('VAR_Takeaway__c', Boolean.valueOf(val));
            } else if (key == 'VAR_Name_Specify__c') {
                q.put('VAR_Name_Specify__c', String.valueOf(val));
            } else if (key == 'CPI_Percent__c') {
                Decimal d = Decimal.valueOf(String.valueOf(val));
                if (d > 1) { d = d / 100; }
                q.put('CPI_Percent__c', d);
            } else if (key == 'Term_Months__c') {
                q.put('Term_Months__c', Integer.valueOf(val));
            }
        }
        update as user q;
    }
}
