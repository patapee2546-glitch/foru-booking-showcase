begin;

alter table public.demo_bookings
  add column if not exists removal_service text,
  add column if not exists slip_path text,
  add column if not exists slip_uploaded_at timestamptz,
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancelled_by uuid references auth.users(id) on delete set null,
  add column if not exists cancelled_by_role text,
  add column if not exists refund_status text;

update public.demo_bookings
set removal_service = 'none'
where removal_service is null;

alter table public.demo_bookings
  alter column removal_service set default 'none',
  alter column removal_service set not null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'demo_bookings_removal_service_check') then
    alter table public.demo_bookings add constraint demo_bookings_removal_service_check
      check (removal_service in ('gel','pvc','none'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'demo_bookings_cancelled_by_role_check') then
    alter table public.demo_bookings add constraint demo_bookings_cancelled_by_role_check
      check (cancelled_by_role is null or cancelled_by_role in ('customer','owner'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'demo_bookings_refund_status_check') then
    alter table public.demo_bookings add constraint demo_bookings_refund_status_check
      check (refund_status is null or refund_status in ('refund_due','no_refund'));
  end if;
end $$;

drop policy if exists demo_bookings_insert_self_pending on public.demo_bookings;
create policy demo_bookings_insert_self_pending
  on public.demo_bookings for insert
  to authenticated
  with check (
    customer_id = (select auth.uid())
    and status = 'pending'
    and removal_service in ('gel','pvc','none')
    and paid_at is null
    and slip_path is null
    and slip_uploaded_at is null
    and cancelled_at is null
    and cancelled_by is null
    and cancelled_by_role is null
    and refund_status is null
    and created_at between now() - interval '5 seconds' and now() + interval '5 seconds'
    and expires_at > now()
    and expires_at <= now() + interval '10 minutes 5 seconds'
    and exists (
      select 1 from public.demo_slots s
      where s.slot_date = demo_bookings.slot_date
        and s.start_time = demo_bookings.start_time
        and s.is_open
    )
  );

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('demo-payment-slips','demo-payment-slips',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set
  public = false,
  file_size_limit = 5242880,
  allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists demo_slips_insert_own_prefix on storage.objects;
create policy demo_slips_insert_own_prefix
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'demo-payment-slips'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists demo_slips_read_self_or_owner on storage.objects;
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

commit;
