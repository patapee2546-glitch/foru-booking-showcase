-- Owner gets a LINE reminder 1 hour before each paid appointment (2026-10-17)

alter table public.demo_line_notifications drop constraint demo_line_notifications_notification_type_check;
alter table public.demo_line_notifications add constraint demo_line_notifications_notification_type_check
  check(notification_type in (
    'booking_confirmed','appointment_reminder','owner_booking_confirmed','owner_booking_cancelled',
    'appointment_reminder_day','booking_cancelled_by_shop','owner_booking_rescheduled','review_request','rebook_nudge',
    'waitlist_open','owner_appointment_reminder'));

-- queue the owner reminder together with the "new booking" alert
create or replace function public.demo_claim_booking_with_owner_notification(
  p_booking_id uuid, p_customer_id uuid, p_slip_path text, p_owner_line_user_id text
) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare
  prior_status text;
  result jsonb;
  v_start timestamptz;
begin
  select status, (slot_date+start_time) at time zone 'Asia/Bangkok' into prior_status, v_start from public.demo_bookings
    where id=p_booking_id and customer_id=p_customer_id for update;
  result := public.demo_claim_booking_and_enqueue(p_booking_id,p_customer_id,p_slip_path);
  if prior_status='pending' and result->>'won'='true'
     and p_owner_line_user_id ~ '^U[0-9a-f]{32}$' then
    insert into public.demo_line_notifications(booking_id,recipient_line_user_id,notification_type,scheduled_for)
      values(p_booking_id,p_owner_line_user_id,'owner_booking_confirmed',statement_timestamp())
      on conflict do nothing;
    if v_start - interval '1 hour' > statement_timestamp() then
      insert into public.demo_line_notifications(booking_id,recipient_line_user_id,notification_type,scheduled_for)
        values(p_booking_id,p_owner_line_user_id,'owner_appointment_reminder',v_start - interval '1 hour')
        on conflict do nothing;
    end if;
  end if;
  return result;
end $$;

-- cancel / reschedule keep the owner reminder in step, like the customer ones
create or replace function private.demo_sync_line_notification_lifecycle()
returns trigger language plpgsql security invoker set search_path = '' as $$
declare v_start timestamptz := (new.slot_date+new.start_time) at time zone 'Asia/Bangkok';
begin
  if new.status='cancelled' and old.status is distinct from new.status then
    update public.demo_line_notifications set status='cancelled',processing_started_at=null,updated_at=statement_timestamp()
    where booking_id=new.id and status in ('pending','processing')
      and notification_type in ('appointment_reminder','appointment_reminder_day','review_request','rebook_nudge','owner_appointment_reminder');
  elsif new.status='approved' and (old.slot_date is distinct from new.slot_date or old.start_time is distinct from new.start_time) then
    update public.demo_line_notifications
    set scheduled_for = v_start + case notification_type
          when 'appointment_reminder' then interval '-1 hour'
          when 'owner_appointment_reminder' then interval '-1 hour'
          when 'appointment_reminder_day' then interval '-1 day'
          when 'review_request' then interval '3 hours'
          else interval '21 days' end,
        updated_at=statement_timestamp()
    where booking_id=new.id and status='pending'
      and notification_type in ('appointment_reminder','appointment_reminder_day','review_request','rebook_nudge','owner_appointment_reminder');
  end if;
  return new;
end $$;

-- bookings already paid: owner reminder for every upcoming one (owner = the LINE user who got the new-booking alerts)
insert into public.demo_line_notifications(booking_id,recipient_line_user_id,notification_type,scheduled_for)
select b.id, o.recipient, 'owner_appointment_reminder', ((b.slot_date+b.start_time) at time zone 'Asia/Bangkok') - interval '1 hour'
from public.demo_bookings b
cross join (select recipient_line_user_id recipient from public.demo_line_notifications
            where notification_type='owner_booking_confirmed' group by 1 order by count(*) desc limit 1) o
where b.status='approved' and ((b.slot_date+b.start_time) at time zone 'Asia/Bangkok') - interval '1 hour' > now()
on conflict do nothing;
