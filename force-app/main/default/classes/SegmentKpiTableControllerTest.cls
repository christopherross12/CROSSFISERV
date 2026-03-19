@IsTest
private class SegmentKpiTableControllerTest {
    @IsTest
    static void getSegmentsByQuote_emptyWhenNoQuote() {
        List<SegmentKpiTableController.SegmentDto> result = SegmentKpiTableController.getSegmentsByQuote(null);
        System.assertEquals(0, result.size(), 'Should return empty list for null quote');
    }

    @IsTest
    static void getSegmentsByQuote_returnsSegments() {
        Account acc = new Account(Name = 'Test Account', DDA_Share_Accounts_Count__c = 100000);
        insert acc;
        Opportunity opp = new Opportunity(Name = 'Test Opp', AccountId = acc.Id, StageName = 'Prospecting', CloseDate = Date.today().addMonths(1));
        insert opp;
        Quote q = new Quote(Name = 'Test Quote', OpportunityId = opp.Id, Proposed_Start_Date__c = Date.newInstance(2026, 1, 1), Term_Months__c = 12);
        insert q;
        Segment__c seg = new Segment__c(
            Quote__c = q.Id,
            Start_Date__c = Date.newInstance(2026, 1, 1),
            End_Date__c = Date.newInstance(2026, 12, 31),
            DDA__c = 100000,
            Adoption_Rate__c = 3.5,
            Active_Users__c = 3500,
            Annual_Trans__c = 12000
        );
        insert seg;

        Test.startTest();
        List<SegmentKpiTableController.SegmentDto> result = SegmentKpiTableController.getSegmentsByQuote(q.Id);
        Test.stopTest();

        System.assertEquals(1, result.size(), 'One segment');
        System.assertEquals('2026', result[0].name, 'Name is year');
        System.assertEquals(100000, result[0].dda, 'DDA matches');
    }

    @IsTest
    static void saveSegmentKpis_updatesSegments() {
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        Opportunity opp = new Opportunity(Name = 'Test Opp', AccountId = acc.Id, StageName = 'Prospecting', CloseDate = Date.today().addMonths(1));
        insert opp;
        Quote q = new Quote(Name = 'Test Quote', OpportunityId = opp.Id, Proposed_Start_Date__c = Date.newInstance(2026, 1, 1), Term_Months__c = 12);
        insert q;
        Segment__c seg = new Segment__c(Quote__c = q.Id, Start_Date__c = Date.newInstance(2026, 1, 1), End_Date__c = Date.newInstance(2026, 12, 31), DDA__c = 50000);
        insert seg;

        List<Object> payloadList = new List<Object>();
        Map<String, Object> p = new Map<String, Object>();
        p.put('id', seg.Id);
        p.put('dda', 60000);
        p.put('activeUsers', 2000);
        p.put('adoptionRate', 4);
        p.put('transactionsAsPctOfDdas', 2.5);
        p.put('avgMonthlyTransVolume', 1500);
        p.put('annualTrans', 18000);
        payloadList.add(p);

        Test.startTest();
        SegmentKpiTableController.saveSegmentKpis(q.Id, JSON.serialize(payloadList));
        Test.stopTest();

        Segment__c updated = [SELECT Id, DDA__c, Active_Users__c FROM Segment__c WHERE Id = :seg.Id];
        System.assertEquals(60000, updated.DDA__c, 'DDA updated');
    }

    @IsTest
    static void saveSegmentKpis_throwsWhenQuoteIdNull() {
        try {
            SegmentKpiTableController.saveSegmentKpis(null, '[]');
            System.assert(false, 'Expected exception');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('required'), 'Should require quote Id');
        }
    }
}
