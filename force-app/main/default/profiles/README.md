# Profile field-level security (FLS)

These profiles set **Visible** (readable) and, where applicable, **Editable** for all custom fields created in the Quote Deal Input project.

## Included profiles

- **Admin** – System Administrator  
- **Standard** – Standard User  

Deploying this source adds these field permissions to the existing Admin and Standard profiles (merge behavior).

## Other profiles (e.g. custom profiles)

To make the same project fields visible for **all** profiles in your org:

1. In Setup, note the **API names** of each profile (e.g. `Sales_Profile`, `Support_Profile`).
2. Copy `Admin.profile-meta.xml` to a new file named `{ProfileApiName}.profile-meta.xml` (e.g. `Sales_Profile.profile-meta.xml`).
3. Add that profile to `manifest/package.xml` under the `Profile` type:
   ```xml
   <members>Sales_Profile</members>
   ```
4. Deploy.

Alternatively, assign the **Quote Deal Input Access** permission set to all users (or to permission set groups that cover all users); that permission set already grants Visible/Editable on the same fields.
