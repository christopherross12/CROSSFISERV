import { LightningElement, api, wire, track } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import saveQuoteDealFields from '@salesforce/apex/QuoteDealInputController.saveQuoteDealFields';

import QUOTE_OPPORTUNITY_ID from '@salesforce/schema/Quote.OpportunityId';
import QUOTE_PROPOSED_START_DATE from '@salesforce/schema/Quote.StartDate';
import QUOTE_FI_NAME from '@salesforce/schema/Quote.FI_Name__c';
import QUOTE_FI_LOCATION from '@salesforce/schema/Quote.FI_Location__c';
import QUOTE_FBPS_DIRECT_FINTECH from '@salesforce/schema/Quote.FBPS_Direct_Fintech__c';
import QUOTE_TYPE_OF_FI from '@salesforce/schema/Quote.Type_of_FI__c';
import QUOTE_ASSET_SIZE_M from '@salesforce/schema/Quote.Asset_Size_M__c';
import QUOTE_DDA_SHARE_ACCOUNTS_COUNT from '@salesforce/schema/Quote.DDA_Share_Accounts_Count__c';
import QUOTE_SMALL_BUSINESS_DDAS from '@salesforce/schema/Quote.Small_Business_DDAs__c';
import QUOTE_OLB_USERS from '@salesforce/schema/Quote.OLB_Business_Retail_Users__c';
import QUOTE_OVERALL_DEAL_TYPE from '@salesforce/schema/Quote.Overall_Deal_Type__c';
import QUOTE_PAN_FISERV from '@salesforce/schema/Quote.Pan_Fiserv__c';
import QUOTE_VAR_TAKEAWAY from '@salesforce/schema/Quote.VAR_Takeaway__c';
import QUOTE_VAR_NAME_SPECIFY from '@salesforce/schema/Quote.VAR_Name_Specify__c';
import QUOTE_CPI_PERCENT from '@salesforce/schema/Quote.CPI_Percent__c';
import QUOTE_TERM_MONTHS from '@salesforce/schema/Quote.Term_Months__c';

// Only standard field – ensures getRecord succeeds even if custom fields are missing or not accessible
const QUOTE_REQUIRED_FIELDS = [QUOTE_OPPORTUNITY_ID];

// Optional fields let the component render in orgs where some fields
// might not be visible yet; missing optional fields are handled defensively.
const QUOTE_OPTIONAL_FIELDS = [
  QUOTE_PROPOSED_START_DATE,
  QUOTE_FI_NAME,
  QUOTE_FI_LOCATION,
  QUOTE_FBPS_DIRECT_FINTECH,
  QUOTE_TYPE_OF_FI,
  QUOTE_ASSET_SIZE_M,
  QUOTE_DDA_SHARE_ACCOUNTS_COUNT,
  QUOTE_SMALL_BUSINESS_DDAS,
  QUOTE_OLB_USERS,
  QUOTE_OVERALL_DEAL_TYPE,
  QUOTE_PAN_FISERV,
  QUOTE_VAR_TAKEAWAY,
  QUOTE_VAR_NAME_SPECIFY,
  QUOTE_CPI_PERCENT,
  QUOTE_TERM_MONTHS,
];


// UI option lists used by comboboxes/selection components.
const OVERALL_DEAL_TYPE_OPTIONS = [
  { label: 'New', value: 'New' },
  { label: 'Renewal', value: 'Renewal' },
  { label: 'Other', value: 'Other' },
];

const PAN_FISERV_OPTIONS = [
  { label: 'Select Yes or No', value: '' },
  { label: 'Yes', value: 'Yes' },
  { label: 'No', value: 'No' },
];

// Helpers for End Date calculation/display.
function pad2(n) {
  return String(n).padStart(2, '0');
}

function parseIsoDateToUtc(iso) {
  // Expects `YYYY-MM-DD`. Returns a Date in UTC at midnight.
  if (!iso || typeof iso !== 'string') return null;
  const parts = iso.split('-').map(Number);
  if (parts.length !== 3 || parts.some(v => Number.isNaN(v))) return null;
  const [y, m, d] = parts;
  return new Date(Date.UTC(y, m - 1, d));
}

function computeEndDateIsoFromStartIso(startIso, termMonths) {
  // The app’s end date rule mirrors the earlier LWC behavior:
  // EndDate = (StartDate + Term_Months months) - 1 day
  const startUtc = parseIsoDateToUtc(startIso);
  const months = Number(termMonths);
  if (!startUtc || Number.isNaN(months)) return '';

  const endUtc = new Date(startUtc.getTime());
  endUtc.setUTCMonth(endUtc.getUTCMonth() + months);
  endUtc.setUTCDate(endUtc.getUTCDate() - 1);

  const y = endUtc.getUTCFullYear();
  const m = pad2(endUtc.getUTCMonth() + 1);
  const d = pad2(endUtc.getUTCDate());
  return `${y}-${m}-${d}`;
}

function formatMonthDayYearFromIso(iso) {
  if (!iso) return '';
  const dt = parseIsoDateToUtc(iso);
  if (!dt) return '';

  // Required output format: "Month Day, Year" (e.g., "March 19, 2026").
  try {
    return new Intl.DateTimeFormat('en-US', {
      month: 'long',
      day: 'numeric',
      year: 'numeric',
    }).format(dt);
  } catch (e) {
    // Minimal fallback if Intl is unavailable.
    const monthNames = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    const monthName = monthNames[dt.getUTCMonth()] || '';
    return `${monthName} ${dt.getUTCDate()}, ${dt.getUTCFullYear()}`;
  }
}

export default class QuoteDealInput extends LightningElement {
  @api recordId;

  // UI state backing variables (tracked so template updates are reactive).
  @track _overallDealType = '';
  @track _panFiserv = '';
  @track _varTakeaway = false;
  @track _varNameSpecify = '';
  @track _cpiPercent = '';
  @track _termMonths = '';
  @track _startDate = '';
  @track _endDateDisplay = '';
  @track _isSaving = false;
  @track _editValues = {};
  _record = null;
  _error = null;

  // Load Quote record for display + initial values for editable fields.
  @wire(getRecord, {
    recordId: '$recordId',
    fields: QUOTE_REQUIRED_FIELDS,
    optionalFields: QUOTE_OPTIONAL_FIELDS,
  })
  wiredQuote({ error, data }) {
    this._error = null;
    if (error) {
      this._error = error;
      return;
    }
    if (!this.recordId || !data) {
      return;
    }
    try {
      this._record = data;
      this._overallDealType = getFieldValue(data, QUOTE_OVERALL_DEAL_TYPE) ?? '';
      this._panFiserv = getFieldValue(data, QUOTE_PAN_FISERV) ?? '';
      this._varTakeaway = getFieldValue(data, QUOTE_VAR_TAKEAWAY) === true;
      this._varNameSpecify = getFieldValue(data, QUOTE_VAR_NAME_SPECIFY) ?? '';

      // CPI and Term can be empty strings depending on org data.
      // We keep them as-is for UI formatting and let Apex coerce on save.
        const cpi = getFieldValue(data, QUOTE_CPI_PERCENT);
        const term = getFieldValue(data, QUOTE_TERM_MONTHS);
        this._cpiPercent = cpi != null && cpi !== '' ? cpi : '';
        this._termMonths = term != null && term !== '' ? term : '';
      const startVal = getFieldValue(data, QUOTE_PROPOSED_START_DATE);
      this._startDate = startVal ? (typeof startVal === 'string' && startVal.indexOf('T') > -1 ? startVal.split('T')[0] : String(startVal)) : '';
      this._endDateDisplay = this._computeEndDate();
    } catch (e) {
      this._error = { message: e.message || 'Failed to load quote data.' };
    }
  }

  // Safe accessor for fields: if a field isn't present in the wire payload,
  // uiRecordApi access can throw; we convert that into `null`.
  _safeFieldValue(fieldRef) {
    try {
      return this._record ? getFieldValue(this._record, fieldRef) : null;
    } catch (_) {
      return null;
    }
  }

  get fiName() {
    return this._safeFieldValue(QUOTE_FI_NAME) ?? '';
  }
  get fiLocation() {
    return this._safeFieldValue(QUOTE_FI_LOCATION) ?? '';
  }
  get fbpsDirectFintech() {
    return this._safeFieldValue(QUOTE_FBPS_DIRECT_FINTECH) ?? '';
  }
  get typeOfFi() {
    return this._safeFieldValue(QUOTE_TYPE_OF_FI) ?? '';
  }
  get assetSizeM() {
    const v = this._safeFieldValue(QUOTE_ASSET_SIZE_M);
    return v != null && v !== '' ? Number(v).toLocaleString() : '';
  }
  get ddaShareCount() {
    const v = this._safeFieldValue(QUOTE_DDA_SHARE_ACCOUNTS_COUNT);
    return v != null && v !== '' ? Number(v).toLocaleString() : '';
  }
  get smallBusinessDdas() {
    const v = this._safeFieldValue(QUOTE_SMALL_BUSINESS_DDAS);
    return v != null && v !== '' ? Number(v).toLocaleString() : '';
  }
  get olbUsers() {
    const v = this._safeFieldValue(QUOTE_OLB_USERS);
    return v != null && v !== '' ? Number(v).toLocaleString() : '';
  }

  get overallDealTypeOptions() {
    return OVERALL_DEAL_TYPE_OPTIONS;
  }
  get panFiservOptions() {
    return PAN_FISERV_OPTIONS;
  }
  get showVarNameSpecify() {
    return this._varTakeaway === true;
  }
  get endDateDisplay() {
    return this._endDateDisplay || this._computeEndDate();
  }
  get noRecordId() {
    return !this.recordId;
  }
  get cpiPercentValue() {
    return this._cpiPercent === undefined || this._cpiPercent === null ? '' : String(this._cpiPercent);
  }
  get termMonthsValue() {
    return this._termMonths === undefined || this._termMonths === null ? '' : String(this._termMonths);
  }
  get hasAccount() {
    try {
      return !!(this._record && getFieldValue(this._record, QUOTE_OPPORTUNITY_ID));
    } catch (_) {
      return false;
    }
  }
  get showNoAccountMessage() {
    return !this.hasAccount;
  }
  get hasRecordAndRecordId() {
    return this.recordId && this._record;
  }
  get isLoading() {
    return Boolean(this.recordId && !this._record && !this._error);
  }
  get errorMessage() {
    if (!this._error) return '';
    try {
      const body = this._error.body;
      if (body?.message) return body.message;
      if (Array.isArray(body?.pageErrors) && body.pageErrors.length) {
        return body.pageErrors.map(e => e && e.message).filter(Boolean).join(' ');
      }
      if (body?.fieldErrors && typeof body.fieldErrors === 'object') {
        const msgs = Object.values(body.fieldErrors)
          .filter(Array.isArray)
          .flat()
          .map(e => e && e.message)
          .filter(Boolean);
        if (msgs.length) return msgs.join(' ');
      }
      return this._error.message || 'Unknown error loading quote.';
    } catch (_) {
      return this._error.message || 'Unknown error loading quote.';
    }
  }

  // UI-only End Date display logic.
  // The server also computes/sends the end date to RLM when appropriate.
  _computeEndDate() {
    const startIso = this._startDate || this._editValues.startDate;
    const termMonths = this._termMonths ?? this._editValues.termMonths;
    if (!startIso || termMonths == null || termMonths === '') return '';

    // Ensure we’re working with a pure ISO date (no time portion).
    const normalizedStartIso = startIso.indexOf('T') > -1 ? startIso.split('T')[0] : String(startIso);
    const endDateIso = computeEndDateIsoFromStartIso(normalizedStartIso, termMonths);
    return endDateIso ? formatMonthDayYearFromIso(endDateIso) : '';
  }

  _computeEndDateIsoForSave(startIso, termMonths) {
    if (!startIso || termMonths == null || termMonths === '') return null;
    const normalizedStartIso = startIso.indexOf('T') > -1 ? startIso.split('T')[0] : String(startIso);
    const endDateIso = computeEndDateIsoFromStartIso(normalizedStartIso, termMonths);
    return endDateIso || null;
  }

  // Input change handlers (each updates the backing tracked value and refreshes dependent UI).
  handleOverallDealTypeChange(event) {
    this._overallDealType = event.detail.value;
  }
  handlePanFiservChange(event) {
    this._panFiserv = event.detail.value;
  }
  handleVarTakeawayChange(event) {
    this._varTakeaway = event.detail.checked;
  }
  handleVarNameSpecifyChange(event) {
    this._varNameSpecify = event.detail.value;
  }
  handleCpiPercentChange(event) {
    this._cpiPercent = event.detail.value;
  }
  handleTermMonthsChange(event) {
    this._termMonths = event.detail.value;
    this._editValues = { ...this._editValues, termMonths: event.detail.value };
    this._endDateDisplay = this._computeEndDate();
  }
  handleStartDateChange(event) {
    this._startDate = event.detail.value;
    this._editValues = { ...this._editValues, startDate: event.detail.value };
    this._endDateDisplay = this._computeEndDate();
  }

  get effectiveDateValue() {
    try {
      const startVal = this._safeFieldValue(QUOTE_PROPOSED_START_DATE);
      const iso = startVal ? (typeof startVal === 'string' && startVal.indexOf('T') > -1 ? startVal.split('T')[0] : String(startVal)) : '';
      return this._startDate || iso || '';
    } catch (_) {
      return this._startDate || '';
    }
  }

  async handleSave() {
    if (!this.recordId) return;
    // Normalize StartDate to YYYY-MM-DD.
    // The Apex controller (and the RLM Place Sales Transaction request) expects an ISO date string.
    // Some orgs deliver date/time values containing a "T" timestamp; we strip the time portion.
    const startStr = this._startDate || this.effectiveDateValue;
    const proposedStart = startStr
      ? (startStr.indexOf('T') > -1 ? startStr.split('T')[0] : startStr)
      : null;

    const termForSave = this._termMonths ?? this._editValues.termMonths;
    const endDateIsoForSave = this._computeEndDateIsoForSave(proposedStart, termForSave);
    const payload = {
      // Quote-level fields (editables from this UI)
      Overall_Deal_Type__c: this._overallDealType || null,
      Pan_Fiserv__c: this._panFiserv || null,
      VAR_Takeaway__c: this._varTakeaway,
      VAR_Name_Specify__c: this._varNameSpecify || null,
      CPI_Percent__c: this._cpiPercent != null && this._cpiPercent !== '' ? this._cpiPercent : null,
      Term_Months__c: this._termMonths != null && this._termMonths !== '' ? this._termMonths : null,
      // Send the normalized value, not the raw UI value (more robust across org data formats).
      StartDate: proposedStart,
      // Explicitly send EndDate to ensure the server writes it.
      EndDate: endDateIsoForSave,
    };
    this._isSaving = true;
    try {
      // Calls Apex which routes the update through the RLM Place Sales Transaction executor.
      await saveQuoteDealFields({ quoteId: this.recordId, fieldValues: payload });
      this.dispatchEvent(new ShowToastEvent({ title: 'Saved', message: 'Quote deal fields updated.', variant: 'success' }));
      this._endDateDisplay = this._computeEndDate();
    } catch (e) {
      this.dispatchEvent(new ShowToastEvent({
        title: 'Error saving',
        message: e.body?.message || e.message || 'Unknown error',
        variant: 'error',
      }));
    } finally {
      this._isSaving = false;
    }
  }
}
