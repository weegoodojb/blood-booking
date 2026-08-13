-- Applied to Supabase on 2026-08-13.
-- This keeps the dashboard from calling disabled slots "available" and limits
-- booking-time settings to the system administrator.
create or replace function public.admin_dashboard()
returns table(reserved int,capacity int,checked_in int,no_show int,completed int,ineligible int,walkins int,slots jsonb)
language plpgsql security definer set search_path=public as $$
declare v_event_id uuid;
begin
 if not exists (select 1 from public.user_roles where user_id=auth.uid() and role in ('system_admin','event_manager')) then
   raise exception '행사 운영 권한이 필요합니다';
 end if;
 select id into v_event_id from public.events where active=true order by event_date desc limit 1;
 if v_event_id is null then return; end if;
 return query select
  (select count(*)::int from public.reservations r where r.event_id=v_event_id and r.reservation_status<>'cancelled'),
  (select coalesce(sum(s.capacity),0)::int from public.time_slots s where s.event_id=v_event_id and s.enabled),
  (select count(*)::int from public.reservations r where r.event_id=v_event_id and r.reservation_status='checked_in'),
  (select count(*)::int from public.reservations r where r.event_id=v_event_id and r.reservation_status='no_show'),
  (select count(*)::int from public.reservations r where r.event_id=v_event_id and r.donation_status='completed'),
  (select count(*)::int from public.reservations r where r.event_id=v_event_id and r.donation_status='ineligible'),
  (select count(*)::int from public.walk_ins w where w.event_id=v_event_id),
  (select coalesce(jsonb_agg(jsonb_build_object(
    'id',s.id,'slot_time',s.slot_time,'capacity',s.capacity,'enabled',s.enabled,
    'booked',(select count(*) from public.reservations z where z.slot_id=s.id and z.reservation_status<>'cancelled'),
    'checked_in',(select count(*) from public.reservations z where z.slot_id=s.id and z.reservation_status='checked_in'),
    'no_show',(select count(*) from public.reservations z where z.slot_id=s.id and z.reservation_status='no_show'),
    'completed',(select count(*) from public.reservations z where z.slot_id=s.id and z.donation_status='completed')
  ) order by s.slot_time),'[]'::jsonb) from public.time_slots s where s.event_id=v_event_id);
end $$;

create or replace function public.generate_time_slots(p_event_id uuid,p_start time,p_end time,p_interval integer,p_capacity integer,p_unavailable_ranges jsonb default '[]'::jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare slot_at time:=p_start; allowed boolean; created_count int:=0;
begin
 if not exists (select 1 from public.user_roles where user_id=auth.uid() and role='system_admin') then
   raise exception '기준정보 관리 권한이 필요합니다';
 end if;
 if p_end<=p_start or p_interval<5 or p_capacity<1 then return jsonb_build_object('ok',false,'message','예약 시간 설정을 확인해주세요.'); end if;
 perform 1 from public.events where id=p_event_id for update;
 if not found then return jsonb_build_object('ok',false,'message','행사 정보를 찾을 수 없습니다.'); end if;
 update public.events set booking_start=p_start,booking_end=p_end,slot_interval_minutes=p_interval,default_slot_capacity=p_capacity,unavailable_ranges=p_unavailable_ranges where id=p_event_id;
 update public.time_slots s set enabled=false where s.event_id=p_event_id and not exists(select 1 from public.reservations r where r.slot_id=s.id and r.reservation_status<>'cancelled');
 while slot_at < p_end loop
  allowed:=not exists(select 1 from jsonb_to_recordset(p_unavailable_ranges) as b(start time,finish time) where slot_at>=b.start and slot_at<b.finish);
  if allowed then
   insert into public.time_slots(event_id,slot_time,capacity,enabled) values(p_event_id,slot_at,p_capacity,true)
   on conflict(event_id,slot_time) do update set capacity=excluded.capacity,enabled=true;
   created_count:=created_count+1;
  end if;
  slot_at:=slot_at+(p_interval||' minutes')::interval;
 end loop;
 return jsonb_build_object('ok',true,'created',created_count);
end $$;
