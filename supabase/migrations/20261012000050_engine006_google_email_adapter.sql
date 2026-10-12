-- ============================================================================
-- TRS026 Construction Directive WP7 (section 2.8) -- Google email is the email
-- provider (Founder decision). The gateway's adapter (integration-gateway/gmail.ts)
-- sends through the Gmail API, as a Google Workspace mailbox (service account
-- with domain-wide delegation) or any Google mailbox (OAuth refresh token).
-- The register records it as built and awaiting credentials; the port stays on
-- the simulator until the Office switches it.
-- ============================================================================

UPDATE trustride.integration_port_registry SET
  live_adapter = 'BUILT',
  readiness = 'LIVE_READY_PENDING_CREDENTIALS',
  primary_vendor = 'Google (Gmail API, gmail.send scope)',
  live_operations = ARRAY['NOTIFY_EMAIL (Gmail API users.messages.send)'],
  blocking_dependency = 'Google mailbox and credentials as Edge secrets: GMAIL_AUTH_MODE with either a Workspace service account granted domain-wide delegation for gmail.send (GMAIL_SERVICE_ACCOUNT_JSON) or an OAuth client and refresh token (GMAIL_CLIENT_ID, GMAIL_CLIENT_SECRET, GMAIL_REFRESH_TOKEN); GMAIL_SENDER. A consumer Gmail account sends about 500 messages a day and its OAuth app must be published (gmail.send is a sensitive scope) or refresh tokens expire after 7 days.'
WHERE port_code = 'EMAIL_SERVICE' AND active;

SELECT trustride.fn_platform_conformance_assert();
