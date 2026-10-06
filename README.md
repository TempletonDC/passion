# Passion Project Workbook: setup guide

This folder is a complete website. Students create an account with a username and password, fill in the workbook, and it saves to their account. Each student sees only their own workbook. An advisor sees the workbooks of the students who chose them (read only). An admin sees every student and can change advisors.

The site is plain files (no server to run). Saving and sign-in are handled by a free-to-start hosted database called Supabase. You do this setup once, in about 20 minutes.

## What is in this folder

| File | What it does |
|---|---|
| `index.html` | The whole workbook and sign-in screens |
| `config.js` | The two values that connect the site to your database (you fill these in) |
| `supabase.js` | The Supabase browser library, included so the site does not depend on another website |
| `setup.sql` | Creates the tables and the privacy rules in your database |

## 1. Create the database

1. Go to supabase.com, sign in, and choose **New project**. Name it "passion-workbook", pick a region in the United States, and set a database password (store it in your password manager; you will rarely need it).
2. Wait for the project to finish starting.

## 2. Load the setup file

1. In the project, open **SQL Editor** and choose **New query**.
2. Open `setup.sql` in a text editor, copy everything, paste it into the query box, and press **Run**. You should see "Success. No rows returned."
3. Change the class code students will need to create an account. In a new query, run:

   ```sql
   update public.app_settings set value = 'pick-a-code-here' where key = 'signup_code';
   ```

## 3. Change three sign-in settings

Open **Authentication** in the left menu.

1. **Sign In / Providers > Email**: turn **off** "Confirm email". Students use a username, not a real email, so no confirmation email can be sent. Leave "Enable email provider" on.
2. In the same place, set **Minimum password length** to 8 or more.
3. **Providers**: leave every other provider (Google, GitHub and so on) off.

## 4. Connect the site to the database

1. In **Project Settings > API**, copy the **Project URL** and the **anon public** key.
2. Open `config.js` and paste them between the quotes. Both values are safe to publish. The rules in `setup.sql` decide who can see what, not secrecy of the key. Never paste the `service_role` key anywhere on the site.

## 5. Put the site online at passion.templetonacademy.org

1. Upload `index.html`, `config.js` and `supabase.js` to your static host, all in the same folder. (`setup.sql` and this guide stay with you.)
2. Point the subdomain at that host (your DNS manager adds the record your host tells you to add, usually a CNAME for `passion`).
3. Make sure the host serves the site over **HTTPS**. Passwords travel over this connection.

## 6. Create your admin account and your advisors

1. Open the site and choose **Create account**. Use your name, a username, a password, and the class code from step 2. Advisor can stay blank.
2. In Supabase, **SQL Editor**, run (with your username):

   ```sql
   update public.profiles set role = 'admin' where username = 'your-username';
   ```

3. Each advisor creates an account the same way, then you run:

   ```sql
   update public.profiles set role = 'advisor' where username = 'their-username';
   ```

4. Students now see their advisor in the drop-down when they create an account. Admins can change a student's advisor from the student list.

## Day-to-day

- **A student forgot their password.** Accounts use a made-up address (`username@passion.templetonacademy.org`), so there is no email reset. In **SQL Editor** run the following with the student's username and a temporary password, then tell the student to sign in with it:

  ```sql
  update auth.users
  set encrypted_password = crypt('temporary-password-here', gen_salt('bf'))
  where email = 'their-username@passion.templetonacademy.org';
  ```

- **Change the class code** at any time with the `update public.app_settings` query above. Existing accounts are not affected.
- **Remove a student.** Authentication > Users > delete the user. Their workbook is deleted with them.
- **Export everything.** Table Editor > `workbooks` > Export, or have a student use "Download completed workbook" on the last step.

## Check it works (about 5 minutes)

1. Create a test student with the class code and pick an advisor. The workbook should open with their name filled in.
2. Type in a few boxes, wait for "Saved to your account", sign out, sign in again. The answers should be there.
3. Sign in as the advisor. The student should appear with a progress bar, and opening them should show a read-only workbook.
4. Sign in as a second student. They should not see the first student's work.

## Things to decide before students use it

- **Student data.** The site stores students' names, usernames and everything they write. Supabase holds it on your behalf. Check this against your school's data and privacy policy and agree who is allowed to see it. Advisors see only students who chose them, and admins see everyone.
- **Plan limits.** Check Supabase's current plan terms. Free projects have historically paused after a stretch of inactivity and do not include automatic backups. A school running this all year should consider a paid plan.
- **Two windows.** If a student has the workbook open on two devices, the second window that saves is told to reload so one device never overwrites the other.
