-- Medium batch (2026-10-17), apply after 20261017090000_small_fixes.sql. Not applied yet.

-- #8 Owner-editable service menu (replaces the fixed gel / pvc / none list)
create table if not exists public.demo_services (
  key text primary key check (key ~ '^[a-z0-9_-]{1,40}$'),
  label text not null check (char_length(btrim(label)) between 1 and 60),
  price integer check (price is null or price >= 0),
  sort integer not null default 0,
  active boolean not null default true,
  updated_at timestamptz not null default now()
);
insert into public.demo_services(key,label,sort) values ('gel','ล้างเล็บเจล',1),('pvc','ล้างพีวีซี',2),('none','ไม่มี',3)
on conflict (key) do nothing;
alter table public.demo_services enable row level security;
grant select on public.demo_services to anon, authenticated;
grant insert, update on public.demo_services to authenticated;
create policy demo_services_read on public.demo_services for select to anon, authenticated
  using (active or (select auth.jwt() -> 'app_metadata' ->> 'role') = 'owner');
create policy demo_services_owner_insert on public.demo_services for insert to authenticated
  with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'owner');
create policy demo_services_owner_update on public.demo_services for update to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'owner')
  with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'owner');
-- services are never deleted (old bookings point at them); the owner hides them with active=false
alter table public.demo_bookings drop constraint if exists demo_bookings_removal_service_check;
alter table public.demo_bookings add constraint demo_bookings_service_fk foreign key (removal_service) references public.demo_services(key);

-- #3 Same LINE account on a new phone keeps its bookings ("คิวของฉัน" no longer disappears)
create or replace function public.demo_link_line_customer(p_customer_id uuid, p_line_user_id text, p_verified_at timestamptz)
returns void language plpgsql security invoker set search_path = '' as $$
declare v_old uuid;
begin
  if p_customer_id is null or p_line_user_id !~ '^U[0-9A-Za-z_-]{8,128}$' then raise exception 'INVALID_LINE_LINK'; end if;
  select customer_id into v_old from public.demo_line_links where line_user_id = p_line_user_id;
  delete from public.demo_line_links where customer_id = p_customer_id and line_user_id <> p_line_user_id;
  insert into public.demo_line_links(customer_id, line_user_id, friend_verified_at, updated_at)
  values (p_customer_id, p_line_user_id, p_verified_at, statement_timestamp())
  on conflict (line_user_id) do update
  set customer_id = excluded.customer_id, friend_verified_at = excluded.friend_verified_at, updated_at = statement_timestamp();
  if v_old is not null and v_old <> p_customer_id then
    update public.demo_bookings set customer_id = p_customer_id where customer_id = v_old;
    update public.demo_reschedule_requests set customer_id = p_customer_id where customer_id = v_old;
    update public.demo_booking_reschedule_history set customer_id = p_customer_id where customer_id = v_old;
    -- ponytail: slip/design images stay under the old user's storage folder; the owner still sees them, the customer does not need to
  end if;
end $$;

-- #6 Waitlist: a customer waits on a full slot; when its paid booking is cancelled, everyone waiting gets a LINE message
alter table public.demo_line_notifications drop constraint if exists demo_line_notifications_booking_id_notification_type_key;
alter table public.demo_line_notifications add constraint demo_line_notifications_booking_type_recipient_key
  unique (booking_id, notification_type, recipient_line_user_id);
alter table public.demo_line_notifications drop constraint demo_line_notifications_notification_type_check;
alter table public.demo_line_notifications add constraint demo_line_notifications_notification_type_check
  check(notification_type in (
    'booking_confirmed','appointment_reminder','owner_booking_confirmed','owner_booking_cancelled',
    'appointment_reminder_day','booking_cancelled_by_shop','owner_booking_rescheduled','review_request','rebook_nudge',
    'waitlist_open'));

-- existing enqueue functions: untargeted ON CONFLICT so they work with the wider unique key
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
  on conflict do nothing;
  return jsonb_build_object('won',true,'status','approved');
end;
$$;

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
      on conflict do nothing;
  end if;
  return result;
end $$;

create table if not exists public.demo_waitlist (
  slot_date date not null,
  start_time time not null,
  customer_id uuid not null references auth.users(id) on delete cascade,
  line_user_id text not null,
  created_at timestamptz not null default now(),
  primary key (slot_date, start_time, customer_id),
  foreign key (slot_date, start_time) references public.demo_slots(slot_date, start_time) on delete cascade
);
alter table public.demo_waitlist enable row level security;
grant select, delete on public.demo_waitlist to authenticated;
create policy demo_waitlist_read_self_or_owner on public.demo_waitlist for select to authenticated
  using (customer_id = (select auth.uid()) or (select auth.jwt() -> 'app_metadata' ->> 'role') = 'owner');
create policy demo_waitlist_delete_self on public.demo_waitlist for delete to authenticated
  using (customer_id = (select auth.uid()));

create or replace function public.demo_join_waitlist(p_slot_date date, p_start_time time)
returns void language plpgsql security definer set search_path = '' as $$
declare v_line text;
begin
  select line_user_id into v_line from public.demo_line_links where customer_id = (select auth.uid());
  if v_line is null then raise exception 'LINE_FRIEND_REQUIRED'; end if;
  if ((p_slot_date + p_start_time) at time zone 'Asia/Bangkok') <= now() then raise exception 'SLOT_PASSED'; end if;
  insert into public.demo_waitlist(slot_date, start_time, customer_id, line_user_id)
  values (p_slot_date, p_start_time, (select auth.uid()), v_line)
  on conflict do nothing;
end $$;
revoke all on function public.demo_join_waitlist(date,time) from public, anon;
grant execute on function public.demo_join_waitlist(date,time) to authenticated;

create or replace function private.demo_notify_waitlist()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin
  if old.status = 'approved' and new.status = 'cancelled'
     and ((old.slot_date + old.start_time) at time zone 'Asia/Bangkok') > statement_timestamp() then
    insert into public.demo_line_notifications(booking_id, recipient_line_user_id, notification_type, scheduled_for)
    select old.id, w.line_user_id, 'waitlist_open', statement_timestamp()
    from public.demo_waitlist w where w.slot_date = old.slot_date and w.start_time = old.start_time
    on conflict do nothing;
    delete from public.demo_waitlist where slot_date = old.slot_date and start_time = old.start_time;
  end if;
  return new;
end $$;
drop trigger if exists demo_notify_waitlist on public.demo_bookings;
create trigger demo_notify_waitlist after update of status on public.demo_bookings
for each row execute function private.demo_notify_waitlist();

-- #7 Owner notes per customer phone
create table if not exists public.demo_customer_notes (
  phone text primary key check (phone ~ '^[0-9]{9,10}$'),
  note text not null default '' check (char_length(note) <= 1000),
  updated_at timestamptz not null default now()
);
alter table public.demo_customer_notes enable row level security;
grant select, insert, update on public.demo_customer_notes to authenticated;
create policy demo_customer_notes_owner on public.demo_customer_notes for all to authenticated
  using ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'owner')
  with check ((select auth.jwt() -> 'app_metadata' ->> 'role') = 'owner');
