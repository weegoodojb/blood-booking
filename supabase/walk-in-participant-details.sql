-- Applied to Supabase on 2026-08-13.
-- Non-reserved donors keep the same person/affiliation information as reservations.
alter table public.walk_ins
  add column if not exists participant_type text not null default 'visitor' check (participant_type in ('visitor','employee')),
  add column if not exists employee_id text,
  add column if not exists workplace text,
  add column if not exists eligibility_checked boolean not null default false,
  add column if not exists privacy_agreed boolean not null default false;

alter table public.walk_ins drop constraint if exists walk_ins_employee_details_check;
alter table public.walk_ins add constraint walk_ins_employee_details_check
  check (participant_type <> 'employee' or (nullif(btrim(employee_id),'') is not null and nullif(btrim(workplace),'') is not null));
