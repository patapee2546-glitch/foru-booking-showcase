create table public.demo_line_links (
  customer_id uuid primary key references auth.users(id) on delete cascade,
  line_user_id text not null unique,
  friend_verified_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.demo_booking_line_recipients (
  booking_id uuid primary key references public.demo_bookings(id) on delete cascade,
  line_user_id text not null,
  created_at timestamptz not null default now()
);

create table public.demo_line_notifications (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.demo_bookings(id) on delete cascade,
  recipient_line_user_id text not null,
  notification_type text not null
    check (notification_type in ('booking_confirmed', 'appointment_reminder')),
  scheduled_for timestamptz not null,
  status text not null default 'pending'
    check (status in ('pending', 'processing', 'sent', 'failed', 'cancelled')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  processing_started_at timestamptz,
  last_error text,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (booking_id, notification_type)
);

create index demo_line_notifications_due_idx
  on public.demo_line_notifications (scheduled_for, status)
  where status in ('pending', 'processing');

alter table public.demo_line_links enable row level security;
alter table public.demo_booking_line_recipients enable row level security;
alter table public.demo_line_notifications enable row level security;

revoke all on table public.demo_line_links from anon, authenticated;
revoke all on table public.demo_booking_line_recipients from anon, authenticated;
revoke all on table public.demo_line_notifications from anon, authenticated;
grant select on table public.demo_line_notifications to authenticated;

create policy demo_line_notifications_owner_read
  on public.demo_line_notifications for select
  to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'owner');

drop policy if exists demo_bookings_insert_self_pending on public.demo_bookings;
revoke insert on table public.demo_bookings from authenticated;

create or replace function public.demo_link_line_customer(
  p_customer_id uuid,
  p_line_user_id text,
  p_verified_at timestamptz
) returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if p_customer_id is null or p_line_user_id !~ '^U[0-9A-Za-z_-]{8,128}$' then
    raise exception 'INVALID_LINE_LINK';
  end if;

  delete from public.demo_line_links
  where customer_id = p_customer_id and line_user_id <> p_line_user_id;

  insert into public.demo_line_links (
    customer_id, line_user_id, friend_verified_at, updated_at
  ) values (
    p_customer_id, p_line_user_id, p_verified_at, statement_timestamp()
  )
  on conflict (line_user_id) do update
  set customer_id = excluded.customer_id,
      friend_verified_at = excluded.friend_verified_at,
      updated_at = statement_timestamp();
end;
$$;

create or replace function public.demo_create_pending_booking(
  p_customer_id uuid,
  p_booking_id uuid,
  p_slot_date date,
  p_start_time time,
  p_customer_name text,
  p_customer_phone text,
  p_removal_service text,
  p_design_image_path text
) returns public.demo_bookings
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_booking public.demo_bookings%rowtype;
  v_line_user_id text;
  v_slot public.demo_slots%rowtype;
begin
  select line_user_id into v_line_user_id
  from public.demo_line_links
  where customer_id = p_customer_id;
  if v_line_user_id is null then raise exception 'LINE_FRIEND_REQUIRED'; end if;

  update public.demo_bookings
  set status = 'expired'
  where slot_date = p_slot_date
    and start_time = p_start_time
    and status = 'pending'
    and expires_at <= statement_timestamp();

  select * into v_slot
  from public.demo_slots
  where slot_date = p_slot_date and start_time = p_start_time
  for update;
  if not found or not v_slot.is_open then raise exception 'SLOT_CLOSED'; end if;

  insert into public.demo_bookings (
    id, customer_id, slot_date, start_time, customer_name, customer_phone,
    removal_service, design_image_path, status
  ) values (
    p_booking_id, p_customer_id, p_slot_date, p_start_time,
    btrim(p_customer_name), btrim(p_customer_phone), p_removal_service,
    nullif(btrim(p_design_image_path), ''), 'pending'
  ) returning * into v_booking;

  insert into public.demo_booking_line_recipients (booking_id, line_user_id)
  values (v_booking.id, v_line_user_id);

  return v_booking;
end;
$$;

create or replace function public.demo_claim_booking_and_enqueue(
  p_booking_id uuid,
  p_customer_id uuid,
  p_slip_path text
) returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_booking public.demo_bookings%rowtype;
  v_line_user_id text;
  v_slot public.demo_slots%rowtype;
begin
  select * into v_booking
  from public.demo_bookings
  where id = p_booking_id and customer_id = p_customer_id
  for update;

  if not found then return jsonb_build_object('won', false, 'status', 'lost'); end if;
  if v_booking.status = 'approved' then return jsonb_build_object('won', true, 'status', 'approved'); end if;
  if v_booking.status <> 'pending' then return jsonb_build_object('won', false, 'status', 'lost'); end if;
  if v_booking.expires_at <= statement_timestamp() then
    update public.demo_bookings set status = 'expired' where id = v_booking.id;
    return jsonb_build_object('won', false, 'status', 'expired');
  end if;

  select * into v_slot
  from public.demo_slots
  where slot_date = v_booking.slot_date and start_time = v_booking.start_time
  for update;
  if not found or not v_slot.is_open then
    update public.demo_bookings set status = 'lost' where id = v_booking.id;
    return jsonb_build_object('won', false, 'status', 'lost');
  end if;

  select line_user_id into v_line_user_id
  from public.demo_booking_line_recipients
  where booking_id = v_booking.id;
  if v_line_user_id is null then raise exception 'LINE_RECIPIENT_MISSING'; end if;

  update public.demo_bookings
  set status = 'approved',
      paid_at = statement_timestamp(),
      slip_path = p_slip_path,
      slip_uploaded_at = statement_timestamp()
  where id = v_booking.id;

  update public.demo_slots
  set is_open = false, is_booked = true, updated_at = statement_timestamp()
  where id = v_slot.id;

  insert into public.demo_line_notifications (
    booking_id, recipient_line_user_id, notification_type, scheduled_for
  ) values
    (v_booking.id, v_line_user_id, 'appointment_reminder',
      ((v_booking.slot_date + v_booking.start_time) at time zone 'Asia/Bangkok') - interval '1 hour')
  on conflict (booking_id, notification_type) do nothing;

  return jsonb_build_object('won', true, 'status', 'approved');
end;
$$;

create or replace function public.demo_claim_due_line_notifications(
  p_limit integer default 25
) returns setof public.demo_line_notifications
language sql
security invoker
set search_path = ''
as $$
  with candidates as (
    select id
    from public.demo_line_notifications
    where scheduled_for <= statement_timestamp()
      and (
        status = 'pending'
        or (status = 'processing' and processing_started_at <= statement_timestamp() - interval '5 minutes')
      )
    order by scheduled_for, created_at
    for update skip locked
    limit greatest(1, least(coalesce(p_limit, 25), 100))
  ), claimed as (
    update public.demo_line_notifications notification
    set status = 'processing',
        attempt_count = notification.attempt_count + 1,
        processing_started_at = statement_timestamp(),
        updated_at = statement_timestamp()
    from candidates
    where notification.id = candidates.id
    returning notification.*
  )
  select * from claimed;
$$;

create or replace function public.demo_claim_line_notification(
  p_id uuid
) returns public.demo_line_notifications
language plpgsql
security invoker
set search_path = ''
as $$
declare v_job public.demo_line_notifications%rowtype;
begin
  update public.demo_line_notifications
  set status = 'processing',
      attempt_count = attempt_count + 1,
      processing_started_at = statement_timestamp(),
      updated_at = statement_timestamp()
  where id = p_id and status = 'pending' and scheduled_for <= statement_timestamp()
  returning * into v_job;
  return v_job;
end;
$$;

create or replace function public.demo_finish_line_notification(
  p_id uuid,
  p_sent boolean,
  p_error text,
  p_retryable boolean
) returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if p_sent then
    update public.demo_line_notifications
    set status = 'sent', sent_at = statement_timestamp(), last_error = null,
        processing_started_at = null, updated_at = statement_timestamp()
    where id = p_id and status = 'processing';
  elsif p_retryable and exists (
    select 1 from public.demo_line_notifications where id = p_id and status = 'processing' and attempt_count < 5
  ) then
    update public.demo_line_notifications
    set status = 'pending',
        scheduled_for = statement_timestamp() + make_interval(secs => least(300, 15 * power(2, greatest(attempt_count - 1, 0)))::integer),
        last_error = left(coalesce(p_error, 'retryable_error'), 500),
        processing_started_at = null,
        updated_at = statement_timestamp()
    where id = p_id and status = 'processing';
  else
    update public.demo_line_notifications
    set status = 'failed', last_error = left(coalesce(p_error, 'permanent_error'), 500),
        processing_started_at = null, updated_at = statement_timestamp()
    where id = p_id and status = 'processing';
  end if;
end;
$$;

create or replace function public.demo_cancel_line_notification(
  p_id uuid
) returns void
language sql
security invoker
set search_path = ''
as $$
  update public.demo_line_notifications
  set status = 'cancelled', processing_started_at = null, updated_at = statement_timestamp()
  where id = p_id and status in ('pending', 'processing');
$$;

create schema if not exists private;
revoke all on schema private from public;

create or replace function private.demo_sync_line_notification_lifecycle()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.status = 'cancelled' and old.status is distinct from new.status then
    update public.demo_line_notifications
    set status = 'cancelled', processing_started_at = null, updated_at = statement_timestamp()
    where booking_id = new.id
      and notification_type = 'appointment_reminder'
      and status in ('pending', 'processing');
  elsif new.status = 'approved'
    and (old.slot_date is distinct from new.slot_date or old.start_time is distinct from new.start_time) then
    update public.demo_line_notifications
    set scheduled_for = ((new.slot_date + new.start_time) at time zone 'Asia/Bangkok') - interval '1 hour',
        updated_at = statement_timestamp()
    where booking_id = new.id
      and notification_type = 'appointment_reminder'
      and status = 'pending';
  end if;
  return new;
end;
$$;

drop trigger if exists demo_sync_line_notification_lifecycle on public.demo_bookings;
create trigger demo_sync_line_notification_lifecycle
after update of status, slot_date, start_time on public.demo_bookings
for each row execute function private.demo_sync_line_notification_lifecycle();

revoke all on function public.demo_link_line_customer(uuid,text,timestamptz) from public, anon, authenticated;
revoke all on function public.demo_create_pending_booking(uuid,uuid,date,time,text,text,text,text) from public, anon, authenticated;
revoke all on function public.demo_claim_booking_and_enqueue(uuid,uuid,text) from public, anon, authenticated;
revoke all on function public.demo_claim_due_line_notifications(integer) from public, anon, authenticated;
revoke all on function public.demo_claim_line_notification(uuid) from public, anon, authenticated;
revoke all on function public.demo_finish_line_notification(uuid,boolean,text,boolean) from public, anon, authenticated;
revoke all on function public.demo_cancel_line_notification(uuid) from public, anon, authenticated;
revoke all on function private.demo_sync_line_notification_lifecycle() from public, anon, authenticated;

grant execute on function public.demo_link_line_customer(uuid,text,timestamptz) to service_role;
grant execute on function public.demo_create_pending_booking(uuid,uuid,date,time,text,text,text,text) to service_role;
grant execute on function public.demo_claim_booking_and_enqueue(uuid,uuid,text) to service_role;
grant execute on function public.demo_claim_due_line_notifications(integer) to service_role;
grant execute on function public.demo_claim_line_notification(uuid) to service_role;
grant execute on function public.demo_finish_line_notification(uuid,boolean,text,boolean) to service_role;
grant execute on function public.demo_cancel_line_notification(uuid) to service_role;

alter publication supabase_realtime add table public.demo_line_notifications;
