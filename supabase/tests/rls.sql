begin;

create extension if not exists pgtap with schema extensions;
select plan(14);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'customer-a@example.test', '', now(), '{}', '{}', now(), now()),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'customer-b@example.test', '', now(), '{}', '{}', now(), now()),
  ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner@example.test', '', now(), '{"role":"owner"}', '{}', now(), now())
on conflict (id) do nothing;

insert into public.demo_slots (slot_date, start_time, end_time, is_open, updated_by)
values (current_date + 1, time '10:00', time '12:30', true, '10000000-0000-0000-0000-000000000003')
on conflict (slot_date, start_time) do update set is_open = excluded.is_open;

set local role anon;
select throws_ok(
  $$select * from public.demo_slots$$,
  '42501',
  'permission denied for table demo_slots',
  'signed-out visitor cannot read slots'
);
select throws_ok(
  $$select * from public.demo_bookings$$,
  '42501',
  'permission denied for table demo_bookings',
  'signed-out visitor cannot read bookings'
);

reset role;
insert into public.demo_bookings (
  id, customer_id, slot_date, start_time, customer_name, customer_phone, removal_service, status, created_at, expires_at
) values (
  '20000000-0000-0000-0000-000000000001',
  '10000000-0000-0000-0000-000000000001',
  current_date + 1, time '10:00', 'Customer A', '0810000001', 'none', 'pending', now(), now() + interval '5 minutes'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated","app_metadata":{}}', true);
select throws_ok(
  $$insert into public.demo_bookings (
      id, customer_id, slot_date, start_time, customer_name, customer_phone, removal_service, status
    ) values (
      '20000000-0000-0000-0000-000000000003',
      '10000000-0000-0000-0000-000000000001',
      current_date + 2, time '13:30', 'Forged', '0810000001', 'none', 'pending'
    )$$,
  '42501',
  null,
  'customer cannot create a booking without the verified LINE Edge Function'
);
select is(
  (select count(*)::int from public.demo_bookings), 1,
  'customer reads own booking'
);
select throws_ok(
  $$update public.demo_bookings set status = 'approved' where id = '20000000-0000-0000-0000-000000000001'$$,
  '42501',
  null,
  'customer cannot directly approve booking'
);
select throws_ok(
  $$update public.demo_slots set is_open = false where slot_date = current_date + 1 and start_time = time '10:00'$$,
  '42501',
  null,
  'customer cannot change merchant slots'
);
select lives_ok(
  $$insert into storage.objects (bucket_id, name, owner_id) values ('demo-payment-slips', '10000000-0000-0000-0000-000000000001/20000000-0000-0000-0000-000000000001/slip.jpg', '10000000-0000-0000-0000-000000000001')$$,
  'customer can upload a slip in own prefix'
);
select throws_ok(
  $$insert into storage.objects (bucket_id, name, owner_id) values ('demo-payment-slips', '10000000-0000-0000-0000-000000000002/20000000-0000-0000-0000-000000000002/slip.jpg', '10000000-0000-0000-0000-000000000001')$$,
  '42501',
  null,
  'customer cannot upload a slip in another customer prefix'
);

reset role;
insert into public.demo_bookings (
  id, customer_id, slot_date, start_time, customer_name, customer_phone, removal_service, status, created_at, expires_at
) values (
  '20000000-0000-0000-0000-000000000002',
  '10000000-0000-0000-0000-000000000002',
  current_date + 1, time '10:00', 'Customer B', '0820000002', 'gel', 'pending', now(), now() + interval '5 minutes'
);
insert into storage.objects (bucket_id, name, owner_id)
values (
  'demo-payment-slips',
  '10000000-0000-0000-0000-000000000002/20000000-0000-0000-0000-000000000002/slip.jpg',
  '10000000-0000-0000-0000-000000000002'
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated","app_metadata":{}}', true);
select is(
  (select count(*)::int from public.demo_bookings where customer_phone = '0820000002'), 0,
  'customer A cannot read customer B'
);
select is(
  (select count(*)::int from storage.objects where bucket_id = 'demo-payment-slips' and name like '10000000-0000-0000-0000-000000000002/%'), 0,
  'customer A cannot read customer B slip'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000003', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated","app_metadata":{"role":"owner"}}', true);
select is(
  (select count(*)::int from public.demo_bookings where removal_service in ('none', 'gel')), 2,
  'owner reads booking metadata'
);
select is(
  (select count(*)::int from storage.objects where bucket_id = 'demo-payment-slips'), 2,
  'owner reads all payment slips'
);
select lives_ok(
  $$update public.demo_slots set is_open = false, updated_by = '10000000-0000-0000-0000-000000000003' where slot_date = current_date + 1 and start_time = time '10:00'$$,
  'owner may close an unapproved slot'
);

reset role;
update public.demo_bookings set status = 'approved' where id = '20000000-0000-0000-0000-000000000001';
select throws_ok(
  $$update public.demo_bookings set status = 'approved' where id = '20000000-0000-0000-0000-000000000002'$$,
  '23505',
  null,
  'unique index prevents two approved bookings'
);

select * from finish();
rollback;
