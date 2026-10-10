-- ============================================================================
-- Platform -- index hygiene
-- TRS026-ENG-REMEDIATION-001, finding D21
-- ============================================================================
-- Forensic audit 2026-10-08: four duplicate index pairs (a unique
-- constraint plus an explicit index on the same column) and 87 foreign keys
-- without a supporting index.
--
-- Correction:
--   * the redundant explicit index of the three non-Engine 5 pairs is
--     dropped (the unique constraint's index stays and serves every lookup);
--   * the 19 foreign keys on tables in operational use (tables holding
--     data on staging) are indexed: order, job, support, session,
--     workforce, custody, telemetry, credential, verification, marketplace,
--     coordination and advisory lookups.
-- Not changed: Engine 5 (cost_ea_rate's duplicate pair and the 24 cost and
-- fare foreign keys) by Founder ruling; the 44 foreign keys on tables no flow
-- has written yet (indexed when a flow first writes them).
-- ============================================================================

DROP INDEX trustride.uq_platform_users_global_uid;
DROP INDEX trustride.idx_resource_fleet_object;
DROP INDEX trustride.idx_integration_circuit_breaker_port;

CREATE INDEX idx_business_job_order_line ON trustride.business_job (order_line_id);
CREATE INDEX idx_business_support_case_job ON trustride.business_support_case (job_id);
CREATE INDEX idx_business_support_case_order ON trustride.business_support_case (order_id);
CREATE INDEX idx_business_support_message_case ON trustride.business_support_message (case_id);
CREATE INDEX idx_coord_admission_decision_session ON trustride.coord_admission_decision (admission_session_id);
CREATE INDEX idx_coord_admission_session_policy ON trustride.coord_admission_session (admission_policy_id);
CREATE INDEX idx_entity_system_credential_issued_by ON trustride.entity_system_credential (issued_by);
CREATE INDEX idx_entity_system_credential_system_user ON trustride.entity_system_credential (system_user_id);
CREATE INDEX idx_object_registry_custody_entity ON trustride.object_registry (custody_entity_id);
CREATE INDEX idx_object_registry_custody_user ON trustride.object_registry (custody_user_id);
CREATE INDEX idx_orch_routing_audit_decision ON trustride.orch_routing_audit (routing_decision_id);
CREATE INDEX idx_present_shell_session_access ON trustride.present_shell_session (access_id);
CREATE INDEX idx_present_shell_session_acting_person ON trustride.present_shell_session (acting_person_user_id);
CREATE INDEX idx_resource_custody_log_estate ON trustride.resource_custody_log (location_estate_id);
CREATE INDEX idx_resource_location_event_binding ON trustride.resource_location_event (binding_id);
CREATE INDEX idx_resource_workforce_unit_estate ON trustride.resource_workforce_unit (primary_estate_id);
CREATE INDEX idx_service_marketplace_listing_service ON trustride.service_marketplace_listing (service_id);
CREATE INDEX idx_verification_record_subject_object ON trustride.verification_record (subject_object_id);
CREATE INDEX idx_advisory_forecast_model ON trustride.advisory_forecast (model_id);

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA trustride FROM PUBLIC;
SELECT trustride.fn_platform_conformance_assert();
