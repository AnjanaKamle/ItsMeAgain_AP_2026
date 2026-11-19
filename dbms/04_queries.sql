-- SQL used by the current API code.
-- Values are passed as PostgreSQL parameters ($1, $2, and so on).
-- Account creation is for local development only.
-- Device enrollment, QR approval, browser sessions, and recovery are not implemented yet.

-- APQ-001: Create a development account
-- WRITE
INSERT INTO users (id, email, password_hash)
VALUES ($1, $2, $3)
RETURNING id, email, created_at;

-- APQ-002: Find an account during sign-in
-- READ
SELECT id, email, password_hash
FROM users
WHERE email = $1;

-- APQ-003: Save a new account session
-- WRITE
INSERT INTO account_sessions (id, user_id, token_hash, expires_at)
VALUES ($1, $2, $3, $4);

-- APQ-004: Check whether an account session is still active
-- READ
SELECT users.id, users.email, account_sessions.expires_at
FROM account_sessions
JOIN users ON users.id = account_sessions.user_id
WHERE account_sessions.token_hash = $1
  AND account_sessions.revoked_at IS NULL
  AND account_sessions.expires_at > NOW();

-- APQ-005: Sign out by revoking the current session
-- WRITE
UPDATE account_sessions
SET revoked_at = NOW()
WHERE token_hash = $1
  AND revoked_at IS NULL;

-- APQ-006: Check that PostgreSQL responds
-- READ
SELECT NOW();

-- APQ-007: Start the password-change transaction
-- WRITE
BEGIN;

-- APQ-008: Lock and read the current password hash
-- READ
SELECT password_hash
FROM users
WHERE id = $1
FOR UPDATE;

-- APQ-009: Cancel the password change if the current password is wrong
-- WRITE
ROLLBACK;

-- APQ-010: Save the new password hash
-- WRITE
UPDATE users
SET password_hash = $1
WHERE id = $2;

-- APQ-011: Sign out the user's other active sessions after a password change
-- WRITE
UPDATE account_sessions
SET revoked_at = NOW()
WHERE user_id = $1
  AND revoked_at IS NULL;

-- APQ-012: Finish a successful password change
-- WRITE
COMMIT;

-- APQ-013: Create a sign-in challenge
-- WRITE
INSERT INTO login_challenges (id, secret_hash, expires_at)
VALUES ($1, $2, $3);

-- APQ-014: Check a challenge's state and expiry
-- READ
SELECT
  CASE
    WHEN state = 'pending' AND expires_at <= NOW() THEN 'expired'
    ELSE state
  END AS state,
  expires_at
FROM login_challenges
WHERE id = $1;
