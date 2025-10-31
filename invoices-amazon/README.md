## Amazon Business Invoice Downloader (Bun + SP-API)

Automated Bun script that downloads Amazon Business invoices (PDF/ZIP) via the Selling Partner API (SP-API). Uses the official `@selling-partner-api/sdk` to handle both Login with Amazon (LWA) and AWS SigV4 authentication through SDK interceptors. Intended for cron usage and safe to re-run thanks to local state tracking that prevents duplicate downloads. Works well with Paperless-NGX or as a standalone archive tool.

### Project structure

```
amazon-invoices/
├─ .env                   # Credentials and settings
├─ invoices/              # Target directory for invoices
├─ state.json             # Tracks already downloaded orderIds
├─ index.ts               # Main Bun script
├─ package.json           # Project definition
```

### Required environment variables (.env)

```ini
# SP-API / LWA Auth
LWA_CLIENT_ID=
LWA_CLIENT_SECRET=
LWA_REFRESH_TOKEN=

# AWS IAM / SigV4
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_ROLE_ARN=

# Region / Marketplace
SPAPI_REGION=eu-west-1
SPAPI_ENDPOINT=https://sellingpartnerapi-eu.amazon.com
MARKETPLACE_ID=A1PA6795UKMFR9

# Date range (ISO8601)
FROM=2025-01-01T00:00:00Z
TO=2025-12-31T23:59:59Z

# Paths
OUT_DIR=./invoices
STATE_FILE=./state.json
```

### Setup guide: Getting your .env values

Follow these steps to obtain all required credentials:

#### Step 1: Register your SP-API application

**Important:** There are two different portals for SP-API apps:

- **Solution Provider Portal** (`solutionprovider.amazon.com`) - For solution providers creating apps for multiple sellers/vendors
- **Seller Central → Develop Apps** - For sellers/vendors creating private apps for their own use (recommended for this project)

**For Private Apps (recommended for this invoice downloader):**

1. Log in to **Seller Central** (not Solution Provider Portal)
   - URL: `sellercentral.amazon.com` (or `sellercentral-europe.amazon.com` for EU)
2. Navigate to **Apps and Services** → **Develop Apps**
   - If you don't see this menu, ensure you have developer access enabled
   - Alternatively: Look for "API Integration" or "Developer Console" in the navigation
3. Click **Add new app client** or **Register new app**
4. Configure:
   - **App name**: e.g., "Invoice Downloader"
   - **OAuth Redirect URI**: Only required for **Public applications** (can leave empty for Private apps)
     - If Public: `https://localhost/callback` (or `https://localhost/login`)
     - If Private: Leave empty (not needed for self-authorization)
   - **Application Type**: Private (for personal use) or Public
   - **Business unit**: ⚠️ **Critical:** Select **Amazon Business** (required for invoice downloads)
     - This setting might not be editable after app creation
     - If your account doesn't show "Amazon Business", ensure your Seller Central account has Amazon Business enabled
     - Wrong business unit selection causes Error SPSA0404: "Keine unterstützte Geschäftseinheit gefunden"
5. After creation, note the **LWA credentials** and **IAM User ARN** shown on the app details page

**Note:** For **Private applications**, OAuth Redirect URIs are optional since they use self-authorization, not OAuth. You can skip this field during registration.

**If you're already in the Solution Provider Portal:**

If you've already created an app in the Solution Provider Portal (you see your app listed with status "Entwurf"/"Draft"):

1. **Option A: Use the Solution Provider Portal app**
   - Click **"App bearbeiten" (Edit App)** next to your app
   - Or click **"Anzeigen" (Show)** under "Anmeldedaten für Login mit Amazon" to view credentials
   - Complete the app configuration and ensure **Amazon Business** is selected as business unit
   - Note: Solution Provider Portal apps work differently and may require additional setup for private use

2. **Option B: Create a new app in Seller Central (recommended)**
   - Go to Seller Central instead (`sellercentral.amazon.com`)
   - Navigate to **Apps and Services** → **Develop Apps**
   - Create a new app there (easier for private apps, better integration with your seller account)

#### Step 2: Get LWA credentials (LWA_CLIENT_ID, LWA_CLIENT_SECRET)

**In Seller Central (Develop Apps):**
- Go to your app's detail page
- **LWA_CLIENT_ID**: Found under "Login with Amazon (LWA) Client Identifier"
- **LWA_CLIENT_SECRET**: Found under "Login with Amazon (LWA) Client Secret"
- Click "Show" to reveal the secret (copy it immediately, it won't be shown again)

**In Solution Provider Portal:**
- Click **"Anzeigen" (Show)** link under "Anmeldedaten für Login mit Amazon" column in the app list
- Or click **"App bearbeiten" (Edit App)** → Navigate to credentials section
- The credentials should be displayed there

**Add to .env:**
```ini
LWA_CLIENT_ID=amzn1.application-oa2-client.xxxxx...
LWA_CLIENT_SECRET=xxxxx...
```

#### Step 3: Get AWS Role ARN (AWS_ROLE_ARN)

**Important:** Do this step before creating AWS credentials, as you need the Role ARN for the IAM policy.

The AWS Role ARN is displayed in Seller Central after you complete the authorization process. Follow these steps:

**Option A: If your app is already authorized (Seller Central):**

1. In **Seller Central** → **Apps and Services** → **Develop Apps**
2. Click on your app name to open the app detail page
3. Navigate to the **Authorizations** or **Authorizations remaining** section
4. Click **View** on an existing authorization (or create a new one if none exists)
5. Look for **IAM Role ARN** or **IAM User ARN** in the authorization details
6. Copy the **Role ARN** (format: `arn:aws:iam::123456789012:role/SellingPartnerApiRole`)
   - This is the role your AWS user will assume for SP-API access

**Option A2: If your app is in Solution Provider Portal (detailed steps):**

The AWS Role ARN is typically shown **during the authorization process**. Follow these steps:

1. **App-Konfiguration abschließen (wichtig vor Authorization):**
   - In **Solution Provider Portal** → Click **"App bearbeiten" (Edit App)** next to your app
   - Ensure **Amazon Business** is selected as business unit
   - **Activate both required roles:**
     - ✅ "Abgleichen von Business-Einkäufen" (Reconciliation of Business Purchases)
     - ✅ "Amazon Business-Bestellung" (Amazon Business Order) - **Critical!**
   - OAuth URIs can be left empty for Private apps
   - Click **"Speichern und beenden" (Save and exit)**
   
2. **Status "Entwurf" (Draft) ist normal:**
   - After saving, the app will still show status "Entwurf" (Draft) - this is expected!
   - The app must be authorized to change from "Entwurf" to "Aktiv" (Active)
   - Authorization is the next step

3. **Start the authorization process to get the Role ARN:**
   - In the app list, look for an **"Authorisieren" (Authorize)** button next to your app
   - Or click **"App bearbeiten" (Edit App)** → Look for **"Authorisieren"**, **"Self-authorize"**, or **"Authorization"** button/section
   - Click to start the authorization workflow
   
4. **During the authorization process**, Amazon will display the **IAM Role ARN**:
   - This appears in a section like **"AWS IAM Role"**, **"IAM Configuration"**, or **"IAM User ARN"**
   - The Role ARN format: `arn:aws:iam::123456789012:role/SellingPartnerApiRole`
   - **Copy this Role ARN immediately** - you'll need it for Step 4

5. **Important workflow:**
   - **Don't complete the authorization yet!** 
   - Copy the Role ARN first
   - Go to Step 4: Configure AWS IAM with this Role ARN
   - **Then** come back to complete the authorization process

**If you don't see an Authorization button:**
- The app might need to be in "Production" mode (check app settings)
- Try refreshing the page
- Check if there's an **"Authorizations"** tab/section in the app detail view

**Alternative locations in Solution Provider Portal:**
- App detail page → **"AWS Configuration"** tab → **IAM Role ARN**
- App detail page → **"Authorizations"** section → View existing authorization → **IAM Role ARN**
- Check if there's an **"AWS IAM Role"** or **"IAM Settings"** section on the app edit page

**Option B: If your app is not yet authorized (you'll see it during authorization):**

1. In **Seller Central** → **Apps and Services** → **Develop Apps** → Your app
2. Click **Authorize** or **Self-authorize** (for Private apps)
3. During the authorization process, Amazon will show you the **IAM Role ARN** that needs to be configured
4. Copy the **Role ARN** from this screen
5. You may need to complete or cancel the authorization at this point - the Role ARN is visible before finalizing

**Option C: Check the app registration email or initial setup:**

Sometimes the Role ARN is provided:
- In the confirmation email when you first register the app
- On the initial app registration success page
- In the **IAM Settings** or **AWS Configuration** section of your app

**Common locations in Seller Central:**
- App detail page → **Authorizations** tab → Click on authorization → **IAM Role ARN**
- App detail page → **IAM User ARN** (directly on the page, may be labeled differently)
- During authorization workflow → **AWS IAM Role** section

**Note:** The Role ARN format is: `arn:aws:iam::ACCOUNT_ID:role/ROLE_NAME` (e.g., `arn:aws:iam::123456789012:role/SellingPartnerApiRole`)

**Add to .env:**
```ini
AWS_ROLE_ARN=arn:aws:iam::123456789012:role/SellingPartnerApiRole
```

#### Step 4: Get AWS credentials (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)

1. In **AWS Console**, go to **IAM** → **Users**
2. Create a new user (or use existing) with programmatic access
3. Grant permissions to assume the SP-API role:
   - Create or attach a policy with:
     ```json
     {
       "Version": "2012-10-17",
       "Statement": [{
         "Effect": "Allow",
         "Action": "sts:AssumeRole",
         "Resource": "arn:aws:iam::xxxxx:role/SP-Api-Role"
       }]
     }
     ```
   - Replace `arn:aws:iam::xxxxx:role/SP-Api-Role` with your **AWS_ROLE_ARN** from Step 3
4. Create **Access Key** for this user:
   - IAM → Users → [Your User] → Security credentials → Create access key
   - Choose "Application running outside AWS" → Create
   - **Copy both values immediately** (secret is shown only once)

**Add to .env:**
```ini
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=xxxxx...
```

#### Step 5: Generate LWA refresh token (LWA_REFRESH_TOKEN)

**For Private Applications (Self-Authorization):**

Private apps use **self-authorization**, which is simpler:

1. In **Seller Central** → Your app's detail page
2. Find the **Authorizations** section
3. Click **Authorize** or **Self-authorize** (the exact wording may vary)
4. After authorization, the refresh token should be available in the app details or authorization section
5. Copy the `refresh_token` value

**Alternative method (works for both Private and Public apps):**

Use the **Authorization Code Grant** flow:

1. Build the authorization URL:
   ```
   https://sellercentral.amazon.com/apps/authorize/consent?
     application_id=YOUR_LWA_CLIENT_ID&
     version=beta&
     redirect_uri=https://localhost/callback&
     state=state123
   ```
   - Replace `YOUR_LWA_CLIENT_ID` with your actual Client ID
   - **Note:** For Private apps without OAuth Redirect URI, you may need to add one temporarily or use the self-authorization method above

2. Open this URL in your browser while logged into Seller Central
3. Approve the authorization
4. You'll be redirected to `https://localhost/callback?spapi_oauth_code=XXXXX&state=state123`
5. Copy the `spapi_oauth_code` value from the URL
6. Exchange the code for a refresh token:

   Using `curl`:
   ```bash
   curl -X POST https://api.amazon.com/auth/o2/token \
     -H "Content-Type: application/x-www-form-urlencoded" \
     -d "grant_type=authorization_code" \
     -d "code=YOUR_SPAPI_OAUTH_CODE" \
     -d "redirect_uri=https://localhost/callback" \
     -d "client_id=YOUR_LWA_CLIENT_ID" \
     -d "client_secret=YOUR_LWA_CLIENT_SECRET"
   ```

   Response includes `refresh_token`:
   ```json
   {
     "access_token": "...",
     "token_type": "bearer",
     "expires_in": 3600,
     "refresh_token": "Atzr|xxxxx..."  ← This is what you need
   }
   ```

**Note:** For Private apps, the self-authorization method (first option) is typically simpler and doesn't require OAuth Redirect URIs.

**Add to .env:**
```ini
LWA_REFRESH_TOKEN=Atzr|xxxxx...
```

#### Step 6: Configure marketplace and region (already set for EU)

Default values are for **EU (Germany)**:
- `SPAPI_REGION=eu-west-1` (EU West)
- `SPAPI_ENDPOINT=https://sellingpartnerapi-eu.amazon.com`
- `MARKETPLACE_ID=A1PA6795UKMFR9` (Germany)

**For other marketplaces**, update:
- **US**: `SPAPI_REGION=us-east-1`, `ENDPOINT=https://sellingpartnerapi-na.amazon.com`, `MARKETPLACE_ID=ATVPDKIKX0DER`
- **UK**: `SPAPI_REGION=eu-west-1`, `ENDPOINT=https://sellingpartnerapi-eu.amazon.com`, `MARKETPLACE_ID=A1F83G8C2ARO7P`
- Full list: [Amazon SP-API Marketplace IDs](https://developer-docs.amazon.com/sp-api/docs/marketplace-ids)

#### Step 7: Set date range (optional)

Leave empty for automatic defaults (last 90 days to now):
```ini
FROM=
TO=
```

Or set specific dates (ISO8601 format):
```ini
FROM=2025-01-01T00:00:00Z
TO=2025-12-31T23:59:59Z
```

#### Step 8: Verify your .env file

Your complete `.env` should look like:
```ini
LWA_CLIENT_ID=amzn1.application-oa2-client.xxxxx
LWA_CLIENT_SECRET=xxxxx
LWA_REFRESH_TOKEN=Atzr|xxxxx
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=xxxxx
AWS_ROLE_ARN=arn:aws:iam::123456789012:role/SellingPartnerApiRole
SPAPI_REGION=eu-west-1
SPAPI_ENDPOINT=https://sellingpartnerapi-eu.amazon.com
MARKETPLACE_ID=A1PA6795UKMFR9
FROM=
TO=
OUT_DIR=./invoices
STATE_FILE=./state.json
```

**Important security notes:**
- Never commit `.env` to git (already in `.gitignore`)
- Store secrets securely
- Refresh tokens can expire; regenerate if authentication fails

### Prerequisites

**Do I need a Seller Central account?**

**No, you don't need a full Seller Central seller account!** You have two options:

1. **Solution Provider Portal** (what you're currently using) - ✅ **This works!**
   - Use your existing app in the Solution Provider Portal
   - No need to register as a seller
   - Perfect for private apps if you have an Amazon Business account

2. **Seller Central → Develop Apps** (alternative)
   - Requires either a seller account OR developer access
   - If you get the "already registered on another marketplace" error, you can use the Solution Provider Portal instead
   - You might need to complete any pending registration first, but you don't need to become a seller

**For this project (private invoice downloader):**
- An **Amazon Business account** (as a buyer) is sufficient - no seller registration needed
- Use **Solution Provider Portal** to create/manage your app (you already have an app there!)
- SP-API developer access (via Solution Provider Portal)

**Requirements:**
- **Amazon Business account** (buyer account is sufficient)
- In **Solution Provider Portal** OR **Seller Central → Developer Console**, register an app:
  - **API type**: SP-API
  - **App type**: Production
  - **Business unit**: Amazon Business
  - **Roles**:
    - Abgleichen von Business-Einkäufen
    - Amazon Business-Bestellung
  - **RDT**: No
  - **OAuth redirect URIs**: Only required for **Public applications** (optional for Private apps)
    - If Public: `https://localhost/login`, `https://localhost/callback`
    - If Private: Can be left empty (uses self-authorization, not OAuth)
- Generate an **LWA refresh token**:
  - **Private apps**: Use self-authorization in Seller Central (simpler, no OAuth Redirect URI needed)
  - **Public apps**: Use Authorization Code Grant flow (see Amazon docs)
- In AWS IAM, allow your user to perform `sts:AssumeRole` on the Seller Central "Role ARN"

### ⚠️ Authorization limits

SP-API applications are subject to authorization limits based on application type ([Amazon documentation](https://developer-docs.amazon.com/sp-api/docs/application-authorization-limits)):

**Private applications** (typical for personal/company use):
- **Maximum 10 self-authorizations** only
- No OAuth authorizations available
- If you need more than 10 Amazon Business accounts, convert the application to public or remove unused authorizations

**Public applications** (unlisted, not on Appstore):
- Maximum 10 self-authorizations + **25 OAuth authorizations** for sellers
- Unlimited OAuth authorizations for vendors

**Public applications** (listed on Selling Partner Appstore):
- Maximum 10 self-authorizations + **unlimited OAuth authorizations**

**Important:** Once you reach your authorization limit, you cannot add more authorizations. Perform regular audits and remove unused authorizations to maintain flexibility. View your current usage in Seller Central → **Apps and Services** → **Develop Apps** → **Authorizations remaining**.

### Authentication layers

1. LWA: Exchanges the stored `refresh_token` for an access token.
2. AWS SigV4: Signs each SP-API request using the IAM role (`AWS_ROLE_ARN`).

Both handled automatically by the SDK interceptors.

### Processing flow

1. Fetch order/transaction IDs
   - `GET /reconciliations/v1/transactions` for the `FROM`–`TO` window
2. For each `orderId` request a report
   - `POST /reports/2021-09-30/reports` with `reportType=GET_AB_INVOICE_PDF`
3. Poll until the report is ready
   - `GET /reports/2021-09-30/reports/{reportId}`
4. Retrieve download URL and save
   - `GET /reports/2021-09-30/documents/{reportDocumentId}`
5. Update local state
   - `state.json` prevents re-downloading the same invoices

### Install and run

1. Install Bun and enable the project
   - Install dependencies: `bun add @selling-partner-api/sdk`
2. Create `.env` from `.env.example` and fill in all values
3. Run once manually:

```bash
bun run index.ts
```

Invoices are saved to `OUT_DIR`; processed `orderId`s are recorded in `STATE_FILE`.

### Cron automation

Example (every 6 hours):

```bash
0 */6 * * * cd /path/to/amazon-invoices && bun run index.ts >> ./cron.log 2>&1
```

### Operational notes

- System clock should be synchronized (NTP)
- Network access to:
  - `sellingpartnerapi-eu.amazon.com`
  - `api.amazon.com`
  - Temporary S3 download URLs
- Write permissions to `OUT_DIR` and `STATE_FILE`
- IAM user can `sts:AssumeRole` for `AWS_ROLE_ARN`
- Optional: Configure Paperless-NGX to watch `OUT_DIR`

### Ideas for extension

- Unzip and rename PDFs automatically (e.g., `YYYY-MM-DD_OrderId.pdf`)
- Improved logging (Pino/Winston)
- Retry on rate limits using `Retry-After`
- Bounded parallelism (e.g., `p-limit`)
- Paperless API integration (`POST /api/documents/post_document/`)
- Config via YAML or CLI flags (e.g., `--from`, `--to`)

### Troubleshooting

**Error Code SPSA0404: "Keine unterstützte Geschäftseinheit gefunden" (No supported business unit found)**

This error occurs during authorization when your SP-API app doesn't have a business unit configured correctly. Common causes and fixes:

**For Solution Provider Portal:**

1. **Verify Business Unit is selected in app configuration:**
   - Go to **Solution Provider Portal** → Click **"App bearbeiten" (Edit App)**
   - Check section **"Unterstützte Unternehmenseinheiten" (Supported Business Units)**
   - Ensure **"Amazon Business"** checkbox is checked ✅
   - If not checked, check it and click **"Speichern und beenden" (Save and exit)**
   - Try authorization again

2. **Check if your Amazon account has Amazon Business:**
   - Error SPSA0404 can occur if your Amazon account doesn't have Amazon Business enabled
   - Log in to `business.amazon.com` to verify you have an Amazon Business account
   - If you don't have Amazon Business, you'll need to:
     - Register for Amazon Business, OR
     - Use a different business unit that your account supports

3. **Verify roles are correctly selected:**
   - In "App bearbeiten" → Section **"Rollen" (Roles)**
   - Under **"Amazon Business"**, ensure these are checked:
     - ✅ "Abgleichen von Business-Einkäufen"
     - ✅ "Amazon Business-Bestellung"
   - Save and try again

4. **Try creating a new app:**
   - If the issue persists, the business unit might be locked after first save
   - Create a new app in Solution Provider Portal
   - **During creation**, ensure "Amazon Business" is selected before saving
   - Make sure to activate both required roles during creation

**For Seller Central:**

1. Go to **Seller Central** → **Apps and Services** → **Develop Apps**
2. Click on your app to open the detail page
3. Look for **Business units** or **Geschäftseinheiten** section
4. Click **Edit** or **Update business units**
5. Select **Amazon Business** (or the appropriate business unit for your account)
6. Save the changes
7. Try the authorization again

**Root cause check:**
- Ensure your Amazon account actually has Amazon Business access
- Business unit might be set only during app creation (not editable later)
- Some accounts may need to complete Amazon Business registration first

**Regional/Marketplace mismatch (important for German accounts):**

If you're registered with **Amazon Business Germany** (`business.amazon.de`), there might be a regional mismatch:

1. **Verify your Amazon Business account region:**
   - If you're at `business.amazon.de` (Germany) → You need EU marketplace configuration
   - If you're at `business.amazon.com` (US) → You need US marketplace configuration
   - Check which Amazon Business site you use: `.de`, `.co.uk`, `.com`, etc.

2. **Solution Provider Portal region:**
   - The Solution Provider Portal should match your Amazon Business region
   - German accounts: Ensure you're using the EU Solution Provider Portal
   - URL should reflect your region (e.g., EU portal for German accounts)

3. **App configuration must match:**
   - If your Amazon Business account is in Germany, the app should be configured for:
     - **Marketplace**: EU/Germany (`A1PA6795UKMFR9` for Germany)
     - **Business Unit**: Amazon Business (should work, but verify)
     - **Region**: `eu-west-1` in your `.env` file

4. **Possible solutions:**
   - Try accessing the Solution Provider Portal from the correct regional domain
   - Ensure your app is created in the same region as your Amazon Business account
   - For German accounts: Verify you're using `solutionprovider.amazon.com` (EU) not US version
   - Consider creating the app directly in Seller Central Germany instead of Solution Provider Portal

5. **Alternative: Use Seller Central for regional accounts:**
   - German Amazon Business accounts might work better with Seller Central → Develop Apps
   - Seller Central automatically matches your account's region
   - Navigate to `sellercentral-europe.amazon.com` → Apps and Services → Develop Apps

**401/403 errors:**
- Check LWA credentials (Client ID, Client Secret, Refresh Token)
- Verify IAM role assumptions and AWS credentials
- Ensure the refresh token hasn't expired

**Report stuck in `IN_QUEUE`:**
- Increase polling interval (currently 3 seconds in the script)
- Widen the date window (smaller date ranges may help)
- Check if there are pending reports in Seller Central

**Empty downloads:**
- Confirm `MARKETPLACE_ID` matches your account's marketplace
- Verify the time range (`FROM`/`TO`) contains actual transactions
- Check that your account has the required roles: "Abgleichen von Business-Einkäufen" and "Amazon Business-Bestellung"


