# Quote Deal Input LWC — Plan (Updated)

## Scope

- **One LWC** on the Quote record page: two-column layout matching the image, SLDS styling, org-aware (SLDS tokens/theming).
- **Green cells** = values from Account (via Quote’s `AccountId`). Implemented by either:
  - **Option A (recommended):** Formula fields on Quote that reference Account; LWC uses `getRecord(Quote)` and displays those formula fields as read-only.
  - **Option B:** LWC uses `getRecord` with `Quote` + `Quote.Account.*` and displays Account fields as read-only (no Quote formula fields).
- **Yellow cells** = editable Quote fields. Custom fields on Quote for all except dates; use **standard Quote date fields** for Start/End.
- **End Date** = standard Quote field (ExpirationDate), display-only in the form; **calculated from Start Date + Term_Months__c** when the user provides Term and saved to ExpirationDate on save.
- **Fintech? (requires Direct)** = label/help text only (no new field).
- **“If Yes, Specify VAR name”** = conditional visibility when VAR Takeaway = Yes.
- **Core Product** = **not** on Quote and **not** in the LWC (no `Core_Product__c` on Quote, no Core Product input/display in the component). Keep `Core_Product__c` on Account only if needed for other uses.

Standard Quote date fields: **EffectiveDate** (Start / “Go Live or Proposed Start Date”) and **ExpirationDate** (End Date).

### Quote updates — required API

**For all updates to the Quote or quote-level fields, use only the API described in:**

**[Revenue Lifecycle Management Dev Guide — Connect Resources: Place Sales Transaction](https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/connect_resources_place_sales_transaction.htm)**

- Do **not** use `updateRecord` from `lightning/uiRecordApi` (or other generic record update APIs) for Quote or quote-level updates.
- The LWC will perform saves by calling the Place Sales Transaction API (e.g. via an Apex controller that invokes the Connect API or the documented REST resource). Implementation must follow the request/response and flow described in that documentation.
- Related Apex: [RevSalesTrxn_PlaceSalesTransactionExecutor](https://developer.salesforce.com/docs/atlas.en-us.revenue_lifecycle_management_dev_guide.meta/revenue_lifecycle_management_dev_guide/apex_class_RevSalesTrxn_PlaceSalesTransactionExecutor.htm) may be used where the doc specifies it for executing the place-sales-transaction flow.

---

## 1. Custom field metadata

### 1.1 Account (source for “green” fields)

| Purpose | API name (suggested) | Type | Notes |
|--------|----------------------|------|--------|
| FI Location | — | — | Use standard **BillingCity** and **BillingState**. |
| FBPS, Direct, Fintech | `FBPS_Direct_Fintech__c` | Picklist (FBPS, Direct, Fintech) | |
| Type of FI | `Type_of_FI__c` | Picklist (e.g. Bank, Credit Union, …) | |
| Asset Size $M | `Asset_Size_M__c` | Number (or Currency), scale 0 | In millions. |
| DDA/Share Accounts Count | `DDA_Share_Accounts_Count__c` | Number, scale 0 | |
| Small Business DDAs | `Small_Business_DDAs__c` | Number, scale 0 | |
| OLB Business and/or Retail Users | `OLB_Business_Retail_Users__c` | Number, scale 0 | |
| Core Product | `Core_Product__c` | Text or Picklist (e.g. Signature) | Account only; **not** on Quote and **not** in LWC. |

**FI Name** = standard **Account.Name** (no new field).

### 1.2 Quote (formula + editable)

**Formula fields (Option A only)** — no Core Product on Quote:

- `FI_Name__c` (Formula, Text) = `Account.Name`
- `FI_Location__c` (Formula, Text) = `BillingCity & ", " & BillingState` (Account)
- `FBPS_Direct_Fintech__c` (Formula, Text) = `Account.FBPS_Direct_Fintech__c`
- `Type_of_FI__c` (Formula, Text) = `Account.Type_of_FI__c`
- `Asset_Size_M__c` (Formula, Number) = `Account.Asset_Size_M__c`
- `DDA_Share_Accounts_Count__c` (Formula, Number) = `Account.DDA_Share_Accounts_Count__c`
- `Small_Business_DDAs__c` (Formula, Number) = `Account.Small_Business_DDAs__c`
- `OLB_Business_Retail_Users__c` (Formula, Number) = `Account.OLB_Business_Retail_Users__c`
- **Do not create** `Core_Product__c` on Quote.

**Editable (yellow) fields:**

| Label | API name (suggested) | Type |
|-------|----------------------|------|
| Overall Deal Type | `Overall_Deal_Type__c` | Picklist (e.g. New, Renewal, …) |
| Pan-Fiserv? | `Pan_Fiserv__c` | Picklist (Yes, No) or Checkbox |
| VAR Takeaway? | `VAR_Takeaway__c` | Checkbox or Picklist (Yes/No) |
| If Yes, Specify VAR name | `VAR_Name_Specify__c` | Text(255) |
| CPI% | `CPI_Percent__c` | Percent |
| Term (# of months) | `Term_Months__c` | Number |

**Dates:**

- **Go Live or Proposed Start Date** → **Quote.EffectiveDate**
- **End Date** → **Quote.ExpirationDate**. When the user provides input to **Term_Months__c** (or changes Start Date), calculate **End Date = Start Date + Term_Months__c (months)** and save to **ExpirationDate**.

---

## 1.3 Permission set (read + write for all project fields and objects)

Create **one permission set** metadata file that grants users **read and write** access to all custom fields and objects created in this project.

**File location:** `force-app/main/default/permissionSets/Quote_Deal_Input_Access.permissionset-meta.xml`

**Contents:**

- **Label / description:** e.g. "Quote Deal Input – access to FI/Deal fields on Account and Quote".
- **Object permissions** (`objectPermissions`): Grant **Read** and **Edit** (allowRead, allowEdit) for:
  - **Account**
  - **Quote**
- **Field permissions** (`fieldPermissions`): One entry per custom field. Use `<readable>true</readable>` for all; use `<editable>true</editable>` for editable fields and `<editable>false</editable>` for formula (read-only) fields.

**Account custom fields** (all Read + Edit):

- `Account.FBPS_Direct_Fintech__c`
- `Account.Type_of_FI__c`
- `Account.Asset_Size_M__c`
- `Account.DDA_Share_Accounts_Count__c`
- `Account.Small_Business_DDAs__c`
- `Account.OLB_Business_Retail_Users__c`
- `Account.Core_Product__c`

**Quote custom fields:**

- **Formula (Read only, Editable = false):** `Quote.FI_Name__c`, `Quote.FI_Location__c`, `Quote.FBPS_Direct_Fintech__c`, `Quote.Type_of_FI__c`, `Quote.Asset_Size_M__c`, `Quote.DDA_Share_Accounts_Count__c`, `Quote.Small_Business_DDAs__c`, `Quote.OLB_Business_Retail_Users__c`
- **Editable (Read + Edit):** `Quote.Overall_Deal_Type__c`, `Quote.Pan_Fiserv__c`, `Quote.VAR_Takeaway__c`, `Quote.VAR_Name_Specify__c`, `Quote.CPI_Percent__c`, `Quote.Term_Months__c`

**Metadata structure (reference):** `PermissionSet` with `objectPermissions` (object, allowRead, allowEdit) and `fieldPermissions` (field, readable, editable). No custom objects are created in this project—only custom fields on Account and Quote—so the permission set only needs these object and field entries.

---

## 2. Lightning Web Component

### 2.1 End Date calculation (required behavior)

- When the user enters or changes **Term_Months__c** or **Start Date (EffectiveDate)**, compute **End Date** as:  
  **Start Date + Term_Months__c months** → set **Quote.ExpirationDate**.
- On Save, include **ExpirationDate** in the payload (calculated from EffectiveDate and Term_Months__c so the standard End Date field stays in sync).
- Display End Date in the form as read-only (showing ExpirationDate or the calculated value).

### 2.2 Layout (no Core Product in UI)

- **Left column:** FI Name, FI Location, Fintech? (label), FBPS/Direct/Fintech, Type of FI, Overall Deal Type, Pan-Fiserv?, VAR Takeaway?, If Yes Specify VAR name.
- **Right column:** Asset Size $M, DDA/Share Count, Small Business DDAs, OLB Users, CPI%, Term (months), Go Live/Start Date, End Date. **No Core Product field or input.**

### 2.3 Data and save

- **Load:** Use `getRecord` for Quote (with formula or Account relation) and read-only display only; no change.
- **Save:** Do **not** use `updateRecord`. Invoke the **Place Sales Transaction** API (see link above) for all Quote/quote-level updates—e.g. from the LWC via an Apex controller that calls the Connect API or `RevSalesTrxn_PlaceSalesTransactionExecutor` as specified in the RLM dev guide. The payload must include the editable Quote fields (including EffectiveDate and calculated ExpirationDate) in the format required by that API.
- **UI:** SLDS two-column form; conditional VAR name field; validation; loading/error handling.

---

## 3. Summary of your changes

1. **Core Product:** Do **not** create `Core_Product__c` on Quote; do **not** add any Core Product display or input in the LWC.
2. **End Date:** When the user provides input to **Term_Months__c**, use **Start Date (EffectiveDate)** and **Term_Months__c** to calculate **End Date** and set **Quote.ExpirationDate** (and show it in the form).
3. **Quote updates API:** All updates to the Quote or quote-level fields must use the **Revenue Lifecycle Management Connect API — Place Sales Transaction** (see link in Scope). Do not use `updateRecord`; use the documented API (e.g. via Apex that invokes the Connect resource or `RevSalesTrxn_PlaceSalesTransactionExecutor`).
4. **Permission set:** Create a permission set metadata file (`Quote_Deal_Input_Access.permissionset-meta.xml`) that grants read and write access to all custom fields and to Account and Quote as described in section 1.3.
