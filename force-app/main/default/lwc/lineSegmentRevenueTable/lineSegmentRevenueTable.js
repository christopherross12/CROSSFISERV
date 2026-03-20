import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRecurringFeeGrid from '@salesforce/apex/LineSegmentRevenueTableController.getRecurringFeeGrid';
import syncLineSegmentRevenueForQuote from '@salesforce/apex/LineSegmentRevenueTableController.syncLineSegmentRevenueForQuote';

export default class LineSegmentRevenueTable extends LightningElement {
  @api recordId;

  @track grid = null;
  @track isLoading = true;
  @track isSyncing = false;
  @track error;

  connectedCallback() {
    this.loadGrid();
  }

  async loadGrid() {
    if (!this.recordId) {
      this.isLoading = false;
      this.grid = null;
      return;
    }
    this.isLoading = true;
    this.error = undefined;
    try {
      const raw = await getRecurringFeeGrid({ quoteId: this.recordId });
      this.grid = this.decorateGrid(raw);
    } catch (e) {
      this.error = e.body?.message || e.message || 'Failed to load recurring fees.';
      this.grid = null;
    } finally {
      this.isLoading = false;
    }
  }

  decorateGrid(raw) {
    if (!raw) return null;
    const cols = raw.segmentColumns || [];
    const rows = (raw.rows || []).map((r) => {
      const cells = (r.segmentAmounts || []).map((amt, idx) => ({
        key: `${r.quoteLineId}_${idx}`,
        display: this.formatMoney(amt),
      }));
      return {
        quoteLineId: r.quoteLineId,
        productName: r.productName,
        unitPriceDisplay: this.formatMoney(r.unitPrice),
        cells,
        rowTotalDisplay: this.formatMoney(r.rowTotal),
      };
    });
    const columnTotals = (raw.columnTotals || []).map((amt, idx) => ({
      key: `coltotal_${idx}`,
      display: this.formatMoney(amt),
    }));
    let grandTotal = 0;
    (raw.rows || []).forEach((r) => {
      grandTotal += Number(r.rowTotal) || 0;
    });
    return {
      segmentColumns: cols,
      rows,
      columnTotals,
      grandTotalDisplay: this.formatMoney(grandTotal),
      hasRows: rows.length > 0,
      hasSegments: cols.length > 0,
    };
  }

  /**
   * Full USD with grouping (e.g. $48,000). Whole dollars omit cents; fractional amounts show up to 2 decimals.
   */
  formatMoney(value) {
    if (value == null || value === '') return '';
    const n = Number(value);
    if (Number.isNaN(n)) return String(value);
    const cents = Math.round(Math.abs(n * 100)) % 100;
    const hasCents = cents !== 0;
    return new Intl.NumberFormat('en-US', {
      style: 'currency',
      currency: 'USD',
      minimumFractionDigits: hasCents ? 2 : 0,
      maximumFractionDigits: hasCents ? 2 : 0,
    }).format(n);
  }

  get showTable() {
    return this.grid && this.grid.hasSegments && this.grid.hasRows;
  }

  get showEmpty() {
    return this.grid && this.grid.hasSegments && !this.grid.hasRows;
  }

  get showNoSegments() {
    return this.grid && !this.grid.hasSegments;
  }

  async handleSync() {
    if (!this.recordId) return;
    this.isSyncing = true;
    try {
      const res = await syncLineSegmentRevenueForQuote({ quoteId: this.recordId });
      if (res.success) {
        this.dispatchEvent(
          new ShowToastEvent({
            title: 'Line segment revenue updated',
            message: res.message || 'Sync completed.',
            variant: 'success',
          }),
        );
        await this.loadGrid();
      } else {
        this.dispatchEvent(
          new ShowToastEvent({
            title: 'Sync failed',
            message: res.message || 'Unknown error',
            variant: 'error',
          }),
        );
      }
    } catch (e) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: 'Sync failed',
          message: e.body?.message || e.message || 'Unknown error',
          variant: 'error',
        }),
      );
    } finally {
      this.isSyncing = false;
    }
  }

  handleRefresh() {
    return this.loadGrid();
  }

  get noRecordId() {
    return !this.recordId;
  }
}
