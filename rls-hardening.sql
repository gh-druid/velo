-- =============================================================
-- VÉLO — RLS 점검 & 하드닝
-- 실행: Supabase 대시보드 > SQL Editor
-- =============================================================
-- 점검 방법: publishable(anon) 키로 각 테이블을 실제 호출해본 결과,
-- REST 카탈로그(pg_policies)는 API로 못 읽으므로 행동 기반으로 점검함.
--
-- [확정된 문제]
--  1) users: anon(공개 키)이 전체 유저의 email/phone/is_admin 을 읽을 수 있음 (PII 유출)
--  2) bounty_claims: 내가 만든 정책이 select using(true) 라
--     데이터가 쌓이면 제보자 계좌/은행/연락처가 anon에게 노출됨 (잠재 유출)
--
-- [확인된 정상]
--  - users UPDATE/DELETE 는 RLS가 차단함 (anon이 is_admin 조작 불가) — 양호
--
-- 아래 1~2번은 "컬럼 단위 권한"만 조정 → 쓰기 정책/로그인 흐름을 건드리지
-- 않으므로 안전합니다. 적용 후 공개 자전거 페이지에서 소유자 이름이
-- 잘 보이는지만 확인하세요.
-- =============================================================


-- =============================================================
-- (A) 권위 있는 점검 쿼리 — 먼저 실행해서 현재 RLS 상태를 확인하세요
-- =============================================================
-- 테이블별 RLS 활성화 여부
select relname as table_name,
       relrowsecurity  as rls_enabled,
       relforcerowsecurity as rls_forced
from pg_class
where relnamespace = 'public'::regnamespace and relkind = 'r'
order by relname;

-- 테이블별 정책 목록 (명령/대상 역할/조건)
select schemaname, tablename, policyname,
       cmd, roles, qual as using_expr, with_check
from pg_policies
where schemaname = 'public'
order by tablename, policyname;

-- anon/authenticated 역할의 테이블 권한 (GRANT) 확인
select table_name, grantee, string_agg(privilege_type, ', ' order by privilege_type) as privs
from information_schema.role_table_grants
where table_schema = 'public' and grantee in ('anon','authenticated')
group by table_name, grantee
order by table_name, grantee;


-- =============================================================
-- (B) 하드닝 #1 — users 민감 컬럼을 anon에게서 숨김
--   anon 은 공개 자전거 페이지의 "소유자 이름/연락처" 표시에만 필요하므로
--   email / is_admin / ip / user_agent / warning_count 는 가릴 수 있음.
--   (현재 앱은 anon 경로에서 users.email 을 select 하지 않으므로 안전)
-- =============================================================
revoke select on public.users from anon;
grant select (id, name, phone, plan, avg_rating, created_at, lifetime_free, referral_code)
  on public.users to anon;
-- 로그인 유저(authenticated)는 본인 프로필 조회를 위해 전체 컬럼 유지
grant select on public.users to authenticated;
-- ※ phone 도 가리고 싶으면 위 목록에서 phone 을 빼세요(소유자 연락은 email 링크 사용).


-- =============================================================
-- (C) 하드닝 #2 — bounty_claims 의 제보자 금융정보를 anon에게서 숨김
--   anon(제보자 본인)은 자기 제보의 "상태"만 확인하면 되므로
--   finder_account / finder_bank / finder_phone / finder_name 은 가림.
--   소유자(authenticated)와 관리자는 지급을 위해 전체 컬럼 유지.
-- =============================================================
revoke select on public.bounty_claims from anon;
grant select (id, bike_id, status, location, location_detail, photos, found_at, created_at)
  on public.bounty_claims to anon;
grant select on public.bounty_claims to authenticated;


-- =============================================================
-- (D) (선택) bounty_claims 쓰기 정책 강화
--   현재 anon update 가 using(true) 라, 제보자가 자기 제보를
--   임의 상태(예: paid)로 바꿀 여지가 있음. 이의 제기(disputed)만
--   허용하도록 좁히는 예시 (지급 처리는 authenticated 소유자가 수행):
-- =============================================================
-- drop policy if exists bounty_claims_update on public.bounty_claims;
-- create policy bounty_claims_update_anon on public.bounty_claims
--   for update to anon using (true) with check (status = 'disputed');
-- create policy bounty_claims_update_auth on public.bounty_claims
--   for update to authenticated using (true) with check (true);


-- =============================================================
-- (E) 점검 권고 — 아래 테이블은 금융/PII 포함. (A) 쿼리 결과로
--   RLS 활성화 + anon SELECT 차단 여부를 꼭 확인하세요.
--   (현재 데이터가 비어 있어 행동 테스트로는 확정 불가)
--     - orders                (배송지/연락처/결제키)
--     - referral_withdrawals  (은행/계좌/예금주)
--     - partnerships          (담당자/연락처/주소)
--     - referral_logs
--   원칙: SELECT/UPDATE/DELETE 는 본인(auth.uid()) 또는 관리자만 허용,
--         INSERT 만 필요한 흐름에 맞게 개방.
-- =============================================================
