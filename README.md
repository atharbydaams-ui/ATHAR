# ATHAR — setup
1. Create a Supabase project. SQL Editor → run `supabase/schema.sql`.
2. Authentication → Users → add your admin (email+password), then run the last commented line of schema.sql with your email.
3. Put Project URL + **anon** key in `config.js` (never the service-role key).
4. Deploy the folder to GitHub Pages / Netlify / Vercel. Store = `index.html`, dashboard = `admin.html`. Admin security is enforced by database policies, not by the URL.
5. Edit the placeholder Instagram/phone/about text in `index.html`; delivery fee is `FEE` in index.html AND `fee` in `place_order` (schema.sql) — the server value is the one charged.
Disable public sign-ups in Supabase Auth settings.
