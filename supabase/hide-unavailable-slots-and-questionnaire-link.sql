-- Applied to Supabase on 2026-08-13.
alter table public.events add column if not exists questionnaire_url text;

create or replace function public.public_booking_data()
returns table(event jsonb, slots jsonb, contacts jsonb)
language sql security definer set search_path=public as $$
 select to_jsonb(e),
  coalesce((select jsonb_agg(to_jsonb(x) order by x.slot_time) from (
    select s.*, count(r.id)::int as booked
    from public.time_slots s left join public.reservations r on r.slot_id=s.id and r.reservation_status <> 'cancelled'
    where s.event_id=e.id and s.enabled=true group by s.id
  ) x),'[]'::jsonb),
  coalesce((select jsonb_agg(to_jsonb(c) order by c.display_order) from public.contact_settings c where c.event_id=e.id),'[]'::jsonb)
 from public.events e where e.active=true order by e.event_date desc limit 1
$$;
