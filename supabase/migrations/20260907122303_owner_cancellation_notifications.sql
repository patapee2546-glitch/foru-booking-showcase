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
