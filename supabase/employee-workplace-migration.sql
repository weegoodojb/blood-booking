-- Safe standalone migration: it can run even if operations-security-migration.sql was not run.
alter table public.reservations add column if not exists participant_type text not null default 'visitor' check (participant_type in ('employee','visitor'));
alter table public.reservations add column if not exists employee_id varchar(30);
alter table public.reservations add column if not exists work_area_type text;
alter table public.reservations add column if not exists ward text;
alter table public.reservations add column if not exists workplace text;
alter table public.reservations drop constraint if exists employee_details_required;
alter table public.reservations add constraint employee_details_required check (
  (participant_type='visitor' and employee_id is null and workplace is null)
  or (participant_type='employee' and employee_id is not null and btrim(employee_id)<>'' and workplace is not null and btrim(workplace)<>'')
);
drop function if exists public.create_reservation(uuid,uuid,text,text,text,boolean);
drop function if exists public.create_reservation(uuid,uuid,text,text,text,boolean,text,text,text,text);
drop function if exists public.create_reservation(uuid,uuid,text,text,text,boolean,text,text,text,text,text);
create function public.create_reservation(p_event_id uuid,p_slot_id uuid,p_name text,p_phone text,p_pin text,p_eligibility_checked boolean,p_participant_type text,p_employee_id text,p_work_area_type text,p_ward text,p_workplace text) returns jsonb language plpgsql security definer set search_path=public as $$
declare r reservations; s time_slots; n int; begin
 if p_name='' or p_phone !~ '^[0-9]{9,11}$' or p_pin !~ '^[0-9]{4}$' or p_participant_type not in ('employee','visitor') then return jsonb_build_object('ok',false,'message','입력 정보를 확인해주세요.');end if;
 if p_participant_type='employee' and coalesce(btrim(p_employee_id),'')='' then return jsonb_build_object('ok',false,'message','병원직원은 사번을 입력해주세요.');end if;
 if p_participant_type='employee' and coalesce(btrim(p_workplace),'')='' then return jsonb_build_object('ok',false,'message','병원직원은 근무처를 입력해주세요.');end if;
 select * into s from time_slots where id=p_slot_id and event_id=p_event_id and enabled for update; if not found then return jsonb_build_object('ok',false,'message','선택한 시간을 사용할 수 없습니다.');end if;
 select count(*) into n from reservations where slot_id=p_slot_id and reservation_status<>'cancelled';if n>=s.capacity then return jsonb_build_object('ok',false,'message','선택하신 시간의 예약이 마감되었습니다. 다른 시간을 선택해주세요.');end if;
 if exists(select 1 from reservations where event_id=p_event_id and phone=p_phone and reservation_status<>'cancelled') then return jsonb_build_object('ok',false,'message','이미 예약된 전화번호입니다.');end if;
 insert into reservations(event_id,slot_id,name,phone,pin,eligibility_checked,participant_type,employee_id,work_area_type,ward,workplace) values(p_event_id,p_slot_id,p_name,p_phone,p_pin,p_eligibility_checked,p_participant_type,case when p_participant_type='employee' then nullif(btrim(p_employee_id),'') end,null,null,case when p_participant_type='employee' then nullif(btrim(p_workplace),'') end) returning * into r;
 return jsonb_build_object('ok',true,'reservation',jsonb_build_object('id',r.id,'name',r.name,'pin',r.pin,'slot_time',s.slot_time,'event_date',(select event_date from events where id=p_event_id),'location',(select location from events where id=p_event_id)));
exception when unique_violation then return jsonb_build_object('ok',false,'message','이미 예약된 전화번호입니다.');end$$;
grant execute on function public.create_reservation(uuid,uuid,text,text,text,boolean,text,text,text,text,text) to anon,authenticated;
