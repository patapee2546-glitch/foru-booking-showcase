begin;

create table if not exists public.demo_holidays (
  day date primary key,
  previously_open time[] not null default '{}',
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null
);

alter table public.demo_holidays enable row level security;
grant select on public.demo_holidays to authenticated;
revoke insert, update, delete on public.demo_holidays from anon, authenticated;
drop policy if exists demo_holidays_read on public.demo_holidays;
create policy demo_holidays_read on public.demo_holidays for select to authenticated using (true);

create or replace function public.demo_set_holiday(p_day date, p_closed boolean)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_open time[];
begin
  if auth.uid() is null or auth.jwt()->'app_metadata'->>'role' is distinct from 'owner' then
    raise exception 'OWNER_REQUIRED';
  end if;
  if p_day is null or p_closed is null then raise exception 'INVALID_HOLIDAY'; end if;
  perform pg_advisory_xact_lock(hashtextextended('demo-holiday-' || p_day::text, 0));
  if p_closed then
    if exists(select 1 from public.demo_bookings b where b.slot_date=p_day and
      (b.status='approved' or (b.status='pending' and b.expires_at>clock_timestamp())))
      or exists(select 1 from public.demo_reschedule_requests r where r.new_slot_date=p_day
        and r.status in ('awaiting_slip','pending_review') and r.expires_at>clock_timestamp()) then
      raise exception 'DAY_HAS_BOOKINGS';
    end if;
    if exists(select 1 from public.demo_holidays where day=p_day) then return true; end if;
    select coalesce(array_agg(start_time order by start_time), '{}') into v_open
      from public.demo_slots where slot_date=p_day and is_open;
    insert into public.demo_holidays(day,previously_open,created_by) values(p_day,v_open,auth.uid());
    update public.demo_slots set is_open=false,updated_at=now(),updated_by=auth.uid()
      where slot_date=p_day and is_open;
  else
    select previously_open into v_open from public.demo_holidays where day=p_day for update;
    if not found then return false; end if;
    delete from public.demo_holidays where day=p_day;
    update public.demo_slots s set is_open=true,updated_at=now(),updated_by=auth.uid()
      where s.slot_date=p_day and s.start_time=any(v_open) and not s.is_booked
        and not exists(select 1 from public.demo_bookings b where b.slot_date=p_day and b.start_time=s.start_time
          and (b.status='approved' or (b.status='pending' and b.expires_at>clock_timestamp())))
        and not exists(select 1 from public.demo_reschedule_requests r where r.new_slot_date=p_day
          and r.new_start_time=s.start_time and r.status in ('awaiting_slip','pending_review')
          and r.expires_at>clock_timestamp());
  end if;
  return p_closed;
end $$;

revoke all on function public.demo_set_holiday(date,boolean) from public,anon;
grant execute on function public.demo_set_holiday(date,boolean) to authenticated;

create or replace function public.demo_guard_holiday_slot()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.is_open then
    perform pg_advisory_xact_lock(hashtextextended('demo-holiday-' || new.slot_date::text, 0));
    if exists(select 1 from public.demo_holidays where day=new.slot_date) then
      raise exception 'HOLIDAY_CLOSED';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists demo_guard_holiday_slot on public.demo_slots;
create trigger demo_guard_holiday_slot before insert or update of is_open,slot_date on public.demo_slots
for each row execute function public.demo_guard_holiday_slot();

create or replace function public.demo_guard_holiday_booking()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.status in ('pending','approved') then
    perform pg_advisory_xact_lock(hashtextextended('demo-holiday-' || new.slot_date::text, 0));
    if exists(select 1 from public.demo_holidays where day=new.slot_date) then
      raise exception 'HOLIDAY_CLOSED';
    end if;
  end if;
  return new;
end $$;
drop trigger if exists demo_guard_holiday_booking on public.demo_bookings;
create trigger demo_guard_holiday_booking before insert or update of slot_date,status on public.demo_bookings
for each row execute function public.demo_guard_holiday_booking();

do $$ begin
  if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='demo_holidays') then
    alter publication supabase_realtime add table public.demo_holidays;
  end if;
end $$;
commit;
