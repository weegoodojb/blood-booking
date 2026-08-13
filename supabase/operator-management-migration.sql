-- Run this entire file in Supabase SQL Editor.
-- It is safe even if user_roles already exists.
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
drop policy if exists "system admin manages roles" on public.user_roles;
create policy "system admin manages roles" on public.user_roles for all to authenticated using (public.is_system_admin()) with check (public.is_system_admin());

create or replace function public.list_event_operators()
returns table(email text,role text)
language plpgsql security definer set search_path=public,auth as $$
begin
  if not public.is_system_admin() then raise exception '시스템 관리자 권한이 필요합니다'; end if;
  return query
    select u.email::text,r.role
    from public.user_roles r join auth.users u on u.id=r.user_id
    order by r.role,u.email;
end $$;

create or replace function public.set_event_operator(p_email text,p_enabled boolean)
returns jsonb
language plpgsql security definer set search_path=public,auth as $$
declare target_id uuid;
begin
  if not public.is_system_admin() then raise exception '시스템 관리자 권한이 필요합니다'; end if;
  select id into target_id from auth.users where lower(email)=lower(btrim(p_email));
  if not found then return jsonb_build_object('ok',false,'message','Supabase Auth에 생성된 계정을 찾을 수 없습니다.'); end if;
  if p_enabled then
    insert into public.user_roles(user_id,role) values(target_id,'event_manager')
    on conflict(user_id) do update set role=case when user_roles.role='system_admin' then 'system_admin' else 'event_manager' end;
  else
    delete from public.user_roles where user_id=target_id and role='event_manager';
  end if;
  return jsonb_build_object('ok',true);
end $$;

grant execute on function public.current_app_role(),public.is_system_admin(),public.list_event_operators(),public.set_event_operator(text,boolean) to authenticated;

-- After this script succeeds, run this once with your own admin email:
-- insert into public.user_roles(user_id,role)
-- select id,'system_admin' from auth.users where email='YOUR_ADMIN_EMAIL'
-- on conflict(user_id) do update set role=excluded.role;
