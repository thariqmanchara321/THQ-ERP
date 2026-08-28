# Security notes

- Flutter contains only the Supabase URL + publishable key.
- Service-role/secret keys are used only inside Edge Functions.
- Username mappings and hidden Auth email values are not directly readable by normal clients.
- Client/POS device secrets are stored in platform secure storage and only their SHA-256 hashes are held in the database.
- One-time activation codes are hashed, expire after 24 hours and are cleared after activation.
- A revoked device can no longer authenticate Client/POS users.
- Tenant membership is rechecked during Client/POS username login.
- Account password minimum is 8 characters even though usernames can be 4 characters.
- Posted sale quantity/price/tax/stock data is not silently edited. Safe metadata edits are audited. A future void/reverse/recreate transaction is the correct way to correct financial lines.
- Business and error audit records are server-written through protected functions.
