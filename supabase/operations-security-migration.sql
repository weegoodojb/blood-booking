-- Run this in Supabase SQL Editor after schema.sql and availability-migration.sql.
-- 1) Roles. The system administrator manages settings; event managers run the event.
create table if not exists public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('system_admin','event_manager')),
  created_at timestamptz not null default now()
);
alter table public.user_roles enable row level security;

create or replace function public.current_app_role() returns text language sql stable security definer set search_path=public as $$
  select role from public.user_roles where user_id=auth.uid()
$$;
create or replace function public.is_system_admin() returns boolean language sql stable security definer set search_path=public as $$
  select public.current_app_role()='system_admin'
$$;
create or replace function public.is_event_manager() returns boolean language sql stable security definer set search_path=public as $$
  select public.current_app_role() in ('system_admin','event_manager')
$$;

-- 2) Replace the MVP's broad "any signed-in user is admin" policies.
drop policy if exists "admin event" on public.events;
drop policy if exists "admin slots" on public.time_slots;
drop policy if exists "admin reservations" on public.reservations;
drop policy if exists "admin walkins" on public.walk_ins;
drop policy if exists "admin pin requests" on public.pin_reset_requests;
drop policy if exists "admin contacts" on public.contact_settings;
create policy "operators view event" on public.events for select to authenticated using (public.is_event_manager());
create policy "system admin changes event" on public.events for update to authenticated using (public.is_system_admin()) with check (public.is_system_admin());
create policy "operators view slots" on public.time_slots for select to authenticated using (public.is_event_manager());
create policy "system admin changes slots" on public.time_slots for all to authenticated using (public.is_system_admin()) with check (public.is_system_admin());
create policy "operators manage reservations" on public.reservations for all to authenticated using (public.is_event_manager()) with check (public.is_event_manager());
create policy "operators manage walkins" on public.walk_ins for all to authenticated using (public.is_event_manager()) with check (public.is_event_manager());
create policy "operators manage pin requests" on public.pin_reset_requests for all to authenticated using (public.is_event_manager()) with check (public.is_event_manager());
create policy "system admin manages contacts" on public.contact_settings for all to authenticated using (public.is_system_admin()) with check (public.is_system_admin());
create policy "system admin manages roles" on public.user_roles for all to authenticated using (public.is_system_admin()) with check (public.is_system_admin());
create or replace function public.list_event_operators() returns table(email text,role text) language plpgsql security definer set search_path=public,auth as $$begin if not public.is_system_admin() then raise exception '시스템 관리자 권한이 필요합니다';end if;return query select u.email::text,r.role from public.user_roles r join auth.users u on u.id=r.user_id order by r.role,u.email;end$$;
create or replace function public.set_event_operator(p_email text,p_enabled boolean) returns jsonb language plpgsql security definer set search_path=public,auth as $$declare target_id uuid;begin if not public.is_system_admin() then raise exception '시스템 관리자 권한이 필요합니다';end if;select id into target_id from auth.users where lower(email)=lower(btrim(p_email));if not found then return jsonb_build_object('ok',false,'message','Supabase Auth에 생성된 계정을 찾을 수 없습니다.');end if;if p_enabled then insert into public.user_roles(user_id,role) values(target_id,'event_manager') on conflict(user_id) do update set role=case when user_roles.role='system_admin' then 'system_admin' else 'event_manager' end;else delete from public.user_roles where user_id=target_id and role='event_manager';end if;return jsonb_build_object('ok',true);end$$;

-- 3) Reservation data for hospital staff and cancellation analysis.
alter table public.reservations add column if not exists participant_type text not null default 'visitor' check (participant_type in ('employee','visitor'));
alter table public.reservations add column if not exists employee_id varchar(30);
alter table public.reservations add column if not exists work_area_type text check (work_area_type in ('ward','other'));
alter table public.reservations add column if not exists ward text;
alter table public.reservations add column if not exists cancellation_reason text check (cancellation_reason in ('personal','schedule','health','duplicate','event_change','other'));
alter table public.reservations add column if not exists cancellation_note text;
alter table public.reservations add column if not exists cancelled_at timestamptz;
alter table public.reservations add constraint employee_details_required check (
  (participant_type='visitor' and employee_id is null and work_area_type is null and ward is null)
  or (participant_type='employee' and employee_id is not null and btrim(employee_id)<>''
      and (work_area_type is null or work_area_type='other' or (work_area_type='ward' and ward is not null and btrim(ward)<>'')))
);

-- 4) Public user functions keep using name, phone, and PIN. No public table access is granted.
drop function if exists public.create_reservation(uuid,uuid,text,text,text,boolean);
drop function if exists public.cancel_reservation(uuid,text);
create function public.create_reservation(p_event_id uuid,p_slot_id uuid,p_name text,p_phone text,p_pin text,p_eligibility_checked boolean,p_participant_type text,p_employee_id text,p_work_area_type text,p_ward text) returns jsonb language plpgsql security definer set search_path=public as $$
declare r reservations; s time_slots; n int; begin
 if p_name='' or p_phone !~ '^[0-9]{9,11}$' or p_pin !~ '^[0-9]{4}$' or p_participant_type not in ('employee','visitor') then return jsonb_build_object('ok',false,'message','입력 정보를 확인해주세요.');end if;
 if p_participant_type='employee' and coalesce(btrim(p_employee_id),'')='' then return jsonb_build_object('ok',false,'message','병원직원은 사번을 입력해주세요.');end if;
 if p_work_area_type='ward' and coalesce(btrim(p_ward),'')='' then return jsonb_build_object('ok',false,'message','병동직원은 병동을 입력해주세요.');end if;
 select * into s from time_slots where id=p_slot_id and event_id=p_event_id and enabled for update; if not found then return jsonb_build_object('ok',false,'message','선택한 시간을 사용할 수 없습니다.');end if;
 select count(*) into n from reservations where slot_id=p_slot_id and reservation_status<>'cancelled';if n>=s.capacity then return jsonb_build_object('ok',false,'message','선택하신 시간의 예약이 마감되었습니다. 다른 시간을 선택해주세요.');end if;
 if exists(select 1 from reservations where event_id=p_event_id and phone=p_phone and reservation_status<>'cancelled') then return jsonb_build_object('ok',false,'message','이미 예약된 전화번호입니다.');end if;
 insert into reservations(event_id,slot_id,name,phone,pin,eligibility_checked,participant_type,employee_id,work_area_type,ward) values(p_event_id,p_slot_id,p_name,p_phone,p_pin,p_eligibility_checked,p_participant_type,case when p_participant_type='employee' then nullif(btrim(p_employee_id),'') end,case when p_participant_type='employee' then p_work_area_type end,case when p_work_area_type='ward' then nullif(btrim(p_ward),'') end) returning * into r;
 return jsonb_build_object('ok',true,'reservation',jsonb_build_object('id',r.id,'name',r.name,'pin',r.pin,'slot_time',s.slot_time,'event_date',(select event_date from events where id=p_event_id),'location',(select location from events where id=p_event_id)));
exception when unique_violation then return jsonb_build_object('ok',false,'message','이미 예약된 전화번호입니다.');end$$;
create function public.cancel_reservation(p_reservation_id uuid,p_pin text,p_reason text,p_note text) returns jsonb language plpgsql security definer set search_path=public as $$begin
 if p_reason not in ('personal','schedule','health','duplicate','event_change','other') then return jsonb_build_object('ok',false,'message','취소 사유를 선택해주세요.');end if;
 update reservations set reservation_status='cancelled',cancellation_reason=p_reason,cancellation_note=nullif(btrim(p_note),''),cancelled_at=now(),updated_at=now() where id=p_reservation_id and pin=p_pin and reservation_status<>'cancelled';return jsonb_build_object('ok',found);end$$;
create or replace function public.admin_dashboard() returns table(reserved int,capacity int,checked_in int,no_show int,completed int,ineligible int,walkins int,slots jsonb) language plpgsql security definer set search_path=public as $$begin if not public.is_event_manager() then raise exception '행사 운영 권한이 필요합니다';end if;return query select count(r.id)filter(where r.reservation_status<>'cancelled')::int,coalesce(sum(s.capacity),0)::int,count(r.id)filter(where r.reservation_status='checked_in')::int,count(r.id)filter(where r.reservation_status='no_show')::int,count(r.id)filter(where r.donation_status='completed')::int,count(r.id)filter(where r.donation_status='ineligible')::int,(select count(*)::int from walk_ins w where w.event_id=e.id),coalesce(jsonb_agg(jsonb_build_object('id',s.id,'slot_time',s.slot_time,'capacity',s.capacity,'booked',(select count(*) from reservations z where z.slot_id=s.id and z.reservation_status<>'cancelled'),'checked_in',(select count(*) from reservations z where z.slot_id=s.id and z.reservation_status='checked_in'),'no_show',(select count(*) from reservations z where z.slot_id=s.id and z.reservation_status='no_show'),'completed',(select count(*) from reservations z where z.slot_id=s.id and z.donation_status='completed')) order by s.slot_time),'[]') from events e left join time_slots s on s.event_id=e.id left join reservations r on r.event_id=e.id where e.active=true group by e.id;end$$;
grant execute on function public.current_app_role(),public.is_system_admin(),public.is_event_manager(),public.admin_dashboard(),public.list_event_operators(),public.set_event_operator(text,boolean) to authenticated;
grant execute on function public.create_reservation(uuid,uuid,text,text,text,boolean,text,text,text,text),public.cancel_reservation(uuid,text,text,text) to anon,authenticated;

-- 5) Replace these emails after creating the accounts in Authentication > Users.
-- insert into public.user_roles(user_id,role) select id,'system_admin' from auth.users where email='YOUR_ADMIN_EMAIL' on conflict(user_id) do update set role=excluded.role;
-- insert into public.user_roles(user_id,role) select id,'event_manager' from auth.users where email in ('BLOOD_CENTER_EMAIL','PROFESSOR_EMAIL') on conflict(user_id) do update set role=excluded.role;
