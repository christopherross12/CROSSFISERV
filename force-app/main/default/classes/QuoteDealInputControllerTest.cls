@IsTest
private class QuoteDealInputControllerTest {
  @IsTest
  static void saveQuoteDealFields_success() {
    Account acc = new Account(Name = 'Test Account');
    insert acc;
    Opportunity opp = new Opportunity(
      Name = 'Test Opp',
      AccountId = acc.Id,
      StageName = 'Prospecting',
      CloseDate = Date.today().addMonths(1)
    );
    insert opp;
    Quote q = new Quote(
      Name = 'Test Quote',
      OpportunityId = opp.Id
    );
    insert q;

    Map<String, Object> fieldValues = new Map<String, Object>{
      'Overall_Deal_Type__c' => 'New',
      'Pan_Fiserv__c' => 'Yes',
      'VAR_Takeaway__c' => false,
      'CPI_Percent__c' => 3,
      'Term_Months__c' => 60
    };

    Test.startTest();
    QuoteDealInputController.saveQuoteDealFields(q.Id, fieldValues);
    Test.stopTest();

    Quote updated = [SELECT Id, Overall_Deal_Type__c, Pan_Fiserv__c, VAR_Takeaway__c, CPI_Percent__c, Term_Months__c FROM Quote WHERE Id = :q.Id];
    System.assertEquals('New', updated.Overall_Deal_Type__c, 'Overall Deal Type should be New');
    System.assertEquals('Yes', updated.Pan_Fiserv__c, 'Pan Fiserv should be Yes');
    System.assertEquals(false, updated.VAR_Takeaway__c, 'VAR Takeaway should be false');
    System.assertEquals(0.03, updated.CPI_Percent__c, 'CPI Percent should be 0.03');
    System.assertEquals(60, updated.Term_Months__c, 'Term Months should be 60');
  }

  @IsTest
  static void saveQuoteDealFields_throwsWhenQuoteIdNull() {
    try {
      QuoteDealInputController.saveQuoteDealFields(null, new Map<String, Object>{ 'Overall_Deal_Type__c' => 'New' });
      System.assert(false, 'Expected AuraHandledException');
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('required'), 'Should require Quote Id');
    }
  }

  @IsTest
  static void saveQuoteDealFields_throwsWhenFieldValuesNull() {
    Account acc = new Account(Name = 'Test Account');
    insert acc;
    Opportunity opp = new Opportunity(Name = 'Test Opp', AccountId = acc.Id, StageName = 'Prospecting', CloseDate = Date.today().addMonths(1));
    insert opp;
    Quote q = new Quote(Name = 'Test Quote', OpportunityId = opp.Id);
    insert q;

    try {
      QuoteDealInputController.saveQuoteDealFields(q.Id, null);
      System.assert(false, 'Expected AuraHandledException');
    } catch (AuraHandledException e) {
      System.assert(e.getMessage().contains('required'), 'Should require field values');
    }
  }
}
