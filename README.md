# Contact Directory - setup guide

## 1. Supabase (5 minutes)
1. Create a project at supabase.com (free plan is enough).
2. Open **SQL Editor** > New query > paste everything from `setup.sql` > **Run**.
3. Open **Authentication > Providers > Email** and turn **OFF** "Confirm email".
   (Users log in with a User ID, not a real email, so confirmation mails cannot work.)
4. Open **Project Settings > API** and copy the **Project URL** and the **anon public** key.

## 2. Connect the app
Open `index.html` and replace these two lines near the bottom:

    const SUPABASE_URL = "PASTE_YOUR_PROJECT_URL";
    const SUPABASE_KEY = "PASTE_YOUR_ANON_PUBLIC_KEY";

The anon key is safe to put in the page. Security comes from the row-level rules in `setup.sql`.
Never put the service_role key here.

## 3. Host it
Upload `index.html` to a new GitHub repository, then **Settings > Pages > Deploy from branch (main)**.
Share the Pages link with your team. On a phone, open it and choose "Add to Home Screen".

## 3b. Add / remove users from the app (run once)
Run `admin_users.sql` in the SQL Editor. After that, **Admin > Users** has **Add user**, **Reset password** and **Remove**.
Logins use the company domain: user ID `rahul.shah` logs in as rahul.shah@mechvactech.com (typing just `rahul.shah` works).
If you created your admin earlier with the old domain, this script also moves it to @mechvactech.com.

## 4. First use
- **The first account created becomes Admin.** Create yours first.
- Colleagues tap "Create an account" (User ID + password + full name). They stay locked out until you open
  **Admin > Users** and tick **Approved**.
- Use **Import** to load your existing Excel/CSV contacts. Recognised column headings include:
  First Name, Last Name, Nickname, Company, Industry, Location/City, Address, Phone/Mobile, Email,
  Designation, Remarks, Tags. Rows with a phone number already in the directory are skipped.

## Rules built in
| Action | Who |
|---|---|
| View and search all contacts | Any approved user |
| Add contact | Any approved user (name of the user is stamped automatically) |
| Edit / delete a contact | The user who added it, or an Admin |
| Approve users, change roles, manage industries, export to Excel | Admin only |

## Forgot password
Admin: open **Admin > Users** in the app and click **Reset password** next to the user.
