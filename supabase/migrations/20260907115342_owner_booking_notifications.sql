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
