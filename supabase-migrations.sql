-- =============================================================
-- VÉLO — Supabase 스키마/권한 보정 마이그레이션
-- 실행: Supabase 대시보드 > SQL Editor 에 붙여넣고 Run
-- (REST API로는 DDL/GRANT 실행이 불가하여 직접 실행이 필요합니다)
-- 모두 idempotent — 여러 번 실행해도 안전합니다.
-- =============================================================

-- -------------------------------------------------------------
-- 1) users.is_suspended 누락 → 계정 정지/경고 기능이 에러남
--    (admin 계정 정지, 경고 3회 자동 정지에서 update 실패)
-- -------------------------------------------------------------
alter table public.users
  add column if not exists is_suspended boolean not null default false;

-- (선택) 참고용: 평점/경고 컬럼은 이미 존재함 (avg_rating, warning_count)


-- -------------------------------------------------------------
-- 2) bounty_claims — anon/authenticated 권한 누락으로
--    현상금 제보/조회/지급이 전부 "permission denied"로 막혀 있음
--    => 권한 부여 + RLS 정책 활성화
-- -------------------------------------------------------------
grant select, insert, update, delete on public.bounty_claims
  to anon, authenticated, service_role;

alter table public.bounty_claims enable row level security;

-- 기존 정책 있으면 지우고 다시 생성 (idempotent)
drop policy if exists bounty_claims_select on public.bounty_claims;
drop policy if exists bounty_claims_insert on public.bounty_claims;
drop policy if exists bounty_claims_update on public.bounty_claims;
drop policy if exists bounty_claims_delete on public.bounty_claims;

-- 누구나 도난 자전거 제보 열람 가능 (소유자/관리자 검토용)
create policy bounty_claims_select on public.bounty_claims
  for select using (true);
-- 발견자(비로그인 anon 포함)가 제보 등록 가능
create policy bounty_claims_insert on public.bounty_claims
  for insert with check (true);
-- 소유자/관리자가 상태 변경(지급/거절/이의) 가능
create policy bounty_claims_update on public.bounty_claims
  for update using (true) with check (true);
create policy bounty_claims_delete on public.bounty_claims
  for delete using (true);
-- ⚠ 위 정책은 MVP용으로 개방적입니다. 운영 시에는 소유자 본인/관리자만
--   update/delete 하도록 (auth.uid() 기반) 좁히는 것을 권장합니다.


-- -------------------------------------------------------------
-- 3) bounty_disputes 테이블 (이의 제기 사유 저장용, 현재 미존재)
--    없어도 앱은 동작(상태값 disputed로 처리)하지만, 사유를 남기려면 생성
-- -------------------------------------------------------------
create table if not exists public.bounty_disputes (
  id uuid primary key default gen_random_uuid(),
  claim_id uuid references public.bounty_claims(id) on delete cascade,
  reason text,
  status text default 'open',
  created_at timestamptz default now()
);

grant select, insert, update, delete on public.bounty_disputes
  to anon, authenticated, service_role;

alter table public.bounty_disputes enable row level security;
drop policy if exists bounty_disputes_all on public.bounty_disputes;
create policy bounty_disputes_all on public.bounty_disputes
  for all using (true) with check (true);


-- -------------------------------------------------------------
-- 4) (선택) user_ratings — 현재 앱에서 미사용(별점 기능 제거됨).
--    추후 다시 쓸 경우에만 아래 권한을 부여하세요.
-- -------------------------------------------------------------
-- grant select, insert, update, delete on public.user_ratings
--   to anon, authenticated, service_role;
-- alter table public.user_ratings enable row level security;
-- drop policy if exists user_ratings_all on public.user_ratings;
-- create policy user_ratings_all on public.user_ratings
--   for all using (true) with check (true);
