# LF3 Alumni — editable website starter

A multi-page-feeling, responsive alumni directory for graduates of Charles University's Third Faculty of Medicine. Runs as a single-page website with URL routes (`#/`, `#/about`, `#/directory`, `#/country/germany`, `#/doctor/...`, `#/join`, `#/dashboard`). Works with Netlify; no frontend build command needed.

## Start in VS Code

1. Extract the ZIP and open the **lf3-alumni** folder in VS Code.
2. Open `index.html` with **Live Server** to preview.
3. To publish, push the entire folder to GitHub, then Netlify → Add new project → Import an existing project → GitHub. Publish directory `.` and no build command.
4. The demo has **five fictional alumni**, clearly marked as sample profiles. It is safe to preview without a database; buttons for real messaging and account registration require Supabase.

## What to edit

| Want to change | File |
| --- | --- |
| Website name, home headline, introduction | `countries.js` → `LF3_SITE` |
| Country names, flags, order, headings, colours | `countries.js` → `LF3_COUNTRIES` |
| Each country's individual background | `countries.js` → each country's `background` |
| Country skyline images | `assets/countries/*.svg` (replace with your own JPEG/PNG if you wish) |
| Home page background | `countries.js` → `homeBackground` |
| Layout, fonts, colours, card spacing | `styles.css` |
| Pages, navigation, sample profile previews | `app.js` |
| Supabase public project URL/key | `config.js` |
| Database and permissions | `schema.sql` |

Example country photograph: place `germany.jpg` in `assets/countries/`, then replace `background:'assets/countries/germany.svg'` with `background:'assets/countries/germany.jpg'` in `countries.js`. Use images you own or are licensed to display.

Country cards use emoji flags; these render on most modern operating systems. If you prefer photo flags or SVGs, modify the `cardCountry` function in `app.js`.

## Activate doctor accounts, self-edits, contact requests

1. Create a [Supabase](https://supabase.com/) project.
2. In its SQL editor, run **`schema.sql`** on a fresh project. This creates accounts, alumni profiles, contact requests, view, RLS policies, admin review functions, and profile re-review on substantive edits.
3. In Supabase → Project Settings → API, copy the Project URL and **publishable / anon key** into `config.js`. A publishable/anon key is intended for the frontend when row-level security is correctly enabled. **Never use service-role or secret keys in browser files.**
4. Configure Supabase Auth → URL Configuration: set your published Netlify URL and add its URL as an allowed redirect destination; configure email confirmation as appropriate.
5. Sign up an admin account on your published site. In Supabase SQL editor (only, not in the browser), assign admin privilege:

```sql
insert into public.admins (user_id)
select id from auth.users where email = 'YOUR_ADMIN_EMAIL@YOUR_DOMAIN';
```

6. Alumni choose the `alumnus` account type, fill out their profile, consent to publishing, and submit for admin review. Once approved, signed-in users can see the profile in its country and individual doctor page. Approved alumni can edit their profiles; material changes set the profile back to pending review.
7. Signed-in members can request contact. Alumni see requests in their dashboard and can accept/decline, replying privately. The backend currently delivers requests **inside the site dashboards**, not by email.

## Important launch checklist

- Real student/alumni identity verification is **not automatic**. Do not rely on a self-declared account type or email confirmation alone to prove university affiliation. Add verification or manually validate members before admitting them to a real private network.
- Test Auth sign-up, email confirmation, sign-in, logout, alumni creation, admin approval, profile re-review, request delivery, accept/decline and all RLS rules with separate test accounts before announcing a public launch.
- Add privacy and terms pages, lawful basis/consent text, a data deletion workflow and appropriate administrative controls for GDPR compliance.
- Set up email notifications separately if needed. They are not implemented in this starter.
- The demo country backgrounds are **original abstract skyline illustrations**, not geographical photographs. You can swap them for each destination's licensed photograph.
- If a Supabase project already uses the previous `schema.sql`, review the differences and migrate carefully rather than rerunning from scratch blindly.
