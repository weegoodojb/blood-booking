-- Applied to Supabase on 2026-08-14. Only completed hospital employees are returned.
create or replace function public.completed_employee_donors()
returns table(name text, workplace text, registration_type text)
language plpgsql security definer set search_path=public as $$
declare v_event_id uuid;
begin
 if not exists (select 1 from public.user_roles where user_id=auth.uid() and role in ('system_admin','event_manager')) then raise exception '행사 운영 권한이 필요합니다'; end if;
 select id into v_event_id from public.events where active=true order by event_date desc limit 1;
 if v_event_id is null then return; end if;
 return query
 select r.name, coalesce(nullif(btrim(r.workplace),''),'미입력'), '예약' from public.reservations r where r.event_id=v_event_id and r.participant_type='employee' and r.donation_status='completed'
 union all
 select w.name, coalesce(nullif(btrim(w.workplace),''),'미입력'), '비예약' from public.walk_ins w where w.event_id=v_event_id and w.participant_type='employee' and w.donation_status='completed'
 order by 2, 1;
end $$;
revoke execute on function public.completed_employee_donors() from public, anon;
grant execute on function public.completed_employee_donors() to authenticated;
