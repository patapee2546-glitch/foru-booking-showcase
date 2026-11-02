create schema if not exists private;

create table if not exists public.demo_reschedule_requests (
  id uuid primary key default gen_random_uuid(), booking_id uuid not null references public.demo_bookings(id) on delete cascade,
  customer_id uuid not null references auth.users(id) on delete cascade,
  old_slot_date date not null, old_start_time time not null, old_end_time time not null,
  new_slot_date date not null, new_start_time time not null, new_end_time time not null,
  fee_amount integer not null default 20 check (fee_amount=20),
  status text not null default 'awaiting_slip' check (status in ('awaiting_slip','pending_review','approved','rejected','expired','cancelled')),
  expires_at timestamptz not null default (now()+interval '10 minutes'), slip_path text, slip_uploaded_at timestamptz,
  reviewed_at timestamptz, reviewed_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create unique index if not exists demo_reschedule_active_new_slot_unique on public.demo_reschedule_requests(new_slot_date,new_start_time) where status in ('awaiting_slip','pending_review');
create unique index if not exists demo_reschedule_one_active_per_booking on public.demo_reschedule_requests(booking_id) where status in ('awaiting_slip','pending_review');
create index if not exists demo_reschedule_customer_idx on public.demo_reschedule_requests(customer_id,created_at desc);
create index if not exists demo_reschedule_merchant_idx on public.demo_reschedule_requests(new_slot_date,new_start_time,status);

create table if not exists public.demo_booking_reschedule_history (
  id uuid primary key default gen_random_uuid(), request_id uuid not null unique references public.demo_reschedule_requests(id) on delete restrict,
  booking_id uuid not null references public.demo_bookings(id) on delete cascade, customer_id uuid not null references auth.users(id) on delete cascade,
  old_slot_date date not null, old_start_time time not null, old_end_time time not null,
  new_slot_date date not null, new_start_time time not null, new_end_time time not null,
  fee_amount integer not null check (fee_amount=20), fee_slip_path text not null,
  approved_at timestamptz not null default now(), approved_by uuid references auth.users(id) on delete set null
);

alter table public.demo_reschedule_requests enable row level security;
alter table public.demo_booking_reschedule_history enable row level security;
revoke all on table public.demo_reschedule_requests from anon,authenticated;
revoke all on table public.demo_booking_reschedule_history from anon,authenticated;
grant select on table public.demo_reschedule_requests to authenticated;
grant select on table public.demo_booking_reschedule_history to authenticated;

drop policy if exists demo_reschedule_read_owner_or_self on public.demo_reschedule_requests;
create policy demo_reschedule_read_owner_or_self on public.demo_reschedule_requests for select to authenticated
using (customer_id=(select auth.uid()) or (select auth.jwt()->'app_metadata'->>'role')='owner');
drop policy if exists demo_reschedule_history_read_owner_or_self on public.demo_booking_reschedule_history;
create policy demo_reschedule_history_read_owner_or_self on public.demo_booking_reschedule_history for select to authenticated
using (customer_id=(select auth.uid()) or (select auth.jwt()->'app_metadata'->>'role')='owner');

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('demo-reschedule-slips','demo-reschedule-slips',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];
drop policy if exists demo_reschedule_slips_insert_own_prefix on storage.objects;
create policy demo_reschedule_slips_insert_own_prefix on storage.objects for insert to authenticated
with check(bucket_id='demo-reschedule-slips' and (storage.foldername(name))[1]=(select auth.uid())::text);
drop policy if exists demo_reschedule_slips_read_self_or_owner on storage.objects;
create policy demo_reschedule_slips_read_self_or_owner on storage.objects for select to authenticated
using(bucket_id='demo-reschedule-slips' and ((storage.foldername(name))[1]=(select auth.uid())::text or (select auth.jwt()->'app_metadata'->>'role')='owner'));

create or replace function public.expire_demo_reschedules() returns integer language plpgsql security invoker as $$
declare v_request public.demo_reschedule_requests%rowtype; v_count integer:=0;
begin
  for v_request in select * from public.demo_reschedule_requests where status='awaiting_slip' and expires_at<=now() for update skip locked loop
    update public.demo_reschedule_requests set status='expired',updated_at=now() where id=v_request.id;
    update public.demo_slots s set is_open=true,updated_at=now() where s.slot_date=v_request.new_slot_date and s.start_time=v_request.new_start_time
      and not exists(select 1 from public.demo_bookings b where b.slot_date=s.slot_date and b.start_time=s.start_time and b.status='approved')
      and not exists(select 1 from public.demo_reschedule_requests r where r.new_slot_date=s.slot_date and r.new_start_time=s.start_time and r.status in ('awaiting_slip','pending_review'));
    v_count:=v_count+1;
  end loop;
  return v_count;
end; $$;

create or replace function public.create_demo_reschedule(p_booking_id uuid,p_customer_id uuid,p_new_slot_date date,p_new_start_time time)
returns jsonb language plpgsql security invoker as $$
declare v_booking public.demo_bookings%rowtype; v_old_slot public.demo_slots%rowtype; v_new_slot public.demo_slots%rowtype;
v_request public.demo_reschedule_requests%rowtype; v_appointment timestamptz;
begin
  perform public.expire_demo_reschedules();
  select * into v_booking from public.demo_bookings where id=p_booking_id and customer_id=p_customer_id for update;
  if not found or v_booking.status<>'approved' then raise exception 'BOOKING_NOT_ELIGIBLE'; end if;
  v_appointment:=(v_booking.slot_date::text||' '||v_booking.start_time::text)::timestamp at time zone 'Asia/Bangkok';
  if (now() at time zone 'Asia/Bangkok')::date>=v_booking.slot_date then raise exception 'RESCHEDULE_DEADLINE_PASSED'; end if;
  select * into v_old_slot from public.demo_slots where slot_date=v_booking.slot_date and start_time=v_booking.start_time for update;
  select * into v_new_slot from public.demo_slots where slot_date=p_new_slot_date and start_time=p_new_start_time for update;
  if not found or not v_new_slot.is_open then raise exception 'NEW_SLOT_UNAVAILABLE'; end if;
  if exists(select 1 from public.demo_bookings where slot_date=p_new_slot_date and start_time=p_new_start_time and status='approved') then raise exception 'NEW_SLOT_UNAVAILABLE'; end if;
  insert into public.demo_reschedule_requests(booking_id,customer_id,old_slot_date,old_start_time,old_end_time,new_slot_date,new_start_time,new_end_time)
  values(v_booking.id,p_customer_id,v_booking.slot_date,v_booking.start_time,v_old_slot.end_time,p_new_slot_date,p_new_start_time,v_new_slot.end_time) returning * into v_request;
  update public.demo_slots set is_open=false,updated_at=now() where id=v_new_slot.id;
  return to_jsonb(v_request);
end; $$;

create or replace function public.review_demo_reschedule(p_request_id uuid,p_decision text,p_owner_id uuid)
returns jsonb language plpgsql security invoker as $$
declare v_request public.demo_reschedule_requests%rowtype; v_booking public.demo_bookings%rowtype;
begin
  if p_decision not in ('approve','reject') then raise exception 'INVALID_DECISION'; end if;
  select * into v_request from public.demo_reschedule_requests where id=p_request_id for update;
  if not found or v_request.status<>'pending_review' then raise exception 'REQUEST_NOT_REVIEWABLE'; end if;
  if p_decision='reject' then
    update public.demo_reschedule_requests set status='rejected',reviewed_at=now(),reviewed_by=p_owner_id,updated_at=now() where id=p_request_id returning * into v_request;
    update public.demo_slots s set is_open=true,updated_at=now(),updated_by=p_owner_id where s.slot_date=v_request.new_slot_date and s.start_time=v_request.new_start_time
      and not exists(select 1 from public.demo_bookings b where b.slot_date=s.slot_date and b.start_time=s.start_time and b.status='approved');
    return jsonb_build_object('request',to_jsonb(v_request));
  end if;
  select * into v_booking from public.demo_bookings where id=v_request.booking_id for update;
  if not found or v_booking.status<>'approved' or v_booking.slot_date<>v_request.old_slot_date or v_booking.start_time<>v_request.old_start_time then raise exception 'BOOKING_CHANGED'; end if;
  if v_request.slip_path is null then raise exception 'RESCHEDULE_SLIP_REQUIRED'; end if;
  update public.demo_bookings set slot_date=v_request.new_slot_date,start_time=v_request.new_start_time where id=v_booking.id returning * into v_booking;
  update public.demo_slots set is_open=true,updated_at=now(),updated_by=p_owner_id where slot_date=v_request.old_slot_date and start_time=v_request.old_start_time;
  update public.demo_slots set is_open=false,updated_at=now(),updated_by=p_owner_id where slot_date=v_request.new_slot_date and start_time=v_request.new_start_time;
  update public.demo_reschedule_requests set status='approved',reviewed_at=now(),reviewed_by=p_owner_id,updated_at=now() where id=p_request_id returning * into v_request;
  insert into public.demo_booking_reschedule_history(request_id,booking_id,customer_id,old_slot_date,old_start_time,old_end_time,new_slot_date,new_start_time,new_end_time,fee_amount,fee_slip_path,approved_by)
  values(v_request.id,v_request.booking_id,v_request.customer_id,v_request.old_slot_date,v_request.old_start_time,v_request.old_end_time,v_request.new_slot_date,v_request.new_start_time,v_request.new_end_time,v_request.fee_amount,v_request.slip_path,p_owner_id);
  return jsonb_build_object('request',to_jsonb(v_request),'booking',to_jsonb(v_booking));
end; $$;

revoke all on function public.create_demo_reschedule(uuid,uuid,date,time) from public,anon,authenticated;
revoke all on function public.review_demo_reschedule(uuid,text,uuid) from public,anon,authenticated;
revoke all on function public.expire_demo_reschedules() from public,anon,authenticated;
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

do $$ begin
  alter publication supabase_realtime add table public.demo_reschedule_requests;
exception when duplicate_object then null;
end $$;
