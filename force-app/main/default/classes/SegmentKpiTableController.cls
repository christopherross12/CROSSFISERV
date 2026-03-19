/**
 * Controller for Segment KPI Table LWC.
 * Returns Segment records for a Quote and saves KPI field updates.
 */
public with sharing class SegmentKpiTableController {
    // Read-only query used by the LWC via `@wire`, so it must be cacheable.
    @AuraEnabled(cacheable=true)
    public static List<SegmentDto> getSegmentsByQuote(Id quoteId) {
        if (quoteId == null) {
            return new List<SegmentDto>();
        }
        List<Segment__c> segments = [
            SELECT Id, Name, Start_Date__c, End_Date__c,
                DDA__c, Active_Users__c, Adoption_Rate__c, Transactions_as_Pct_of_DDAs__c,
                Avg_Monthly_Trans_Volume__c, Annual_Trans__c
            FROM Segment__c
            WHERE Quote__c = :quoteId
            WITH SECURITY_ENFORCED
            ORDER BY Start_Date__c ASC
        ];
        List<SegmentDto> dtos = new List<SegmentDto>();
        for (Segment__c s : segments) {
            SegmentDto dto = new SegmentDto();
            dto.id = s.Id;
            dto.name = segmentDisplayName(s.Start_Date__c, s.End_Date__c);
            dto.startDate = s.Start_Date__c != null ? s.Start_Date__c.format() : '';
            dto.endDate = s.End_Date__c != null ? s.End_Date__c.format() : '';
            dto.dda = s.DDA__c;
            dto.activeUsers = s.Active_Users__c;
            dto.adoptionRate = s.Adoption_Rate__c;
            dto.transactionsAsPctOfDdas = s.Transactions_as_Pct_of_DDAs__c;
            dto.avgMonthlyTransVolume = s.Avg_Monthly_Trans_Volume__c;
            dto.annualTrans = s.Annual_Trans__c;
            dtos.add(dto);
        }
        return dtos;
    }

    private static String segmentDisplayName(Date startD, Date endD) {
        if (startD == null) return '';
        return String.valueOf(startD.year());
    }

    @AuraEnabled(cacheable=false)
    public static void saveSegmentKpis(Id quoteId, String segmentPayloadJson) {
        if (quoteId == null || String.isBlank(segmentPayloadJson)) {
            throw new AuraHandledException('Quote Id and segment data are required.');
        }
        List<SegmentKpiPayload> payloads = (List<SegmentKpiPayload>) JSON.deserialize(segmentPayloadJson, List<SegmentKpiPayload>.class);
        List<Segment__c> toUpdate = new List<Segment__c>();
        Set<Id> allowedIds = new Set<Id>();
        for (Segment__c s : [SELECT Id FROM Segment__c WHERE Quote__c = :quoteId WITH SECURITY_ENFORCED]) {
            allowedIds.add(s.Id);
        }
        for (SegmentKpiPayload p : payloads) {
            if (p.id == null || !allowedIds.contains(p.id)) continue;
            Segment__c seg = new Segment__c(
                Id = p.id,
                DDA__c = p.dda,
                Active_Users__c = p.activeUsers,
                Adoption_Rate__c = p.adoptionRate,
                Transactions_as_Pct_of_DDAs__c = p.transactionsAsPctOfDdas,
                Avg_Monthly_Trans_Volume__c = p.avgMonthlyTransVolume,
                Annual_Trans__c = p.annualTrans
            );
            toUpdate.add(seg);
        }
        if (!toUpdate.isEmpty()) {
            update as user toUpdate;
        }
    }

    public class SegmentDto {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String startDate;
        @AuraEnabled public String endDate;
        @AuraEnabled public Decimal dda;
        @AuraEnabled public Decimal activeUsers;
        @AuraEnabled public Decimal adoptionRate;
        @AuraEnabled public Decimal transactionsAsPctOfDdas;
        @AuraEnabled public Decimal avgMonthlyTransVolume;
        @AuraEnabled public Decimal annualTrans;
    }

    public class SegmentKpiPayload {
        public Id id;
        public Decimal dda;
        public Decimal activeUsers;
        public Decimal adoptionRate;
        public Decimal transactionsAsPctOfDdas;
        public Decimal avgMonthlyTransVolume;
        public Decimal annualTrans;
    }
}
