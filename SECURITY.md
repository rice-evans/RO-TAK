# Security Policy

## Supported versions

Only the latest release and the current `main` branch get security fixes.

## Reporting a vulnerability

Do not open a public issue.

- Use GitHub's private reporting: the **Security** tab of this repo, then **Report a vulnerability**.
- Or message me on Discord: `rice.e`.

Include what you found, how to reproduce it, which part it affects (website, desktop app, database, upload function) and a fix if you have one.

I will reply within 7 days and fix by severity. You are credited in the fix unless you want to stay anonymous. There is no bounty.

## How it is built

- **Secrets.** The OpenAI key and the Supabase service key live only in Supabase secrets and are never committed. The Supabase publishable key in `index.html` is public by design. What it can do is limited by the database rules in `supabase/`.
- **Rooms.** There are no accounts. Anyone with a room code can join it. The creator of a room is its host, and a host key stored in their browser proves it. Locking, bulk clearing and map changes are enforced in the database, not only in the page. Rooms are deleted after 2 hours with nobody connected.
- **Uploads.** Maps go through the `upload-map` function, which checks the file type and size and runs OpenAI's moderation check before storing anything. Direct writes to the storage bucket are removed. If the check cannot run, the upload is refused.
- **Text.** Slurs are blocked in the page and again in the database.
- **Shared data.** Everything received from a room is validated before it is drawn.
- **Desktop app.** It loads only the bundled `index.html`, never a remote page. Node integration is enabled, so anything that makes room data run as script would run on the user's computer. Reports of that kind are treated as high severity.

## Scope

In scope:

- the code in this repo
- the database rules and the `upload-map` function
- bypassing the host or lock rules
- bypassing the upload check
- script injection through room data or map files
- anything in the desktop app that runs code or reads files it should not
- dependencies with a real attack path

Out of scope:

- Supabase, Vercel, GitHub and OpenAI themselves
- social engineering
- denial of service and spam
- forks and modified copies
- the public Supabase publishable key
- anyone with a room code being able to join that room

Test only against rooms you created.
