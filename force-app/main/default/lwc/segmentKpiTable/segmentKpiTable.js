import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSegmentsByQuote from '@salesforce/apex/SegmentKpiTableController.getSegmentsByQuote';
import saveSegmentKpis from '@salesforce/apex/SegmentKpiTableController.saveSegmentKpis';

export default class SegmentKpiTable extends LightningElement {
  @api recordId;
  @track segments = [];
  @track _edited = {}; // segmentId -> { dda, adoptionRate, ... }
  @track isLoading = true;
  @track error;
  @track isSaving = false;

  @wire(getSegmentsByQuote, { quoteId: '$recordId' })
  wiredSegments({ data, error }) {
    this.isLoading = false;
    if (error) {
      this.error = error.body?.message || String(error);
      this.segments = [];
      return;
    }
    this.error = undefined;
    this.segments = (data || []).map((s) => ({
      ...s,
      ddaDisplay: this._formatNumber(s.dda),
      activeUsersDisplay: this._formatNumber(s.activeUsers),
      adoptionRateDisplay: this._formatPercent(s.adoptionRate),
      transPctDisplay: this._formatPercent(s.transactionsAsPctOfDdas),
      avgMonthlyDisplay: this._formatNumber(s.avgMonthlyTransVolume),
      annualTransDisplay: this._formatNumber(s.annualTrans),
    }));
    this._edited = {};
  }

  get hasSegments() {
    return this.segments && this.segments.length > 0;
  }

  get segmentColumns() {
    return this.segments.map((s) => {
      const e = this._edited[s.id];
      const seg = e ? { ...s, ...e } : s;
      return {
        ...seg,
        ddaDisplay: this._formatNumber(seg.dda),
        activeUsersDisplay: this._formatNumber(seg.activeUsers),
        adoptionRateDisplay: this._formatPercent(seg.adoptionRate),
        transPctDisplay: this._formatPercent(seg.transactionsAsPctOfDdas),
        avgMonthlyDisplay: this._formatNumber(seg.avgMonthlyTransVolume),
        annualTransDisplay: this._formatNumber(seg.annualTrans),
      };
    });
  }

  get averageTotalColumn() {
    if (!this.segments.length) return null;
    const n = this.segments.length;
    const segs = this._effectiveSegments();
    let dda = 0, activeUsers = 0, adoptionRate = 0, transPct = 0, avgMonthly = 0, annualTrans = 0;
    segs.forEach((s) => {
      dda += Number(s.dda) || 0;
      activeUsers += Number(s.activeUsers) || 0;
      adoptionRate += Number(s.adoptionRate) || 0;
      transPct += Number(s.transactionsAsPctOfDdas) || 0;
      avgMonthly += Number(s.avgMonthlyTransVolume) || 0;
      annualTrans += Number(s.annualTrans) || 0;
    });
    return {
      ddaDisplay: this._formatNumber(dda / n),
      activeUsersDisplay: this._formatNumber(activeUsers / n),
      adoptionRateDisplay: this._formatPercent(adoptionRate / n),
      transPctDisplay: this._formatPercent(transPct / n),
      avgMonthlyDisplay: this._formatNumber(avgMonthly / n),
      annualTransDisplay: this._formatNumber(annualTrans),
    };
  }

  _effectiveSegments() {
    return this.segments.map((s) => {
      const e = this._edited[s.id];
      if (e) return { ...s, ...e };
      return s;
    });
  }

  get isDirty() {
    return Object.keys(this._edited).length > 0;
  }

  get isSaveDisabled() {
    return this.isSaving || !this.isDirty;
  }

  _formatNumber(val) {
    if (val == null || val === '') return '';
    const n = Number(val);
    if (isNaN(n)) return String(val);
    return n.toLocaleString('en-US', { maximumFractionDigits: 0 });
  }

  _formatPercent(val) {
    if (val == null || val === '') return '';
    const n = Number(val);
    if (isNaN(n)) return String(val);
    return n.toFixed(1) + '%';
  }

  _handleCellChange(segmentId, field, value) {
    if (!segmentId || !field) return;
    if (!this._edited[segmentId]) this._edited[segmentId] = {};
    const num = value === '' || value == null ? null : Number(value);
    this._edited[segmentId][field] = num;
    this._edited = { ...this._edited };
  }

  handleDdaChange(event) {
    const segmentId = event.target.dataset.segmentId;
    const val = event.target.value;
    this._handleCellChange(segmentId, 'dda', val);
  }
  handleNumberChange(event) {
    const segmentId = event.target.dataset.segmentId;
    const field = event.target.dataset.field;
    const val = event.target.value;
    this._handleCellChange(segmentId, field, val);
  }
  handlePercentChange(event) {
    const segmentId = event.target.dataset.segmentId;
    const field = event.target.dataset.field;
    const val = event.target.value;
    this._handleCellChange(segmentId, field, val);
  }

  async handleSave() {
    if (!this.recordId || !this.isDirty) return;
    const payload = this._effectiveSegments()
      .filter((s) => s.id)
      .map((s) => ({
        id: s.id,
        dda: s.dda,
        activeUsers: s.activeUsers,
        adoptionRate: s.adoptionRate,
        transactionsAsPctOfDdas: s.transactionsAsPctOfDdas,
        avgMonthlyTransVolume: s.avgMonthlyTransVolume,
        annualTrans: s.annualTrans,
      }));
    this.isSaving = true;
    try {
      await saveSegmentKpis({ quoteId: this.recordId, segmentPayloadJson: JSON.stringify(payload) });
      this._edited = {};
      this.dispatchEvent(new ShowToastEvent({ title: 'Saved', message: 'Segment KPIs updated.', variant: 'success' }));
      const data = await getSegmentsByQuote({ quoteId: this.recordId });
      this.segments = (data || []).map((s) => ({
        ...s,
        ddaDisplay: this._formatNumber(s.dda),
        activeUsersDisplay: this._formatNumber(s.activeUsers),
        adoptionRateDisplay: this._formatPercent(s.adoptionRate),
        transPctDisplay: this._formatPercent(s.transactionsAsPctOfDdas),
        avgMonthlyDisplay: this._formatNumber(s.avgMonthlyTransVolume),
        annualTransDisplay: this._formatNumber(s.annualTrans),
      }));
    } catch (e) {
      this.dispatchEvent(new ShowToastEvent({
        title: 'Error saving',
        message: e.body?.message || e.message || 'Unknown error',
        variant: 'error',
      }));
    } finally {
      this.isSaving = false;
    }
  }

  get noRecordId() {
    return !this.recordId;
  }
}
