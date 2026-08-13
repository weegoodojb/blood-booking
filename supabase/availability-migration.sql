-- 이미 schema.sql을 실행한 경우에만 이 파일을 추가로 실행하세요.
alter table public.events add column if not exists booking_start time;
alter table public.events add column if not exists booking_end time;
alter table public.events add column if not exists slot_interval_minutes integer not null default 30 check (slot_interval_minutes between 5 and 240);
alter table public.events add column if not exists default_slot_capacity integer not null default 5 check (default_slot_capacity > 0);
alter table public.events add column if not exists unavailable_ranges jsonb not null default '[]'::jsonb;
-- 기존에 안내 링크가 비어 있는 행사에만 기본 링크를 넣습니다. 관리자가 입력한 링크는 바꾸지 않습니다.
update public.events
set eligibility_url = 'https://lumpy-azimuth-7eb.notion.site/3bbe4a07fa58801aa4a1ed1578a947ac?source=copy_link'
where eligibility_url is null or btrim(eligibility_url) = '';

create or replace function public.generate_time_slots(p_event_id uuid,p_start time,p_end time,p_interval integer,p_capacity integer,p_unavailable_ranges jsonb default '[]'::jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare slot_at time:=p_start; allowed boolean; created_count int:=0;
begin
 if auth.role() <> 'authenticated' then raise exception '관리자 인증이 필요합니다'; end if;
 if p_end<=p_start or p_interval<5 or p_capacity<1 then return jsonb_build_object('ok',false,'message','예약 시간 설정을 확인해주세요.'); end if;
 perform 1 from events where id=p_event_id for update; if not found then return jsonb_build_object('ok',false,'message','행사 정보를 찾을 수 없습니다.'); end if;
 update events set booking_start=p_start,booking_end=p_end,slot_interval_minutes=p_interval,default_slot_capacity=p_capacity,unavailable_ranges=p_unavailable_ranges where id=p_event_id;
 -- 먼저 모든 미예약 슬롯을 숨긴 뒤, 이번 설정에 포함되는 슬롯만 다시 활성화합니다.
 update time_slots s set enabled=false where s.event_id=p_event_id and not exists(select 1 from reservations r where r.slot_id=s.id and r.reservation_status<>'cancelled');
 while slot_at < p_end loop
  allowed:=not exists(select 1 from jsonb_to_recordset(p_unavailable_ranges) as b(start time,finish time) where slot_at>=b.start and slot_at<b.finish);
  if allowed then
   insert into time_slots(event_id,slot_time,capacity,enabled) values(p_event_id,slot_at,p_capacity,true)
   on conflict(event_id,slot_time) do update set capacity=excluded.capacity,enabled=true;
   created_count:=created_count+1;
  end if;
  slot_at:=slot_at+(p_interval||' minutes')::interval;
 end loop;
 return jsonb_build_object('ok',true,'created',created_count);
end $$;
grant execute on function public.generate_time_slots(uuid,time,time,integer,integer,jsonb) to authenticated;
