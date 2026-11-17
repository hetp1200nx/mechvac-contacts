# Contact Directory - setup guide

## Files
| File | What it is |
|---|---|
| `index.html` | The app |
| `config.js` | Your Supabase URL and key (fill in once) |
| `setup.sql` | Database: tables, security rules, admin functions, your first admin |

## 1. Supabase (5 minutes)
1. Create a project at supabase.com (the free plan is enough).
2. **Authentication > Providers > Email**: turn **OFF** "Confirm email". Users log in with a User ID, not a real email.
3. Open `setup.sql`, scroll to the very bottom and set `v_username`, `v_password`, `v_fullname` (this becomes your Admin login).
4. **SQL Editor** > New query > paste all of `setup.sql` > **Run**.
5. **Project Settings > API**: copy the **Project URL** and the **anon public** key.

Already ran an older `setup.sql`? Run the new one again. It is safe to re-run: it keeps your contacts, moves old
remarks into the private table, and adds the new rules. Leave `v_password` as `ChangeMe@123` to skip the admin step.

## 2. Connect the app
Open `config.js` and paste the URL and key. You only do this once; later versions of `index.html` need no edits.
Never use the service_role key.

## 3. Host it
Upload `index.html` and `config.js` to a GitHub repository, then **Settings > Pages > Deploy from branch (main)**.
On a phone, open the link and choose "Add to Home Screen".

## How it works
| Feature | Rule |
|---|---|
| Logins | User ID + password. `rahul.shah` logs in as rahul.shah@mechvactech.com (typing just `rahul.shah` works) |
| Who sees contacts | Every approved user sees every contact, with an "Added by" tag |
| Duplicate numbers | A number (phone, alternate or WhatsApp, matched on the last 10 digits) can only be saved once. Blocked when adding, editing and importing, and enforced by the database |
| Remarks | Private. Only the user who added the contact can read or edit them. Admins and other users never see them |
| Edit | The user who added the contact, or an Admin |
| Delete | Anyone can press **Request delete**. The contact stays until an Admin approves it in **Admin > Delete requests**. An Admin can also delete directly |
| Users | Admin adds, removes, resets passwords and approves new sign-ups in **Admin > Users** |
| Import | Excel/CSV preview shows how many are new and which numbers are skipped, before anything is saved |

Import recognises these headings: First Name, Last Name, Nickname, Company, Industry, Location/City, Address,
Phone/Mobile, Alternate Phone, WhatsApp, Email, LinkedIn, Designation, Source, Pump, Tags, Remarks.

## Good to know
- Removing a user also deletes that user's private remarks. The contacts they added stay.
- Anyone with access to the Supabase dashboard can still read the database tables directly.
