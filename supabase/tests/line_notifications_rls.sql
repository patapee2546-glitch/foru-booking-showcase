begin;

create extension if not exists pgtap with schema extensions;
select plan(7);

insert into auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  ('11000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'line-customer@example.test', '', now(), '{}', '{}', now(), now()),
  ('11000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'line-owner@example.test', '', now(), '{"role":"owner"}', '{}', now(), now())
on conflict (id) do nothing;

insert into public.demo_slots (slot_date, start_time, end_time, is_open, updated_by)
values (current_date + 2, time '10:00', time '12:30', true, '11000000-0000-0000-0000-000000000002')
on conflict (slot_date, start_time) do update set is_open = excluded.is_open;

insert into public.demo_line_links (customer_id, line_user_id, friend_verified_at)
values ('11000000-0000-0000-0000-000000000001', 'Uline-customer', now());

insert into public.demo_bookings (
  id, customer_id, slot_date, start_time, customer_name, customer_phone, removal_service, status
) values (
  '21000000-0000-0000-0000-000000000001',
  '11000000-0000-0000-0000-000000000001',
  current_date + 2, time '10:00', 'Line Customer', '0811111111', 'none', 'pending'
);

insert into public.demo_booking_line_recipients (booking_id, line_user_id)
values ('21000000-0000-0000-0000-000000000001', 'Uline-customer');

insert into public.demo_line_notifications (
  booking_id, recipient_line_user_id, notification_type, scheduled_for
) values (
  '21000000-0000-0000-0000-000000000001', 'Uline-customer', 'booking_confirmed', now()
);

set local role authenticated;
select set_config('request.jwt.claim.sub', '11000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"11000000-0000-0000-0000-000000000001","role":"authenticated","app_metadata":{}}', true);

select throws_ok(
  $$select * from public.demo_line_links$$,
  '42501',
  'permission denied for table demo_line_links',
  'customer cannot read raw LINE user IDs'
);
select throws_ok(
  $$select * from public.demo_booking_line_recipients$$,
  '42501',
  'permission denied for table demo_booking_line_recipients',
  'customer cannot read immutable booking recipients'
);
select throws_ok(
  $$select * from public.demo_line_notifications$$,
  '42501',
  'permission denied for table demo_line_notifications',
  'customer cannot read notification jobs'
);
select throws_ok(
  $$select public.demo_cancel_line_notification('31000000-0000-0000-0000-000000000001')$$,
  '42501',
  null,
  'customer cannot execute internal notification RPCs'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '11000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"11000000-0000-0000-0000-000000000002","role":"authenticated","app_metadata":{"role":"owner"}}', true);
select is(
  (select count(*)::int from public.demo_line_notifications),
  1,
  'owner can read notification status rows'
);

reset role;
update public.demo_bookings
set status = 'approved'
where id = '21000000-0000-0000-0000-000000000001';
insert into public.demo_line_notifications (
  booking_id, recipient_line_user_id, notification_type, scheduled_for
) values (
  '21000000-0000-0000-0000-000000000001', 'Uline-customer',
  'appointment_reminder', now() + interval '1 day'
);
update public.demo_bookings
set status = 'cancelled'
where id = '21000000-0000-0000-0000-000000000001';
select is(
  (select status from public.demo_line_notifications
    where booking_id = '21000000-0000-0000-0000-000000000001'
      and notification_type = 'appointment_reminder'),
  'cancelled',
  'cancelling a booking cancels its unsent reminder'
);

update public.demo_bookings
set status = 'approved'
where id = '21000000-0000-0000-0000-000000000001';
update public.demo_line_notifications
set status = 'pending', scheduled_for = now()
where booking_id = '21000000-0000-0000-0000-000000000001'
  and notification_type = 'appointment_reminder';
update public.demo_bookings
set slot_date = current_date + 3
where id = '21000000-0000-0000-0000-000000000001';
select is(
  (select scheduled_for from public.demo_line_notifications
    where booking_id = '21000000-0000-0000-0000-000000000001'
      and notification_type = 'appointment_reminder'),
  ((current_date + 3 + time '10:00') at time zone 'Asia/Bangkok') - interval '1 hour',
  'moving an approved booking recalculates its unsent reminder'
);

select * from finish();
rollback;
