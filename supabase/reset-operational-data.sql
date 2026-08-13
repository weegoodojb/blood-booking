-- 새 행사 운영을 시작할 때 Supabase SQL Editor에서 실행하세요.
-- 행사 기본정보, 시간대, 연락처, 사용자 계정은 유지하고 운영 기록만 초기화합니다.
begin;
delete from public.pin_reset_requests;
delete from public.walk_ins;
delete from public.reservations;
commit;
