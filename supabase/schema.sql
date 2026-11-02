create extension if not exists pgcrypto with schema extensions;

create table public.demo_slots (
  id uuid primary key default gen_random_uuid(),
  slot_date date not null,
  start_time time not null,
  end_time time not null,
  is_open boolean not null default false,
  is_booked boolean not null default false,
  hold_expires_at timestamptz,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  constraint demo_slots_date_start_unique unique (slot_date, start_time),
  constraint demo_slots_approved_periods check (
    (start_time = time '10:00' and end_time = time '12:30') or
    (start_time = time '13:30' and end_time = time '16:00') or
    (extract(isodow from slot_date) = 2 and start_time = time '15:00' and end_time = time '17:30') or
    (start_time = time '17:00' and end_time = time '19:30') or
    (extract(isodow from slot_date) = 2 and start_time = time '19:00' and end_time = time '21:00') or
    (start_time = time '20:00' and end_time = time '22:30')
  )
);

create table public.demo_bookings (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references auth.users(id) on delete cascade,
  slot_date date not null,
  start_time time not null,
  customer_name text not null check (char_length(btrim(customer_name)) between 1 and 100),
  customer_phone text not null check (char_length(regexp_replace(customer_phone, '[^0-9]', '', 'g')) between 9 and 10),
  removal_service text not null check (removal_service in ('gel','pvc','none')),
  special_request text check (special_request is null or char_length(special_request) <= 500),
  status text not null default 'pending' check (status in ('pending','approved','lost','expired','cancelled')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '5 minutes'),
  paid_at timestamptz,
  slip_path text,
  slip_uploaded_at timestamptz,
  cancelled_at timestamptz,
  cancelled_by uuid references auth.users(id) on delete set null,
  cancelled_by_role text check (cancelled_by_role is null or cancelled_by_role in ('customer','owner')),
  refund_status text check (refund_status is null or refund_status in ('refund_due','no_refund')),
  constraint demo_bookings_slot_fk foreign key (slot_date, start_time)
    references public.demo_slots(slot_date, start_time)
    on update cascade on delete restrict,
  constraint demo_bookings_approved_start_times check (
    start_time in (time '10:00', time '13:30', time '17:00', time '20:00') or
    (extract(isodow from slot_date) = 2 and start_time in (time '15:00', time '19:00'))
  ),
  constraint demo_bookings_expiry_after_creation check (expires_at > created_at)
);

create or replace function public.demo_force_five_minute_booking_expiry()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.status = 'pending' then
    new.expires_at := statement_timestamp() + interval '5 minutes';
  end if;
  return new;
end;
$$;

create trigger demo_force_five_minute_booking_expiry
before insert on public.demo_bookings
for each row
execute function public.demo_force_five_minute_booking_expiry();

create unique index demo_one_active_booking_per_slot
  on public.demo_bookings (slot_date, start_time)
  where status in ('pending', 'approved');

create index demo_bookings_customer_date_idx on public.demo_bookings(customer_id, slot_date);
create index demo_bookings_merchant_calendar_idx on public.demo_bookings(slot_date, start_time, status);

create or replace function public.demo_sync_slot_booking_state()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if tg_op = 'UPDATE' and old.status = 'approved'
    and (new.status <> 'approved' or old.slot_date <> new.slot_date or old.start_time <> new.start_time) then
    update public.demo_slots s
    set is_booked = exists (
      select 1 from public.demo_bookings b
      where b.slot_date = old.slot_date and b.start_time = old.start_time and b.status = 'approved'
    ), updated_at = now()
    where s.slot_date = old.slot_date and s.start_time = old.start_time;
  end if;

  if new.status = 'approved' then
    update public.demo_slots
    set is_open = false, is_booked = true, updated_at = now()
    where slot_date = new.slot_date and start_time = new.start_time;
  end if;
  return new;
end;
$$;

drop trigger if exists demo_sync_slot_booking_state on public.demo_bookings;
create trigger demo_sync_slot_booking_state
after insert or update of status, slot_date, start_time on public.demo_bookings
for each row execute function public.demo_sync_slot_booking_state();

create table public.demo_reschedule_requests (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.demo_bookings(id) on delete cascade,
  customer_id uuid not null references auth.users(id) on delete cascade,
  old_slot_date date not null,
  old_start_time time not null,
  old_end_time time not null,
  new_slot_date date not null,
  new_start_time time not null,
  new_end_time time not null,
  fee_amount integer not null default 20 check (fee_amount = 20),
  status text not null default 'awaiting_slip' check (status in ('awaiting_slip','pending_review','approved','rejected','expired','cancelled')),
  expires_at timestamptz not null default (now() + interval '10 minutes'),
  slip_path text,
  slip_uploaded_at timestamptz,
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index demo_reschedule_active_new_slot_unique
  on public.demo_reschedule_requests(new_slot_date,new_start_time)
  where status in ('awaiting_slip','pending_review');
create unique index demo_reschedule_one_active_per_booking
  on public.demo_reschedule_requests(booking_id)
  where status in ('awaiting_slip','pending_review');
create index demo_reschedule_customer_idx on public.demo_reschedule_requests(customer_id,created_at desc);
create index demo_reschedule_merchant_idx on public.demo_reschedule_requests(new_slot_date,new_start_time,status);

create table public.demo_booking_reschedule_history (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references public.demo_reschedule_requests(id) on delete restrict,
  booking_id uuid not null references public.demo_bookings(id) on delete cascade,
  customer_id uuid not null references auth.users(id) on delete cascade,
  old_slot_date date not null,
  old_start_time time not null,
  old_end_time time not null,
  new_slot_date date not null,
  new_start_time time not null,
  new_end_time time not null,
  fee_amount integer not null check (fee_amount = 20),
  fee_slip_path text not null,
  approved_at timestamptz not null default now(),
  approved_by uuid references auth.users(id) on delete set null
);

alter table public.demo_slots enable row level security;
alter table public.demo_bookings enable row level security;
alter table public.demo_reschedule_requests enable row level security;
alter table public.demo_booking_reschedule_history enable row level security;

revoke all on table public.demo_slots from anon, authenticated;
revoke all on table public.demo_bookings from anon, authenticated;
revoke all on table public.demo_reschedule_requests from anon, authenticated;
revoke all on table public.demo_booking_reschedule_history from anon, authenticated;

grant select on table public.demo_slots to authenticated;
grant insert, update on table public.demo_slots to authenticated;
grant select on table public.demo_bookings to authenticated;
grant select on table public.demo_reschedule_requests to authenticated;
grant select on table public.demo_booking_reschedule_history to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('demo-payment-slips','demo-payment-slips',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=false, file_size_limit=5242880,
allowed_mime_types=array['image/jpeg','image/png','image/webp'];

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('demo-reschedule-slips','demo-reschedule-slips',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=false, file_size_limit=5242880,
allowed_mime_types=array['image/jpeg','image/png','image/webp'];

create policy demo_slots_read_authenticated
  on public.demo_slots for select
  to authenticated
  using (true);

create policy demo_slots_insert_owner
  on public.demo_slots for insert
  to authenticated
  with check (
    (select auth.jwt()->'app_metadata'->>'role') = 'owner'
    and updated_by = (select auth.uid())
  );

create policy demo_slots_update_owner
  on public.demo_slots for update
  to authenticated
  using ((select auth.jwt()->'app_metadata'->>'role') = 'owner')
  with check (
    (select auth.jwt()->'app_metadata'->>'role') = 'owner'
    and updated_by = (select auth.uid())
    and (
      is_open
      or not exists (
        select 1 from public.demo_bookings b
        where b.slot_date = demo_slots.slot_date
          and b.start_time = demo_slots.start_time
          and b.status = 'approved'
      )
    )
  );

create policy demo_bookings_read_owner_or_self
  on public.demo_bookings for select
  to authenticated
  using (
    customer_id = (select auth.uid())
    or (select auth.jwt()->'app_metadata'->>'role') = 'owner'
  );

create policy demo_reschedule_read_owner_or_self
  on public.demo_reschedule_requests for select
  to authenticated
  using (
    customer_id = (select auth.uid())
    or (select auth.jwt()->'app_metadata'->>'role') = 'owner'
  );

create policy demo_reschedule_history_read_owner_or_self
  on public.demo_booking_reschedule_history for select
  to authenticated
  using (
    customer_id = (select auth.uid())
    or (select auth.jwt()->'app_metadata'->>'role') = 'owner'
  );

create policy demo_slips_insert_own_prefix
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'demo-payment-slips'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy demo_slips_read_self_or_owner
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'demo-payment-slips'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or (select auth.jwt()->'app_metadata'->>'role') = 'owner'
    )
  );

create policy demo_reschedule_slips_insert_own_prefix
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'demo-reschedule-slips'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy demo_reschedule_slips_read_self_or_owner
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'demo-reschedule-slips'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or (select auth.jwt()->'app_metadata'->>'role') = 'owner'
    )
  );

create schema if not exists private;

create or replace function public.create_demo_reschedule(
  p_booking_id uuid,
  p_customer_id uuid,
  p_new_slot_date date,
  p_new_start_time time
) returns jsonb
language plpgsql
security invoker
as $$
declare
  v_booking public.demo_bookings%rowtype;
  v_old_slot public.demo_slots%rowtype;
  v_new_slot public.demo_slots%rowtype;
  v_request public.demo_reschedule_requests%rowtype;
  v_appointment timestamptz;
begin
  perform public.expire_demo_reschedules();
  select * into v_booking from public.demo_bookings
    where id=p_booking_id and customer_id=p_customer_id for update;
  if not found or v_booking.status <> 'approved' then
    raise exception 'BOOKING_NOT_ELIGIBLE';
  end if;
  v_appointment := (v_booking.slot_date::text || ' ' || v_booking.start_time::text)::timestamp at time zone 'Asia/Bangkok';
  if (now() at time zone 'Asia/Bangkok')::date >= v_booking.slot_date then
    raise exception 'RESCHEDULE_DEADLINE_PASSED';
  end if;
  select * into v_old_slot from public.demo_slots
    where slot_date=v_booking.slot_date and start_time=v_booking.start_time for update;
  select * into v_new_slot from public.demo_slots
    where slot_date=p_new_slot_date and start_time=p_new_start_time for update;
  if not found or not v_new_slot.is_open then
    raise exception 'NEW_SLOT_UNAVAILABLE';
  end if;
  if exists(select 1 from public.demo_bookings where slot_date=p_new_slot_date and start_time=p_new_start_time and status='approved') then
    raise exception 'NEW_SLOT_UNAVAILABLE';
  end if;
  insert into public.demo_reschedule_requests(
    booking_id,customer_id,old_slot_date,old_start_time,old_end_time,
    new_slot_date,new_start_time,new_end_time
  ) values (
    v_booking.id,p_customer_id,v_booking.slot_date,v_booking.start_time,v_old_slot.end_time,
    p_new_slot_date,p_new_start_time,v_new_slot.end_time
  ) returning * into v_request;
  update public.demo_slots set is_open=false,updated_at=now()
    where id=v_new_slot.id;
  return to_jsonb(v_request);
end;
$$;

create or replace function public.review_demo_reschedule(
  p_request_id uuid,
  p_decision text,
  p_owner_id uuid
) returns jsonb
language plpgsql
security invoker
as $$
declare
  v_request public.demo_reschedule_requests%rowtype;
  v_booking public.demo_bookings%rowtype;
begin
  if p_decision not in ('approve','reject') then raise exception 'INVALID_DECISION'; end if;
  select * into v_request from public.demo_reschedule_requests where id=p_request_id for update;
  if not found or v_request.status <> 'pending_review' then raise exception 'REQUEST_NOT_REVIEWABLE'; end if;
  if p_decision='reject' then
    update public.demo_reschedule_requests set status='rejected',reviewed_at=now(),reviewed_by=p_owner_id,updated_at=now() where id=p_request_id returning * into v_request;
    update public.demo_slots s set is_open=true,updated_at=now(),updated_by=p_owner_id
      where s.slot_date=v_request.new_slot_date and s.start_time=v_request.new_start_time
      and not exists(select 1 from public.demo_bookings b where b.slot_date=s.slot_date and b.start_time=s.start_time and b.status='approved');
    return jsonb_build_object('request',to_jsonb(v_request));
  end if;
  select * into v_booking from public.demo_bookings where id=v_request.booking_id for update;
  if not found or v_booking.status <> 'approved' or v_booking.slot_date <> v_request.old_slot_date or v_booking.start_time <> v_request.old_start_time then
    raise exception 'BOOKING_CHANGED';
  end if;
  if v_request.slip_path is null then raise exception 'RESCHEDULE_SLIP_REQUIRED'; end if;
  update public.demo_bookings set slot_date=v_request.new_slot_date,start_time=v_request.new_start_time where id=v_booking.id returning * into v_booking;
  update public.demo_slots set is_open=true,updated_at=now(),updated_by=p_owner_id where slot_date=v_request.old_slot_date and start_time=v_request.old_start_time;
  update public.demo_slots set is_open=false,updated_at=now(),updated_by=p_owner_id where slot_date=v_request.new_slot_date and start_time=v_request.new_start_time;
  update public.demo_reschedule_requests set status='approved',reviewed_at=now(),reviewed_by=p_owner_id,updated_at=now() where id=p_request_id returning * into v_request;
  insert into public.demo_booking_reschedule_history(request_id,booking_id,customer_id,old_slot_date,old_start_time,old_end_time,new_slot_date,new_start_time,new_end_time,fee_amount,fee_slip_path,approved_by)
  values(v_request.id,v_request.booking_id,v_request.customer_id,v_request.old_slot_date,v_request.old_start_time,v_request.old_end_time,v_request.new_slot_date,v_request.new_start_time,v_request.new_end_time,v_request.fee_amount,v_request.slip_path,p_owner_id);
  return jsonb_build_object('request',to_jsonb(v_request),'booking',to_jsonb(v_booking));
end;
$$;

create or replace function public.expire_demo_reschedules() returns integer
language plpgsql
security invoker
as $$
declare v_request public.demo_reschedule_requests%rowtype; v_count integer:=0;
begin
  for v_request in select * from public.demo_reschedule_requests where status='awaiting_slip' and expires_at<=now() for update skip locked loop
    update public.demo_reschedule_requests set status='expired',updated_at=now() where id=v_request.id;
    update public.demo_slots s set is_open=true,updated_at=now()
      where s.slot_date=v_request.new_slot_date and s.start_time=v_request.new_start_time
      and not exists(select 1 from public.demo_bookings b where b.slot_date=s.slot_date and b.start_time=s.start_time and b.status='approved')
      and not exists(select 1 from public.demo_reschedule_requests r where r.new_slot_date=s.slot_date and r.new_start_time=s.start_time and r.status in ('awaiting_slip','pending_review'));
    v_count:=v_count+1;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.create_demo_reschedule(uuid,uuid,date,time) from public, anon, authenticated;
revoke all on function public.review_demo_reschedule(uuid,text,uuid) from public, anon, authenticated;
revoke all on function public.expire_demo_reschedules() from public, anon, authenticated;
grant execute on function public.create_demo_reschedule(uuid,uuid,date,time) to service_role;
grant execute on function public.review_demo_reschedule(uuid,text,uuid) to service_role;
grant execute on function public.expire_demo_reschedules() to service_role;

create extension if not exists pg_cron with schema pg_catalog;
do $$
declare v_job_id bigint;
begin
  select jobid into v_job_id from cron.job where jobname='expire-demo-reschedules' limit 1;
  if v_job_id is not null then perform cron.unschedule(v_job_id); end if;
end $$;
select cron.schedule('expire-demo-reschedules','* * * * *',$$select public.expire_demo_reschedules();$$);

alter publication supabase_realtime add table public.demo_slots;
alter publication supabase_realtime add table public.demo_bookings;
alter publication supabase_realtime add table public.demo_reschedule_requests;

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
  notification_type text not null check (notification_type in ('booking_confirmed','appointment_reminder')),
  scheduled_for timestamptz not null,
  status text not null default 'pending' check (status in ('pending','processing','sent','failed','cancelled')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  processing_started_at timestamptz,
  last_error text,
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (booking_id, notification_type)
);

create index demo_line_notifications_due_idx on public.demo_line_notifications(scheduled_for,status)
where status in ('pending','processing');

alter table public.demo_line_links enable row level security;
alter table public.demo_booking_line_recipients enable row level security;
alter table public.demo_line_notifications enable row level security;
revoke all on table public.demo_line_links from anon, authenticated;
revoke all on table public.demo_booking_line_recipients from anon, authenticated;
revoke all on table public.demo_line_notifications from anon, authenticated;
grant select on table public.demo_line_notifications to authenticated;

create policy demo_line_notifications_owner_read on public.demo_line_notifications for select to authenticated
using ((select auth.jwt()->'app_metadata'->>'role')='owner');

create or replace function public.demo_link_line_customer(p_customer_id uuid,p_line_user_id text,p_verified_at timestamptz)
returns void language plpgsql security invoker set search_path = '' as $$
begin
  if p_customer_id is null or p_line_user_id !~ '^U[0-9A-Za-z_-]{8,128}$' then raise exception 'INVALID_LINE_LINK'; end if;
  delete from public.demo_line_links where customer_id=p_customer_id and line_user_id<>p_line_user_id;
  insert into public.demo_line_links(customer_id,line_user_id,friend_verified_at,updated_at)
  values(p_customer_id,p_line_user_id,p_verified_at,statement_timestamp())
  on conflict(line_user_id) do update set customer_id=excluded.customer_id,friend_verified_at=excluded.friend_verified_at,updated_at=statement_timestamp();
end;
$$;

create or replace function public.demo_create_pending_booking(
  p_customer_id uuid,p_booking_id uuid,p_slot_date date,p_start_time time,p_customer_name text,
  p_customer_phone text,p_removal_service text,p_design_image_path text
) returns public.demo_bookings language plpgsql security invoker set search_path = '' as $$
declare v_booking public.demo_bookings%rowtype; v_line_user_id text; v_slot public.demo_slots%rowtype;
begin
  select line_user_id into v_line_user_id from public.demo_line_links where customer_id=p_customer_id;
  if v_line_user_id is null then raise exception 'LINE_FRIEND_REQUIRED'; end if;
  update public.demo_bookings set status='expired'
    where slot_date=p_slot_date and start_time=p_start_time and status='pending' and expires_at<=statement_timestamp();
  select * into v_slot from public.demo_slots where slot_date=p_slot_date and start_time=p_start_time for update;
  if not found or not v_slot.is_open then raise exception 'SLOT_CLOSED'; end if;
  insert into public.demo_bookings(id,customer_id,slot_date,start_time,customer_name,customer_phone,removal_service,design_image_path,status)
  values(p_booking_id,p_customer_id,p_slot_date,p_start_time,btrim(p_customer_name),btrim(p_customer_phone),p_removal_service,nullif(btrim(p_design_image_path),''),'pending')
  returning * into v_booking;
  insert into public.demo_booking_line_recipients(booking_id,line_user_id) values(v_booking.id,v_line_user_id);
  return v_booking;
end;
$$;

create or replace function public.demo_claim_booking_and_enqueue(p_booking_id uuid,p_customer_id uuid,p_slip_path text)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare v_booking public.demo_bookings%rowtype; v_line_user_id text; v_slot public.demo_slots%rowtype;
begin
  select * into v_booking from public.demo_bookings where id=p_booking_id and customer_id=p_customer_id for update;
  if not found then return jsonb_build_object('won',false,'status','lost'); end if;
  if v_booking.status='approved' then return jsonb_build_object('won',true,'status','approved'); end if;
  if v_booking.status<>'pending' then return jsonb_build_object('won',false,'status','lost'); end if;
  if v_booking.expires_at<=statement_timestamp() then
    update public.demo_bookings set status='expired' where id=v_booking.id;
    return jsonb_build_object('won',false,'status','expired');
  end if;
  select * into v_slot from public.demo_slots where slot_date=v_booking.slot_date and start_time=v_booking.start_time for update;
  if not found or not v_slot.is_open then
    update public.demo_bookings set status='lost' where id=v_booking.id;
    return jsonb_build_object('won',false,'status','lost');
  end if;
  select line_user_id into v_line_user_id from public.demo_booking_line_recipients where booking_id=v_booking.id;
  if v_line_user_id is null then raise exception 'LINE_RECIPIENT_MISSING'; end if;
  update public.demo_bookings set status='approved',paid_at=statement_timestamp(),slip_path=p_slip_path,slip_uploaded_at=statement_timestamp() where id=v_booking.id;
  update public.demo_slots set is_open=false,is_booked=true,updated_at=statement_timestamp() where id=v_slot.id;
  insert into public.demo_line_notifications(booking_id,recipient_line_user_id,notification_type,scheduled_for) values
    (v_booking.id,v_line_user_id,'booking_confirmed',statement_timestamp()),
    (v_booking.id,v_line_user_id,'appointment_reminder',((v_booking.slot_date+v_booking.start_time) at time zone 'Asia/Bangkok')-interval '1 hour')
  on conflict(booking_id,notification_type) do nothing;
  return jsonb_build_object('won',true,'status','approved');
end;
$$;

create or replace function public.demo_claim_due_line_notifications(p_limit integer default 25)
returns setof public.demo_line_notifications language sql security invoker set search_path = '' as $$
  with candidates as (
    select id from public.demo_line_notifications
    where scheduled_for<=statement_timestamp() and (status='pending' or (status='processing' and processing_started_at<=statement_timestamp()-interval '5 minutes'))
    order by scheduled_for,created_at for update skip locked limit greatest(1,least(coalesce(p_limit,25),100))
  ), claimed as (
    update public.demo_line_notifications notification
    set status='processing',attempt_count=notification.attempt_count+1,processing_started_at=statement_timestamp(),updated_at=statement_timestamp()
    from candidates where notification.id=candidates.id returning notification.*
  ) select * from claimed;
$$;

create or replace function public.demo_claim_line_notification(p_id uuid)
returns public.demo_line_notifications language plpgsql security invoker set search_path = '' as $$
declare v_job public.demo_line_notifications%rowtype;
begin
  update public.demo_line_notifications set status='processing',attempt_count=attempt_count+1,processing_started_at=statement_timestamp(),updated_at=statement_timestamp()
  where id=p_id and status='pending' and scheduled_for<=statement_timestamp() returning * into v_job;
  return v_job;
end;
$$;

create or replace function public.demo_finish_line_notification(p_id uuid,p_sent boolean,p_error text,p_retryable boolean)
returns void language plpgsql security invoker set search_path = '' as $$
begin
  if p_sent then
    update public.demo_line_notifications set status='sent',sent_at=statement_timestamp(),last_error=null,processing_started_at=null,updated_at=statement_timestamp()
    where id=p_id and status='processing';
  elsif p_retryable and exists(select 1 from public.demo_line_notifications where id=p_id and status='processing' and attempt_count<5) then
    update public.demo_line_notifications
    set status='pending',scheduled_for=statement_timestamp()+make_interval(secs=>least(300,15*power(2,greatest(attempt_count-1,0)))::integer),
      last_error=left(coalesce(p_error,'retryable_error'),500),processing_started_at=null,updated_at=statement_timestamp()
    where id=p_id and status='processing';
  else
    update public.demo_line_notifications set status='failed',last_error=left(coalesce(p_error,'permanent_error'),500),processing_started_at=null,updated_at=statement_timestamp()
    where id=p_id and status='processing';
  end if;
end;
$$;

create or replace function public.demo_cancel_line_notification(p_id uuid)
returns void language sql security invoker set search_path = '' as $$
  update public.demo_line_notifications set status='cancelled',processing_started_at=null,updated_at=statement_timestamp()
  where id=p_id and status in ('pending','processing');
$$;

create or replace function private.demo_sync_line_notification_lifecycle()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if new.status='cancelled' and old.status is distinct from new.status then
    update public.demo_line_notifications set status='cancelled',processing_started_at=null,updated_at=statement_timestamp()
    where booking_id=new.id and notification_type='appointment_reminder' and status in ('pending','processing');
  elsif new.status='approved' and (old.slot_date is distinct from new.slot_date or old.start_time is distinct from new.start_time) then
    update public.demo_line_notifications
    set scheduled_for=((new.slot_date+new.start_time) at time zone 'Asia/Bangkok')-interval '1 hour',updated_at=statement_timestamp()
    where booking_id=new.id and notification_type='appointment_reminder' and status='pending';
  end if;
  return new;
end;
$$;

create trigger demo_sync_line_notification_lifecycle after update of status,slot_date,start_time on public.demo_bookings
for each row execute function private.demo_sync_line_notification_lifecycle();

revoke all on function public.demo_link_line_customer(uuid,text,timestamptz) from public,anon,authenticated;
revoke all on function public.demo_create_pending_booking(uuid,uuid,date,time,text,text,text,text) from public,anon,authenticated;
revoke all on function public.demo_claim_booking_and_enqueue(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.demo_claim_due_line_notifications(integer) from public,anon,authenticated;
revoke all on function public.demo_claim_line_notification(uuid) from public,anon,authenticated;
revoke all on function public.demo_finish_line_notification(uuid,boolean,text,boolean) from public,anon,authenticated;
revoke all on function public.demo_cancel_line_notification(uuid) from public,anon,authenticated;
revoke all on function private.demo_sync_line_notification_lifecycle() from public,anon,authenticated;
grant execute on function public.demo_link_line_customer(uuid,text,timestamptz) to service_role;
grant execute on function public.demo_create_pending_booking(uuid,uuid,date,time,text,text,text,text) to service_role;
grant execute on function public.demo_claim_booking_and_enqueue(uuid,uuid,text) to service_role;
grant execute on function public.demo_claim_due_line_notifications(integer) to service_role;
grant execute on function public.demo_claim_line_notification(uuid) to service_role;
grant execute on function public.demo_finish_line_notification(uuid,boolean,text,boolean) to service_role;
grant execute on function public.demo_cancel_line_notification(uuid) to service_role;
alter publication supabase_realtime add table public.demo_line_notifications;

-- Owner booking notification; recipient is supplied only by the server.
alter table public.demo_line_notifications drop constraint demo_line_notifications_notification_type_check;
alter table public.demo_line_notifications add constraint demo_line_notifications_notification_type_check
  check(notification_type in ('booking_confirmed','appointment_reminder','owner_booking_confirmed'));
create or replace function public.demo_claim_booking_with_owner_notification(
  p_booking_id uuid, p_customer_id uuid, p_slip_path text, p_owner_line_user_id text
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  prior_status text;
  result jsonb;
begin
  select status into prior_status from public.demo_bookings
    where id=p_booking_id and customer_id=p_customer_id for update;
  result := public.demo_claim_booking_and_enqueue(p_booking_id,p_customer_id,p_slip_path);
  if prior_status='pending' and result->>'won'='true'
     and p_owner_line_user_id ~ '^U[0-9a-f]{32}$' then
    insert into public.demo_line_notifications(booking_id,recipient_line_user_id,notification_type,scheduled_for)
      values(p_booking_id,p_owner_line_user_id,'owner_booking_confirmed',statement_timestamp())
      on conflict(booking_id,notification_type) do nothing;
  end if;
  return result;
end $$;
revoke all on function public.demo_claim_booking_with_owner_notification(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.demo_claim_booking_with_owner_notification(uuid,uuid,text,text) to service_role;

alter table public.demo_line_notifications drop constraint demo_line_notifications_notification_type_check;
alter table public.demo_line_notifications add constraint demo_line_notifications_notification_type_check
  check(notification_type in ('booking_confirmed','appointment_reminder','owner_booking_confirmed','owner_booking_cancelled'));

-- Internal only: the Edge Function verifies the caller and supplies the owner recipient.
create or replace function public.demo_cancel_booking_and_notify(
  p_booking_id uuid,p_actor_id uuid,p_actor_role text,p_refund_status text,p_owner_line_user_id text
) returns uuid language plpgsql security invoker set search_path='' as $$
declare changed uuid;
begin
  if p_actor_role not in ('customer','owner') or p_refund_status not in ('refund_due','no_refund') then
    raise exception 'INVALID_CANCELLATION';
  end if;
  update public.demo_bookings set status='cancelled',cancelled_at=statement_timestamp(),
    cancelled_by=p_actor_id,cancelled_by_role=p_actor_role,refund_status=p_refund_status
    where id=p_booking_id and status in ('pending','approved')
      and (p_actor_role='owner' or customer_id=p_actor_id)
    returning id into changed;
  if changed is not null and p_owner_line_user_id ~ '^U[0-9a-f]{32}$' then
    insert into public.demo_line_notifications(booking_id,recipient_line_user_id,notification_type,scheduled_for)
      values(changed,p_owner_line_user_id,'owner_booking_cancelled',statement_timestamp())
      on conflict(booking_id,notification_type) do nothing;
  end if;
  return changed;
end $$;
revoke all on function public.demo_cancel_booking_and_notify(uuid,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.demo_cancel_booking_and_notify(uuid,uuid,text,text,text) to service_role;
