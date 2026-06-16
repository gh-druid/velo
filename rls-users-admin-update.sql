-- =============================================================
-- VÉLO — 관리자의 유저 수정 허용 (정지/경고/평생무료 부여)
-- 실행: Supabase 대시보드 > SQL Editor
-- =============================================================
-- 문제: users UPDATE 정책이 "본인 행(auth.uid()=id)"만 허용이라,
--       관리자가 다른 유저를 정지/경고/평생무료 부여할 수 없었음
--       (펜테스트로 확인: admin이 타 유저 row 수정 시 0행 반영).
-- 해결: is_admin() 인 경우 모든 유저 row 수정 허용 정책 추가.
--       (기존 self-only 정책과 OR 결합 / 컬럼 보호는 guard_users_privileged 트리거가 담당)
-- =============================================================

drop policy if exists users_admin_update on public.users;
create policy users_admin_update on public.users
  for update using (public.is_admin()) with check (public.is_admin());

-- 참고:
--  - 일반 유저: 본인 행만 수정 + 트리거가 is_admin/is_suspended/warning_count/
--    lifetime_free(/plan) 변경을 되돌림.
--  - 관리자: 모든 유저 수정 가능(트리거는 is_admin()=true라 통과).
