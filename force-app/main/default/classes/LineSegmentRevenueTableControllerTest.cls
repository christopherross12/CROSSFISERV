@IsTest
private class LineSegmentRevenueTableControllerTest {
    @IsTest
    static void getRecurringFeeGrid_nullQuote_returnsEmpty() {
        LineSegmentRevenueTableController.RecurringFeeGrid g = LineSegmentRevenueTableController.getRecurringFeeGrid(null);
        System.assertNotEquals(null, g);
        System.assertEquals(0, g.segmentColumns.size());
        System.assertEquals(0, g.rows.size());
    }

    @IsTest
    static void syncLineSegmentRevenueForQuote_nullQuote() {
        LineSegmentRevenueTableController.SyncResult r = LineSegmentRevenueTableController.syncLineSegmentRevenueForQuote(null);
        System.assertEquals(false, r.success);
    }
}
