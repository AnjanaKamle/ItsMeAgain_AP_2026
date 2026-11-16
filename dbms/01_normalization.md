# Database Normalization

This document explains how the authentication app’s data is organized to reduce duplication and keep related information consistent.

## 1NF: Keep each value in one place

The tables store one record per account, trusted phone, login challenge, browser session, recovery code, or audit event. Each column holds one value. For example, a user’s trusted devices are stored as separate rows in `trusted_devices`, rather than as a list inside the `users` row.

The design avoids repeating groups such as `device_1`, `device_2`, and `device_3`.

## 2NF: Keep facts about each thing together

Each table has a primary key that identifies one row. The tables do not use a multi-column primary key, so there are no columns that depend on only part of a primary key.

The recovery-code table also prevents duplicate codes for the same user with `UNIQUE (user_id, code_hash)`. Each recovery code’s creation and use timestamps describe that specific code.

## 3NF: Store each fact with the thing it describes

Information about a user is stored in `users`. Device information is stored in `trusted_devices`. Challenges, browser sessions, recovery codes, and audit events each have their own tables.

Other tables refer to users or devices by ID. This avoids copying details such as a user’s email into every device, challenge, and session row. Updating an email therefore requires changing it in one place.

## Tables and functional dependencies

A functional dependency means that one value (or set of values) identifies the other values in a row.

- **users**
  - `id → email, password_hash, created_at`
  - `email → id, password_hash, created_at` because email is unique.
- **trusted_devices**
  - `id → user_id, device_name, public_key_pem, created_at, revoked_at`
- **login_challenges**
  - `id → secret_hash, state, created_at, expires_at, consumed_at, approved_user_id, approved_device_id`
  - `secret_hash` is also unique and identifies a challenge.
- **browser_sessions**
  - `id → user_id, device_id, challenge_id, created_at, expires_at, revoked_at`
  - `challenge_id` is unique, so it can identify at most one browser session.
- **recovery_codes**
  - `id → user_id, code_hash, created_at, used_at`
  - `(user_id, code_hash) → id, created_at, used_at` because that pair is unique.
- **audit_events**
  - `id → user_id, event_type, created_at`
- **account_sessions**
  - `id → user_id, token_hash, created_at, expires_at, revoked_at`
  - `token_hash` is also unique.

## Why the tables are separate

- One user can enroll multiple trusted devices.
- A login challenge is a short-lived request and is stored separately from the device that approves it.
- A browser session records the result of an approved challenge.
- Recovery codes and account sessions can each be used or revoked independently.
- Audit events record security-related activity without storing a copy of all user details.

## Constraints and relationships

- Primary keys identify rows.
- Foreign keys connect devices, challenges, sessions, recovery codes, and audit events to their related users or devices.
- Unique constraints prevent duplicate emails, challenge hashes, session token hashes, and repeated recovery codes for one user.
- Check constraints restrict challenge states and require session and challenge expiry times to be later than their creation times.

## Scope note

This document describes the schema currently in `db/schema.sql`. The database currently stores a trusted device’s public key as `public_key_pem`. The phone’s private signing key must remain on the phone and must not be stored in this database.