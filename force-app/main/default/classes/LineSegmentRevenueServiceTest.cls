@IsTest
private class LineSegmentRevenueServiceTest {
    @IsTest
    static void syncFromSegment_createsRows() {
        Account acc = new Account(Name = 'LSR Test Acc', DDA_Share_Accounts_Count__c = 1000);
        insert acc;
        Opportunity opp = new Opportunity(
            Name = 'LSR Test Opp',
            AccountId = acc.Id,
            StageName = 'Prospecting',
            CloseDate = Date.today().addMonths(1)
        );
        insert opp;

        Pricebook2 stdPb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
        Product2 prod = new Product2(Name = 'Request Money transaction, regardless of speed', IsActive = true);
        insert prod;
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = stdPb.Id,
            Product2Id = prod.Id,
            UnitPrice = 0.01,
            IsActive = true
        );
        insert pbe;

        Quote q = new Quote(
            Name = 'LSR Test Quote',
            OpportunityId = opp.Id,
            Pricebook2Id = stdPb.Id,
            Proposed_Start_Date__c = Date.newInstance(2026, 1, 1),
            Term_Months__c = 12
        );
        insert q;

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 10,
            UnitPrice = 2,
            StartDate = Date.newInstance(2026, 1, 1),
            EndDate = Date.newInstance(2026, 12, 31)
        );
        insert qli;

        Segment__c seg = new Segment__c(
            Quote__c = q.Id,
            Start_Date__c = Date.newInstance(2026, 1, 1),
            End_Date__c = Date.newInstance(2026, 12, 31),
            Annual_Trans__c = 5000
        );
        insert seg;

        LineSegmentRevenueService.InvocableRequest req = new LineSegmentRevenueService.InvocableRequest();
        req.segmentId = seg.Id;

        Test.startTest();
        List<LineSegmentRevenueService.InvocableResult> results = LineSegmentRevenueService.syncFromSegment(
            new List<LineSegmentRevenueService.InvocableRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success, results[0].message);
        System.assertEquals(1, results[0].recordsCreated);

        List<Line_Segment_Revenue__c> lsrs = [
            SELECT Id, Segment_Revenue_Amount__c, Unit_Price__c, Quantity__c
            FROM Line_Segment_Revenue__c
            WHERE Segment__c = :seg.Id AND Quote_Line__c = :qli.Id
        ];
        System.assertEquals(1, lsrs.size(), 'One LSR for segment × line');
        // Special product: UnitPrice * Annual_Trans = 2 * 5000 = 10000
        System.assertEquals(10000, lsrs[0].Segment_Revenue_Amount__c, 'Annual-trans product formula');
    }

    @IsTest
    static void syncFromSegment_nonSpecial_usesMonthsAndQty() {
        Account acc = new Account(Name = 'LSR Test Acc2');
        insert acc;
        Opportunity opp = new Opportunity(Name = 'LSR Test Opp2', AccountId = acc.Id, StageName = 'Prospecting', CloseDate = Date.today().addMonths(1));
        insert opp;

        Pricebook2 stdPb = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
        Product2 prod = new Product2(Name = 'Some Other Termed Product', IsActive = true);
        insert prod;
        PricebookEntry pbe = new PricebookEntry(Pricebook2Id = stdPb.Id, Product2Id = prod.Id, UnitPrice = 5, IsActive = true);
        insert pbe;

        Quote q = new Quote(Name = 'LSR Q2', OpportunityId = opp.Id, Pricebook2Id = stdPb.Id, Proposed_Start_Date__c = Date.newInstance(2026, 1, 1), Term_Months__c = 12);
        insert q;

        QuoteLineItem qli = new QuoteLineItem(
            QuoteId = q.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 3,
            UnitPrice = 4,
            StartDate = Date.newInstance(2026, 1, 1),
            EndDate = Date.newInstance(2026, 12, 31)
        );
        insert qli;

        Segment__c seg = new Segment__c(
            Quote__c = q.Id,
            Start_Date__c = Date.newInstance(2026, 1, 1),
            End_Date__c = Date.newInstance(2026, 12, 31),
            Annual_Trans__c = 100
        );
        insert seg;

        LineSegmentRevenueService.InvocableRequest req = new LineSegmentRevenueService.InvocableRequest();
        req.segmentId = seg.Id;

        Test.startTest();
        List<LineSegmentRevenueService.InvocableResult> results = LineSegmentRevenueService.syncFromSegment(
            new List<LineSegmentRevenueService.InvocableRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(true, results[0].success);
        Line_Segment_Revenue__c lsr = [
            SELECT Segment_Revenue_Amount__c
            FROM Line_Segment_Revenue__c
            WHERE Segment__c = :seg.Id
            LIMIT 1
        ];
        // 4 * 3 * 12 months = 144
        System.assertEquals(144, lsr.Segment_Revenue_Amount__c);
    }

    @IsTest
    static void syncFromSegment_nullSegment_throws() {
        LineSegmentRevenueService.InvocableRequest req = new LineSegmentRevenueService.InvocableRequest();
        req.segmentId = null;

        Test.startTest();
        List<LineSegmentRevenueService.InvocableResult> results = LineSegmentRevenueService.syncFromSegment(
            new List<LineSegmentRevenueService.InvocableRequest>{ req }
        );
        Test.stopTest();

        System.assertEquals(false, results[0].success);
    }
}
