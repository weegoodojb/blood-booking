# 순천향대학교 부천병원 헌혈예약 MVP

## 실행

1. Supabase 프로젝트를 만들고 `supabase/schema.sql` 전체를 SQL Editor에서 실행합니다. 기존 운영 DB는 기존에 적용한 SQL을 유지한 채 `supabase/employee-only-booking.sql`과 `supabase/detailed-statistics.sql`을 추가 실행합니다. 전자는 기존 방문객 기록을 보존하고 이후 공개 예약만 직원 예약으로 제한하며, 후자는 통계의 상태별 상세 명단과 완료 기준 근무처 집계를 제공합니다. 역할/행사진행자 메뉴는 `supabase/operator-management-migration.sql`을 실행합니다.
2. Authentication > Users에서 관리자 이메일/비밀번호 계정을 생성합니다. (회원가입은 비활성화 권장)
3. `.env.example`을 `.env.local`로 복사해 Project URL과 anon key를 입력합니다.
4. `npm install && npm run dev`

## 배포

Git 저장소를 Vercel에 연결하고 위의 두 환경변수를 Vercel Project Settings > Environment Variables에 등록한 뒤 배포합니다. service role key는 사용하거나 등록하지 않습니다.

## 운영

`/admin/settings`에서 행사명, 날짜, 장소, 전자문진 링크와 혈액원·수혈관리실 담당자 전화번호를 수정합니다. 저장한 전화번호는 예약 홈의 예약 문의에 표시됩니다. 예약 시작/종료, 주기, 주기당 정원과 점심시간 같은 예약 불가 구간을 입력한 후 **예약 시간대 생성·갱신**을 누르면 시간대가 자동으로 만들어집니다. 기존 예약이 있는 시간은 삭제하지 않고 보존합니다. 예약 생성과 시간 변경은 DB 함수가 행 잠금을 사용해 동시 정원 초과를 막습니다.
