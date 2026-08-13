-- Applied to Supabase on 2026-08-14.
alter table public.reservations add column if not exists cancellation_reason text, add column if not exists cancellation_note text, add column if not exists cancelled_at timestamptz;

create or replace function public.cancel_reservation(p_reservation_id uuid,p_pin text,p_reason text,p_note text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if p_reason not in ('personal','schedule','health','duplicate','event_change','other') then return jsonb_build_object('ok',false,'message','취소 사유를 선택해주세요.'); end if;
 if p_reason='other' and coalesce(nullif(btrim(p_note),''),'')='' then return jsonb_build_object('ok',false,'message','기타 취소 사유를 입력해주세요.'); end if;
 update public.reservations set reservation_status='cancelled',cancellation_reason=p_reason,cancellation_note=nullif(btrim(p_note),''),cancelled_at=now(),updated_at=now() where id=p_reservation_id and pin=p_pin and reservation_status<>'cancelled';
 if not found then return jsonb_build_object('ok',false,'message','취소할 예약을 찾을 수 없거나 이미 취소된 예약입니다.'); end if;
 return jsonb_build_object('ok',true);
end $$;
revoke execute on function public.cancel_reservation(uuid,text,text,text) from public;
grant execute on function public.cancel_reservation(uuid,text,text,text) to anon, authenticated;
