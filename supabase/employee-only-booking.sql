-- Run this in Supabase SQL Editor after employee-workplace-migration.sql.
-- Existing visitor records are preserved, but new public reservations are employees only.
drop function if exists public.create_reservation(uuid,uuid,text,text,text,boolean,text,text,text,text,text);

create function public.create_reservation(
  p_event_id uuid, p_slot_id uuid, p_name text, p_phone text, p_pin text,
  p_eligibility_checked boolean, p_participant_type text, p_employee_id text,
  p_work_area_type text, p_ward text, p_workplace text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare r reservations; s time_slots; n int;
begin
  if p_name='' or p_phone !~ '^[0-9]{9,11}$' or p_pin !~ '^[0-9]{4}$'
     or p_participant_type <> 'employee' then
    return jsonb_build_object('ok',false,'message','병원직원 예약 정보만 입력할 수 있습니다.');
  end if;
  if coalesce(btrim(p_employee_id),'')='' then return jsonb_build_object('ok',false,'message','사번을 입력해주세요.'); end if;
  if coalesce(btrim(p_workplace),'')='' then return jsonb_build_object('ok',false,'message','근무처를 입력해주세요.'); end if;
  select * into s from time_slots where id=p_slot_id and event_id=p_event_id and enabled for update;
  if not found then return jsonb_build_object('ok',false,'message','선택한 시간을 사용할 수 없습니다.'); end if;
  select count(*) into n from reservations where slot_id=p_slot_id and reservation_status<>'cancelled';
  if n>=s.capacity then return jsonb_build_object('ok',false,'message','선택하신 시간의 예약이 마감되었습니다. 다른 시간을 선택해주세요.'); end if;
  if exists(select 1 from reservations where event_id=p_event_id and phone=p_phone and reservation_status<>'cancelled') then
    return jsonb_build_object('ok',false,'message','이미 예약된 전화번호입니다.');
  end if;
  insert into reservations(event_id,slot_id,name,phone,pin,eligibility_checked,participant_type,employee_id,work_area_type,ward,workplace)
  values(p_event_id,p_slot_id,p_name,p_phone,p_pin,p_eligibility_checked,'employee',nullif(btrim(p_employee_id),''),null,null,nullif(btrim(p_workplace),''))
  returning * into r;
  return jsonb_build_object('ok',true,'reservation',jsonb_build_object('id',r.id,'name',r.name,'pin',r.pin,'slot_time',s.slot_time,'event_date',(select event_date from events where id=p_event_id),'location',(select location from events where id=p_event_id)));
exception when unique_violation then return jsonb_build_object('ok',false,'message','이미 예약된 전화번호입니다.');
end $$;

grant execute on function public.create_reservation(uuid,uuid,text,text,text,boolean,text,text,text,text,text) to anon,authenticated;
