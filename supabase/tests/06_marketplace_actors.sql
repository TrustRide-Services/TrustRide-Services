-- Suite 06 -- Journey E (Marketplace: own stock and vendors), partner
-- contribution, Journey H (governance: request -> approval -> capability ->
-- audit), intermediary referrals, Office user management.
DO $$
DECLARE
  founder UUID; admin UUID; buyer UUID; buyer2 UUID; vendor UUID; vendor2 UUID; partner UUID; gov UUID; inter UUID; cust UUID;
  est UUID; r JSONB; item UUID; listing UUID; vlisting UUID; car_listing UUID; ord UUID; o RECORD; v TEXT; n INT; obj UUID; code TEXT; p RECORD;
BEGIN
  PERFORM pg_temp.t_open_all_hours();
  founder := pg_temp.t_person('Founder', NULL);  PERFORM pg_temp.t_role(founder, 'FOUNDER');
  admin := pg_temp.t_person('Admin', NULL);  PERFORM pg_temp.t_role(admin, 'ADMINISTRATOR');
  buyer := pg_temp.t_customer('Buyer');
  buyer2 := pg_temp.t_customer('Buyer Two');
  vendor := pg_temp.t_customer('Vendor Motors');
  vendor2 := pg_temp.t_customer('Other Vendor');
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_ESTATE',
    '{"estate_code":"M-YARD","estate_type":"STORAGE_FACILITY","estate_name":"Marketplace Yard","lat":-0.10,"lon":34.75}');
  est := (r->>'signal')::uuid;
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REGISTER_ESTATE',
    '{"estate_code":"M-HUB","estate_type":"OPERATING_HUB","estate_name":"Main Hub","lat":-0.09,"lon":34.76}');

  -- ===================================== Journey E: own marketplace stock
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'ACQUIRE_INVENTORY', jsonb_build_object('vehicle_category', 'MOTORCYCLE',
    'make', 'TVS', 'model', 'HLX 125', 'year', 2023, 'plate_number', 'KMEA 777E', 'acquisition_cost_kes', 70000, 'custody_estate_id', est));
  PERFORM pg_temp.t_check('Office acquires a motorcycle into marketplace stock', r->>'status' = 'TRANSLATED', r::text);
  item := (r->>'signal')::uuid;
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'PUBLISH_OFFER', jsonb_build_object('inventory_item_id', item, 'title', 'TVS HLX 125', 'price_kes', 95000));
  PERFORM pg_temp.t_check('stock cannot be listed before it is compliant', r->>'status' = 'REJECTED', r::text);
  PERFORM pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'ADVANCE_INVENTORY', jsonb_build_object('inventory_item_id', item, 'new_state', 'INSPECTED', 'inspection_status', 'PASSED'));
  PERFORM pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'ADVANCE_INVENTORY', jsonb_build_object('inventory_item_id', item, 'new_state', 'VALUED', 'valuation_kes', 95000));
  PERFORM pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'ADVANCE_INVENTORY', jsonb_build_object('inventory_item_id', item, 'new_state', 'REFURBISHED', 'refurbishment_status', 'DONE'));
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'ADVANCE_INVENTORY', jsonb_build_object('inventory_item_id', item, 'new_state', 'COMPLIANT', 'compliance_status', 'COMPLIANT'));
  PERFORM pg_temp.t_check('inspection -> valuation -> refurbishment -> compliance', EXISTS (SELECT 1 FROM trustride.resource_marketplace_inventory WHERE inventory_item_id = item AND lifecycle_state = 'COMPLIANT'), r::text);
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'ADVANCE_INVENTORY', jsonb_build_object('inventory_item_id', item, 'new_state', 'LISTED'));
  PERFORM pg_temp.t_check('stock cannot be marked listed or sold by hand', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'PUBLISH_OFFER', jsonb_build_object('inventory_item_id', item, 'title', 'TVS HLX 125 (2023)', 'price_kes', 95000));
  listing := (r->>'signal')::uuid;
  PERFORM pg_temp.t_check('Office publishes the offer; stock is LISTED', EXISTS (SELECT 1 FROM trustride.service_marketplace_listing WHERE listing_id = listing AND listing_status = 'LISTED')
    AND EXISTS (SELECT 1 FROM trustride.resource_marketplace_inventory WHERE inventory_item_id = item AND lifecycle_state = 'LISTED'), r::text);
  PERFORM pg_temp.t_as(buyer);
  PERFORM pg_temp.t_check('buyers see the listed offer', pg_temp.t_visible('service_marketplace_listing', format('listing_id = %L', listing)) = 1);
  PERFORM pg_temp.t_admin();

  r := pg_temp.t_cmd(buyer, 'TRUSTRIDE_MARKETPLACE', 'MARKETPLACE_APP', 'RESERVE_VEHICLE', jsonb_build_object('listing_id', listing, 'notes', 'Can I view on Saturday?'));
  PERFORM pg_temp.t_check('buyer reserves the motorcycle', r->>'status' = 'TRANSLATED', r::text);
  ord := (r->>'signal')::uuid;
  r := pg_temp.t_cmd(buyer2, 'TRUSTRIDE_MARKETPLACE', 'MARKETPLACE_APP', 'RESERVE_VEHICLE', jsonb_build_object('listing_id', listing));
  PERFORM pg_temp.t_check('a reserved vehicle cannot be reserved twice', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REVIEW_ACTOR_REQUEST', jsonb_build_object('order_id', ord, 'decision', 'ACCEPTED', 'notes', 'Viewing Saturday 10:00'));
  PERFORM pg_temp.t_cycle(8);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = ord;
  PERFORM pg_temp.t_check('Office confirms -> AWAITING_PAYMENT, M-Pesa requested', o.status = 'AWAITING_PAYMENT'
    AND EXISTS (SELECT 1 FROM trustride.integration_payment_gateway_transaction WHERE order_id = ord AND txn_status = 'PENDING_CALLBACK'), o.status::text);
  PERFORM pg_temp.t_check('buyer told on the Marketplace surface', EXISTS (
    SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = buyer AND title = 'Reservation confirmed' AND sub_shell = 'MARKETPLACE_APP'));
  PERFORM pg_temp.t_check('a Marketplace purchase never enters driver dispatch (G6)',
    NOT EXISTS (SELECT 1 FROM trustride.business_job WHERE order_id = ord)
    AND NOT EXISTS (SELECT 1 FROM trustride.business_event_outbox WHERE signal_type = 'ASSIGNMENT_REQUESTED' AND payload_in->>'order_id' = ord::text));
  r := pg_temp.t_cmd(buyer, 'TRUSTRIDE_MARKETPLACE', 'MARKETPLACE_APP', 'CONFIRM_SIMULATED_PAYMENT', jsonb_build_object('order_id', ord));
  PERFORM pg_temp.t_cycle(8);
  SELECT * INTO o FROM trustride.business_order WHERE order_id = ord;
  PERFORM pg_temp.t_check('paid -> SETTLED, listing SOLD, stock SOLD/AFTERCARE', o.status = 'SETTLED'
    AND EXISTS (SELECT 1 FROM trustride.service_marketplace_listing WHERE listing_id = listing AND listing_status = 'SOLD')
    AND EXISTS (SELECT 1 FROM trustride.resource_marketplace_inventory WHERE inventory_item_id = item AND lifecycle_state = 'AFTERCARE'), o.status::text || ' ' || r::text);
  PERFORM pg_temp.t_check('own stock earns no vendor payout', NOT EXISTS (SELECT 1 FROM trustride.business_marketplace_payout WHERE order_id = ord));
  PERFORM pg_temp.t_check('the sale signal no longer fabricates an order', NOT EXISTS (
    SELECT 1 FROM trustride.business_order WHERE requester_user_id = '00000000-0000-0000-0000-000000000000'));
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'CONFIRM_HANDOVER', jsonb_build_object('order_id', ord, 'notes', 'Keys and logbook handed over'));
  PERFORM pg_temp.t_cycle(4);
  PERFORM pg_temp.t_check('Office confirms handover -> COMPLETED, buyer told', EXISTS (SELECT 1 FROM trustride.business_order WHERE order_id = ord AND status = 'COMPLETED')
    AND EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = buyer AND title = 'Handover complete'), r::text);

  -- ===================================== vendors (5% commission)
  r := pg_temp.t_cmd(vendor, 'TRUSTRIDE_MARKETPLACE', 'VENDOR_APP', 'PUBLISH_OFFER', '{"vehicle_category":"CAR","title":"Premio","price_kes":900000}');
  PERFORM pg_temp.t_check('an unapproved vendor cannot list', r->>'status' = 'REJECTED', r::text);
  PERFORM pg_temp.t_as(vendor);  PERFORM trustride.fn_business_actor_register(vendor, 'PARTNER');  PERFORM pg_temp.t_admin();
  r := pg_temp.t_cmd(vendor, 'TRUSTRIDE_MARKETPLACE', 'VENDOR_APP', 'SUBMIT_VENDOR_LISTING',
    '{"scope_lines":[{"line_description":"Used car dealer","scope_detail":{"vehicle_category":"CAR"}}]}');
  PERFORM pg_temp.t_check('vendor applies', r->>'status' = 'TRANSLATED', r::text);
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REVIEW_ACTOR_REQUEST', jsonb_build_object('order_id', (r->>'signal')::uuid, 'decision', 'ACCEPTED'));
  PERFORM pg_temp.t_check('approval activates the vendor capability at 5%', EXISTS (
    SELECT 1 FROM trustride.business_partner_agreement pa JOIN trustride.business_actor_registration a ON a.actor_registration_id = pa.actor_registration_id
    WHERE a.user_id = vendor AND pa.partner_category = 'VENDOR' AND (pa.agreement_terms->>'commission_pct')::numeric = 5), r::text);
  r := pg_temp.t_cmd(vendor, 'TRUSTRIDE_MARKETPLACE', 'VENDOR_APP', 'PUBLISH_OFFER', '{"vehicle_category":"TRUCK","title":"Lorry","price_kes":2000000}');
  PERFORM pg_temp.t_check('vendors may list only motorcycles and cars', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(vendor, 'TRUSTRIDE_MARKETPLACE', 'VENDOR_APP', 'PUBLISH_OFFER', '{"vehicle_category":"MOTORCYCLE","title":"Bajaj Boxer 150","price_kes":110000}');
  vlisting := (r->>'signal')::uuid;
  PERFORM pg_temp.t_check('approved vendor lists a motorcycle', r->>'status' = 'TRANSLATED', r::text);
  r := pg_temp.t_cmd(vendor, 'TRUSTRIDE_MARKETPLACE', 'VENDOR_APP', 'PUBLISH_OFFER', '{"vehicle_category":"CAR","title":"Toyota Fielder","price_kes":650000}');
  car_listing := (r->>'signal')::uuid;

  r := pg_temp.t_cmd(buyer, 'TRUSTRIDE_MARKETPLACE', 'MARKETPLACE_APP', 'RESERVE_VEHICLE', jsonb_build_object('listing_id', vlisting));
  ord := (r->>'signal')::uuid;
  PERFORM pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REVIEW_ACTOR_REQUEST', jsonb_build_object('order_id', ord, 'decision', 'ACCEPTED'));
  PERFORM pg_temp.t_cycle(6);
  PERFORM pg_temp.t_cmd(buyer, 'TRUSTRIDE_MARKETPLACE', 'MARKETPLACE_APP', 'CONFIRM_SIMULATED_PAYMENT', jsonb_build_object('order_id', ord));
  PERFORM pg_temp.t_cycle(8);
  SELECT * INTO p FROM trustride.business_marketplace_payout WHERE order_id = ord;
  PERFORM pg_temp.t_check('vendor sale: 5% commission, 95% payout', p.gross_kes = 110000 AND p.commission_kes = 5500 AND p.payout_kes = 104500 AND p.status = 'PENDING',
    coalesce(p.gross_kes::text, 'no payout') || '/' || coalesce(p.commission_kes::text, '') || '/' || coalesce(p.payout_kes::text, ''));
  PERFORM pg_temp.t_check('vendor told the vehicle sold', EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = vendor AND title LIKE 'Sold:%'));
  r := pg_temp.t_cmd(vendor2, 'TRUSTRIDE_MARKETPLACE', 'VENDOR_APP', 'CONFIRM_HANDOVER', jsonb_build_object('order_id', ord));
  PERFORM pg_temp.t_check('another vendor cannot confirm my handover', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(vendor, 'TRUSTRIDE_MARKETPLACE', 'VENDOR_APP', 'CONFIRM_HANDOVER', jsonb_build_object('order_id', ord, 'notes', 'Delivered'));
  PERFORM pg_temp.t_cycle(8);
  PERFORM pg_temp.t_check('handover pays the vendor (B2C, simulator)', EXISTS (SELECT 1 FROM trustride.business_marketplace_payout WHERE order_id = ord AND status = 'PAID'), r::text);

  -- above the M-Pesa limit -> bank transfer
  r := pg_temp.t_cmd(buyer2, 'TRUSTRIDE_MARKETPLACE', 'MARKETPLACE_APP', 'RESERVE_VEHICLE', jsonb_build_object('listing_id', car_listing));
  ord := (r->>'signal')::uuid;
  PERFORM pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REVIEW_ACTOR_REQUEST', jsonb_build_object('order_id', ord, 'decision', 'ACCEPTED'));
  PERFORM pg_temp.t_cycle(6);
  PERFORM pg_temp.t_check('a car above the STK limit is set up for bank transfer (no STK sent)', EXISTS (
    SELECT 1 FROM trustride.business_settlement WHERE order_id = ord AND payment_rail = 'BANK_TRANSFER')
    AND NOT EXISTS (SELECT 1 FROM trustride.integration_payment_gateway_transaction WHERE order_id = ord));
  PERFORM pg_temp.t_check('Office alerted to send bank details', EXISTS (SELECT 1 FROM trustride.present_notification_inbox WHERE recipient_user_id = founder AND category = 'ORDER_EXCEPTION'));
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'RECORD_BANK_PAYMENT', jsonb_build_object('order_id', ord, 'amount_kes', 650000, 'bank_reference', 'KCB-TT-5521'));
  PERFORM pg_temp.t_cycle(8);
  PERFORM pg_temp.t_check('recorded bank transfer completes the sale', EXISTS (SELECT 1 FROM trustride.service_marketplace_listing WHERE listing_id = car_listing AND listing_status = 'SOLD')
    AND EXISTS (SELECT 1 FROM trustride.business_marketplace_payout WHERE order_id = ord AND commission_kes = 32500), r::text);

  -- declined / cancelled / expired reservations return the vehicle to sale
  r := pg_temp.t_cmd(vendor, 'TRUSTRIDE_MARKETPLACE', 'VENDOR_APP', 'PUBLISH_OFFER', '{"vehicle_category":"MOTORCYCLE","title":"Honda CB","price_kes":120000}');
  vlisting := (r->>'signal')::uuid;
  r := pg_temp.t_cmd(buyer, 'TRUSTRIDE_MARKETPLACE', 'MARKETPLACE_APP', 'RESERVE_VEHICLE', jsonb_build_object('listing_id', vlisting));
  PERFORM pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REVIEW_ACTOR_REQUEST', jsonb_build_object('order_id', (r->>'signal')::uuid, 'decision', 'DECLINED', 'notes', 'Sold offline'));
  PERFORM pg_temp.t_check('declined reservation -> vehicle back on sale', EXISTS (SELECT 1 FROM trustride.service_marketplace_listing WHERE listing_id = vlisting AND listing_status = 'LISTED'));
  r := pg_temp.t_cmd(buyer, 'TRUSTRIDE_MARKETPLACE', 'MARKETPLACE_APP', 'RESERVE_VEHICLE', jsonb_build_object('listing_id', vlisting));
  ord := (r->>'signal')::uuid;
  r := pg_temp.t_cmd(buyer, 'TRUSTRIDE_MARKETPLACE', 'MARKETPLACE_APP', 'CANCEL_ORDER', jsonb_build_object('order_id', ord));
  PERFORM pg_temp.t_check('buyer cancels before paying -> vehicle back on sale', r->>'status' = 'TRANSLATED'
    AND EXISTS (SELECT 1 FROM trustride.service_marketplace_listing WHERE listing_id = vlisting AND listing_status = 'LISTED'), r::text);
  r := pg_temp.t_cmd(buyer, 'TRUSTRIDE_MARKETPLACE', 'MARKETPLACE_APP', 'RESERVE_VEHICLE', jsonb_build_object('listing_id', vlisting));
  ord := (r->>'signal')::uuid;
  PERFORM pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REVIEW_ACTOR_REQUEST', jsonb_build_object('order_id', ord, 'decision', 'ACCEPTED'));
  PERFORM pg_temp.t_cycle(6);
  UPDATE trustride.service_marketplace_listing SET reserved_until = now() - interval '1 hour' WHERE listing_id = vlisting;
  n := trustride.fn_business_marketplace_sweep();
  PERFORM pg_temp.t_check('unpaid reservation expires -> vehicle back on sale', n = 1
    AND EXISTS (SELECT 1 FROM trustride.business_order WHERE order_id = ord AND status = 'EXPIRED')
    AND EXISTS (SELECT 1 FROM trustride.service_marketplace_listing WHERE listing_id = vlisting AND listing_status = 'LISTED'), n::text);
  r := pg_temp.t_cmd(vendor2, 'TRUSTRIDE_MARKETPLACE', 'VENDOR_APP', 'DELIST_OFFER', jsonb_build_object('listing_id', vlisting));
  PERFORM pg_temp.t_check('another vendor cannot withdraw my listing', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(vendor, 'TRUSTRIDE_MARKETPLACE', 'VENDOR_APP', 'DELIST_OFFER', jsonb_build_object('listing_id', vlisting));
  PERFORM pg_temp.t_check('vendor withdraws own listing', r->>'status' = 'TRANSLATED', r::text);

  -- ===================================== partner contribution
  partner := pg_temp.t_customer('Fleet Partner');
  PERFORM pg_temp.t_as(partner);  PERFORM trustride.fn_business_actor_register(partner, 'PARTNER');  PERFORM pg_temp.t_admin();
  r := pg_temp.t_cmd(partner, 'TRUSTRIDE_BUSINESS', 'PARTNER_APP', 'SUBMIT_CONTRIBUTION', '{"vehicles":[{"object_type":"MOTORCYCLE","plate_number":"KMFC 001A","capacity_class":"BODA_BODA"}]}');
  PERFORM pg_temp.t_check('contribution waits for partnership approval', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(partner, 'TRUSTRIDE_BUSINESS', 'PARTNER_APP', 'SUBMIT_PARTNERSHIP_REQUEST', '{"scope_lines":[{"line_description":"Fleet partnership","scope_detail":{"partner_category":"FLEET_CONTRIBUTOR"}}]}');
  PERFORM pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REVIEW_ACTOR_REQUEST', jsonb_build_object('order_id', (r->>'signal')::uuid, 'decision', 'ACCEPTED'));
  r := pg_temp.t_cmd(partner, 'TRUSTRIDE_BUSINESS', 'PARTNER_APP', 'SUBMIT_CONTRIBUTION', '{"vehicles":[
    {"object_type":"MOTORCYCLE","make":"Honda","model":"Ace","year":2025,"plate_number":"KMFC 001A","capacity_class":"BODA_BODA","inspection_status":"PASSED","insurance_status":"ACTIVE"},
    {"object_type":"CAR","make":"Toyota","model":"Axio","year":2017,"plate_number":"KDF 002B","capacity_class":"SEDAN","inspection_status":"PASSED","insurance_status":"ACTIVE"}]}');
  PERFORM pg_temp.t_check('approved partner submits two vehicles', r->>'status' = 'TRANSLATED', r::text);
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REVIEW_ACTOR_REQUEST', jsonb_build_object('order_id', (r->>'signal')::uuid, 'decision', 'ACCEPTED'));
  PERFORM pg_temp.t_cycle(8);
  SELECT count(*) INTO n FROM trustride.resource_fleet_register f JOIN trustride.object_registry ob ON ob.object_id = f.object_id
  WHERE ob.custody_user_id = partner AND f.ownership_type = 'PARTNER_CONTRIBUTED' AND f.lifecycle_state = 'VERIFIED';
  PERFORM pg_temp.t_check('approval puts both vehicles in the fleet register, NTSA-verified, partner-owned', n = 2, n::text || ' ' || r::text);
  PERFORM pg_temp.t_as(partner);
  PERFORM pg_temp.t_check('partner sees their contributed vehicles', pg_temp.t_visible('resource_fleet_register') = 2);
  PERFORM pg_temp.t_admin();

  -- ===================================== Journey H: governor
  gov := pg_temp.t_customer('County Revenue');
  PERFORM pg_temp.t_as(gov);  PERFORM trustride.fn_business_actor_register(gov, 'GOVERNOR');  PERFORM pg_temp.t_admin();
  r := pg_temp.t_cmd(gov, 'TRUSTRIDE_BUSINESS', 'GOVERNOR_APP', 'SUBMIT_REGULATORY_REQUEST',
    '{"scope_lines":[{"line_description":"Kisumu County revenue oversight","scope_detail":{"authority":"Kisumu County Revenue Board"}}]}');
  PERFORM pg_temp.t_check('governor submits a regulatory access request', r->>'status' = 'TRANSLATED', r::text);
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REVIEW_ACTOR_REQUEST', jsonb_build_object('order_id', (r->>'signal')::uuid, 'decision', 'ACCEPTED'));
  PERFORM pg_temp.t_check('approval opens an oversight engagement', EXISTS (
    SELECT 1 FROM trustride.business_governor_engagement g JOIN trustride.business_actor_registration a ON a.actor_registration_id = g.actor_registration_id
    WHERE a.user_id = gov AND g.engagement_status = 'ACTIVE'), r::text);
  PERFORM pg_temp.t_check('D4: no data rights until Office grants them', NOT EXISTS (
    SELECT 1 FROM trustride.business_governor_data_grant gr JOIN trustride.business_governor_engagement g ON g.governor_engagement_id = gr.governor_engagement_id
    JOIN trustride.business_actor_registration a ON a.actor_registration_id = g.actor_registration_id WHERE a.user_id = gov));
  r := pg_temp.t_cmd(gov, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'SET_GOVERNOR_SCOPE', jsonb_build_object('governor_user_id', gov, 'data_scope', 'AGGREGATE_REVENUE_AND_TAX'));
  PERFORM pg_temp.t_check('a governor cannot grant themselves data', r->>'status' = 'SESSION_REFUSED', r::text);
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'SET_GOVERNOR_SCOPE', jsonb_build_object('governor_user_id', gov, 'data_scope', 'AGGREGATE_SERVICE_VOLUMES'));
  PERFORM pg_temp.t_check('Office grants an aggregate scope', r->>'status' = 'TRANSLATED' AND EXISTS (
    SELECT 1 FROM trustride.business_governor_data_grant WHERE data_scope = 'AGGREGATE_SERVICE_VOLUMES' AND revoked_at IS NULL), r::text);
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'SET_GOVERNOR_SCOPE', jsonb_build_object('governor_user_id', gov, 'data_scope', 'PERSONAL_DATA_OF_RIDERS'));
  PERFORM pg_temp.t_check('there is no scope that exposes personal data', r->>'status' = 'REJECTED', r::text);
  PERFORM pg_temp.t_check('every grant is in the audit trail', EXISTS (SELECT 1 FROM trustride.audit_log WHERE action = 'GOVERNOR_SCOPE_GRANTED'));

  -- ===================================== intermediary
  inter := pg_temp.t_customer('Broker');
  PERFORM pg_temp.t_as(inter);  PERFORM trustride.fn_business_actor_register(inter, 'INTERMEDIARY');  PERFORM pg_temp.t_admin();
  r := pg_temp.t_cmd(inter, 'TRUSTRIDE_BUSINESS', 'INTERMEDIARY_APP', 'SUBMIT_FACILITATION_REQUEST',
    '{"scope_lines":[{"line_description":"Referral agent","scope_detail":{"intermediary_type":"REFERRAL_PARTNER"}}]}');
  PERFORM pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REVIEW_ACTOR_REQUEST', jsonb_build_object('order_id', (r->>'signal')::uuid, 'decision', 'ACCEPTED'));
  SELECT e.referral_code INTO code FROM trustride.business_intermediary_engagement e JOIN trustride.business_actor_registration a ON a.actor_registration_id = e.actor_registration_id WHERE a.user_id = inter;
  PERFORM pg_temp.t_check('approval issues a referral code', code ~ '^TR-[0-9A-F]{6}$', code);
  cust := pg_temp.t_customer('Referred');
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'APPLY_REFERRAL_CODE', jsonb_build_object('referral_code', lower(code)));
  PERFORM pg_temp.t_check('a customer is attributed to the intermediary', r->>'status' = 'TRANSLATED' AND EXISTS (SELECT 1 FROM trustride.business_intermediary_referral WHERE referred_user_id = cust), r::text);
  r := pg_temp.t_cmd(cust, 'TRUSTRIDE_BUSINESS', 'CUSTOMER_APP', 'APPLY_REFERRAL_CODE', jsonb_build_object('referral_code', code));
  PERFORM pg_temp.t_check('attribution happens once', r->>'status' = 'REJECTED', r::text);

  -- ===================================== Office user management
  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'GRANT_ROLE', jsonb_build_object('user_id', cust, 'role_code', 'EXECUTIVE'));
  PERFORM pg_temp.t_check('an Administrator cannot grant Office authority', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'GRANT_ROLE', jsonb_build_object('user_id', cust, 'role_code', 'FOUNDER'));
  PERFORM pg_temp.t_check('nobody is granted the Founder role', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'GRANT_ROLE', jsonb_build_object('user_id', cust, 'role_code', 'EXECUTIVE'));
  PERFORM pg_temp.t_check('the Founder grants Executive', r->>'status' = 'TRANSLATED', r::text);
  r := pg_temp.t_cmd(founder, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REVOKE_ROLE', jsonb_build_object('user_id', cust, 'role_code', 'EXECUTIVE'));
  PERFORM pg_temp.t_check('the Founder revokes it', r->>'status' = 'TRANSLATED', r::text);
  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'SUSPEND_USER', jsonb_build_object('user_id', buyer, 'reason', 'Fraud investigation'));
  PERFORM pg_temp.t_check('Office suspends a user', r->>'status' = 'TRANSLATED', r::text);
  r := pg_temp.t_cmd(buyer, 'TRUSTRIDE_MARKETPLACE', 'MARKETPLACE_APP', 'RESERVE_VEHICLE', jsonb_build_object('listing_id', listing));
  PERFORM pg_temp.t_check('a suspended user opens no shell', r->>'status' = 'SESSION_REFUSED', r::text);
  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'SUSPEND_USER', jsonb_build_object('user_id', founder, 'reason', 'x'));
  PERFORM pg_temp.t_check('the Founder cannot be suspended', r->>'status' = 'REJECTED', r::text);
  r := pg_temp.t_cmd(admin, 'TRUSTRIDE_OFFICE', 'ADMIN_CONSOLE', 'REINSTATE_USER', jsonb_build_object('user_id', buyer, 'reason', 'Cleared'));
  PERFORM pg_temp.t_check('Office reinstates the user', r->>'status' = 'TRANSLATED' AND EXISTS (SELECT 1 FROM trustride.platform_users WHERE user_id = buyer AND status = 'ACTIVE'), r::text);

  SELECT count(*) INTO n FROM (
    SELECT signal_id FROM trustride.business_event_inbox WHERE signal_status IN ('RECEIVED', 'DEAD_LETTER')
    UNION ALL SELECT signal_id FROM trustride.resource_event_inbox WHERE signal_status IN ('RECEIVED', 'DEAD_LETTER')
    UNION ALL SELECT signal_id FROM trustride.service_event_inbox WHERE signal_status IN ('RECEIVED', 'DEAD_LETTER')
    UNION ALL SELECT signal_id FROM trustride.integration_event_inbox WHERE signal_status IN ('RECEIVED', 'DEAD_LETTER')
    UNION ALL SELECT signal_id FROM trustride.present_event_inbox WHERE signal_status IN ('RECEIVED', 'DEAD_LETTER')
    UNION ALL SELECT signal_id FROM trustride.platform_event_inbox WHERE signal_status IN ('RECEIVED', 'DEAD_LETTER')) z;
  PERFORM pg_temp.t_check('no signal unprocessed or dead-lettered', n = 0, n::text || ' ' || coalesce((SELECT string_agg(failure_reason, ' | ') FROM trustride.dead_letter_review), ''));
  SELECT count(*) INTO n FROM trustride.fn_platform_conformance_violations();
  PERFORM pg_temp.t_check('conformance: zero violations', n = 0, n || ' violations');
END;
$$;
