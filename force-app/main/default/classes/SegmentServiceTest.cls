@IsTest
private class SegmentServiceTest {
    @IsTest
    static void createOrUpdateSegmentsForQuote_createsSegments() {
        Account acc = new Account(Name = 'Test Account', DDA_Share_Accounts_Count__c = 200000);
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
            OpportunityId = opp.Id,
            Proposed_Start_Date__c = Date.newInstance(2026, 1, 1),
            Term_Months__c = 24
        );
        insert q;

        SegmentService.InvocableRequest req = new SegmentService.InvocableRequest();
        req.quoteId = q.Id;

        Test.startTest();
        List<SegmentService.InvocableResult> results = SegmentService.createOrUpdateSegmentsForQuote(new List<SegmentService.InvocableRequest>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'One result');
        System.assertEquals(true, results[0].success, 'Should succeed');

        List<Segment__c> segments = [SELECT Id, Quote__c, Start_Date__c, End_Date__c, DDA__c, Adoption_Rate__c, Active_Users__c, Annual_Trans__c FROM Segment__c WHERE Quote__c = :q.Id ORDER BY Start_Date__c];
        System.assert(segments.size() >= 1, 'At least one segment created');
        if (!segments.isEmpty()) {
            System.assertEquals(3.5, segments[0].Adoption_Rate__c, 'First segment Adoption Rate 3.5%');
        }
    }

    @IsTest
    static void createOrUpdateSegmentsForQuote_nullQuoteId() {
        SegmentService.InvocableRequest req = new SegmentService.InvocableRequest();
        req.quoteId = null;

        Test.startTest();
        List<SegmentService.InvocableResult> results = SegmentService.createOrUpdateSegmentsForQuote(new List<SegmentService.InvocableRequest>{ req });
        Test.stopTest();

        System.assertEquals(false, results[0].success, 'Should fail');
    }

    @IsTest
    static void createOrUpdateSegmentsForQuote_noStartDate_returnsWithoutError() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        Opportunity opp = new Opportunity(Name = 'Test Opp', AccountId = acc.Id, StageName = 'Prospecting', CloseDate = Date.today().addMonths(1));
        insert opp;
        Quote q = new Quote(Name = 'Test Quote', OpportunityId = opp.Id);
        insert q;

        SegmentService.InvocableRequest req = new SegmentService.InvocableRequest();
        req.quoteId = q.Id;

        Test.startTest();
        List<SegmentService.InvocableResult> results = SegmentService.createOrUpdateSegmentsForQuote(new List<SegmentService.InvocableRequest>{ req });
        Test.stopTest();

        System.assertEquals(true, results[0].success, 'Should succeed without creating segments');
        System.assertEquals(0, [SELECT COUNT() FROM Segment__c WHERE Quote__c = :q.Id], 'No segments when no start date');
    }
}
