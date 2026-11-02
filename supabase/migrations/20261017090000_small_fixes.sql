-- Small fixes batch (2026-10-17). Not applied yet: run on the live project together with the web deploy.

-- 1. New LINE notification types
alter table public.demo_line_notifications drop constraint demo_line_notifications_notification_type_check;
alter table public.demo_line_notifications add constraint demo_line_notifications_notification_type_check
  check(notification_type in (
    'booking_confirmed','appointment_reminder','owner_booking_confirmed','owner_booking_cancelled',
    'appointment_reminder_day','booking_cancelled_by_shop','owner_booking_rescheduled','review_request','rebook_nudge'));

-- 2. Arrived / no-show, set by the owner only
alter table public.demo_bookings add column if not exists attendance text check (attendance in ('arrived','no_show'));
alter table public.demo_bookings add column if not exists attendance_at timestamptz;

create or replace function public.demo_set_attendance(p_booking_id uuid, p_attendance text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if coalesce((select auth.jwt() -> 'app_metadata' ->> 'role'), '') <> 'owner' then raise exception 'OWNER_REQUIRED'; end if;
  if p_attendance not in ('arrived','no_show') then raise exception 'INVALID_ATTENDANCE'; end if;
  update public.demo_bookings set attendance=p_attendance, attendance_at=statement_timestamp()
    where id=p_booking_id and status='approved' and slot_date <= (now() at time zone 'Asia/Bangkok')::date;
  if not found then raise exception 'BOOKING_NOT_MARKABLE'; end if;
  -- no-show customers get no review request or rebook nudge
  update public.demo_line_notifications set status=case when p_attendance='no_show' then 'cancelled' else 'pending' end, updated_at=statement_timestamp()
    where booking_id=p_booking_id and notification_type in ('review_request','rebook_nudge')
      and status in (case when p_attendance='no_show' then 'pending' else 'cancelled' end);
end $$;
revoke all on function public.demo_set_attendance(uuid,text) from public,anon;
grant execute on function public.demo_set_attendance(uuid,text) to authenticated;

-- 3. Customer follow-ups queued when a booking is paid: day-before reminder, review request, rebook nudge
create or replace function private.demo_enqueue_customer_followups()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare v_line text; v_start timestamptz;
begin
  if new.status='approved' and old.status is distinct from 'approved' then
    select line_user_id into v_line from public.demo_booking_line_recipients where booking_id=new.id;
    if v_line is null then return new; end if;
    v_start := (new.slot_date+new.start_time) at time zone 'Asia/Bangkok';
    insert into public.demo_line_notifications(booking_id,recipient_line_user_id,notification_type,scheduled_for)
    select new.id, v_line, t, at from (values
      ('appointment_reminder_day', v_start-interval '1 day'),
      ('review_request', v_start+interval '3 hours'),
      ('rebook_nudge', v_start+interval '21 days')) as f(t,at)
    where t<>'appointment_reminder_day' or v_start-interval '1 day' > statement_timestamp()
    on conflict do nothing;
  end if;
  return new;
end $$;
drop trigger if exists demo_enqueue_customer_followups on public.demo_bookings;
create trigger demo_enqueue_customer_followups after update of status on public.demo_bookings
for each row execute function private.demo_enqueue_customer_followups();

-- 4. Keep every customer notification in step with cancel / reschedule (replaces the reminder-only version)
create or replace function private.demo_sync_line_notification_lifecycle()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare v_start timestamptz := (new.slot_date+new.start_time) at time zone 'Asia/Bangkok';
begin
  if new.status='cancelled' and old.status is distinct from new.status then
    update public.demo_line_notifications set status='cancelled',processing_started_at=null,updated_at=statement_timestamp()
    where booking_id=new.id and status in ('pending','processing')
      and notification_type in ('appointment_reminder','appointment_reminder_day','review_request','rebook_nudge');
  elsif new.status='approved' and (old.slot_date is distinct from new.slot_date or old.start_time is distinct from new.start_time) then
    update public.demo_line_notifications
    set scheduled_for = v_start + case notification_type
          when 'appointment_reminder' then interval '-1 hour'
          when 'appointment_reminder_day' then interval '-1 day'
          when 'review_request' then interval '3 hours'
          else interval '21 days' end,
        updated_at=statement_timestamp()
    where booking_id=new.id and status='pending'
      and notification_type in ('appointment_reminder','appointment_reminder_day','review_request','rebook_nudge');
  end if;
  return new;
end $$;

-- 5. Owner cancels -> customer is told on LINE
create or replace function public.demo_cancel_booking_and_notify(
  p_booking_id uuid,p_actor_id uuid,p_actor_role text,p_refund_status text,p_owner_line_user_id text
) returns uuid language plpgsql security invoker set search_path='' as $$
declare changed uuid; v_line text;
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
      on conflict do nothing;
  end if;
  if changed is not null and p_actor_role='owner' then
    select line_user_id into v_line from public.demo_booking_line_recipients where booking_id=changed;
    if v_line is not null then
      insert into public.demo_line_notifications(booking_id,recipient_line_user_id,notification_type,scheduled_for)
        values(changed,v_line,'booking_cancelled_by_shop',statement_timestamp())
        on conflict do nothing;
    end if;
  end if;
  return changed;
end $$;
revoke all on function public.demo_cancel_booking_and_notify(uuid,uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.demo_cancel_booking_and_notify(uuid,uuid,text,text,text) to service_role;

-- 6. Live "someone is paying" hold: a pending booking puts its expiry on the slot (customers already get demo_slots via realtime)
create or replace function public.demo_sync_slot_hold()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.status = 'pending' and (tg_op = 'INSERT' or old.status is distinct from 'pending') then
    update public.demo_slots set hold_expires_at = new.expires_at, updated_at = now()
    where slot_date = new.slot_date and start_time = new.start_time;
  elsif tg_op = 'UPDATE' and old.status = 'pending' and new.status <> 'pending' then
    update public.demo_slots set hold_expires_at = null, updated_at = now()
    where slot_date = old.slot_date and start_time = old.start_time
      and hold_expires_at is not distinct from old.expires_at;
  end if;
  return new;
end $$;
drop trigger if exists demo_sync_slot_hold on public.demo_bookings;
create trigger demo_sync_slot_hold after insert or update of status on public.demo_bookings
for each row execute function public.demo_sync_slot_hold();
