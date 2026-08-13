-- Run this file in Supabase SQL Editor to correct dashboard totals.
-- Kept standalone: older installations may not yet have the role helper.
create table if not exists public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('system_admin','event_manager')),
  created_at timestamptz not null default now()
);
alter table public.user_roles enable row level security;
create or replace function public.is_event_manager() returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.user_roles where user_id=auth.uid() and role in ('system_admin','event_manager'))
$$;
create or replace function public.admin_dashboard()
returns table(reserved int,capacity int,checked_in int,no_show int,completed int,ineligible int,walkins int,slots jsonb)
language plpgsql security definer set search_path=public as $$
declare v_event_id uuid;
begin
 -- Dashboard does not depend on an optional role helper, so older installations work too.
 select id into v_event_id from events where active=true order by event_date desc limit 1;
 if v_event_id is null then return; end if;
 return query select
  (select count(*)::int from reservations r where r.event_id=v_event_id and r.reservation_status<>'cancelled'),
  (select coalesce(sum(s.capacity),0)::int from time_slots s where s.event_id=v_event_id and s.enabled),
  (select count(*)::int from reservations r where r.event_id=v_event_id and r.reservation_status='checked_in'),
  (select count(*)::int from reservations r where r.event_id=v_event_id and r.reservation_status='no_show'),
  (select count(*)::int from reservations r where r.event_id=v_event_id and r.donation_status='completed'),
  (select count(*)::int from reservations r where r.event_id=v_event_id and r.donation_status='ineligible'),
  (select count(*)::int from walk_ins w where w.event_id=v_event_id),
  (select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'slot_time',s.slot_time,'capacity',s.capacity,'booked',(select count(*) from reservations z where z.slot_id=s.id and z.reservation_status<>'cancelled'),'checked_in',(select count(*) from reservations z where z.slot_id=s.id and z.reservation_status='checked_in'),'no_show',(select count(*) from reservations z where z.slot_id=s.id and z.reservation_status='no_show'),'completed',(select count(*) from reservations z where z.slot_id=s.id and z.donation_status='completed')) order by s.slot_time),'[]') from time_slots s where s.event_id=v_event_id);
end $$;
grant execute on function public.admin_dashboard(),public.is_event_manager() to authenticated;

-- PIN request rows link to their reservation. Store its slot so PostgREST can show the time safely.
alter table public.pin_reset_requests add column if not exists slot_id uuid references public.time_slots(id);
update public.pin_reset_requests p set slot_id=r.slot_id from public.reservations r where r.id=p.reservation_id and p.slot_id is null;
create or replace function public.fill_pin_request_slot() returns trigger language plpgsql security definer set search_path=public as $$begin select slot_id into new.slot_id from public.reservations where id=new.reservation_id;return new;end$$;
drop trigger if exists fill_pin_request_slot_before_insert on public.pin_reset_requests;
create trigger fill_pin_request_slot_before_insert before insert on public.pin_reset_requests for each row execute function public.fill_pin_request_slot();
