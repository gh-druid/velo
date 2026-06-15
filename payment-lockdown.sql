-- =============================================================
-- VÉLO — 결제 우회 차단 (서버만 권한 부여 가능하게)
-- 실행 순서 ⚠: confirm-payment Edge Function 배포 + 클라이언트 수정 후 실행!
--   (먼저 실행하면 구독/주문 부여 경로가 막혀 정상 결제도 권한이 안 들어감)
-- =============================================================
-- 배경: 클라이언트가 users.plan / subscriptions / orders 를 직접 써서
--       무결제로 구독을 받을 수 있었음(펜테스트로 확인).
-- 해결: 이 3가지 쓰기를 일반 유저에게서 회수 → 오직 Edge Function의
--       service_role 만 권한 부여. (service_role 은 RLS/가드 우회)
-- =============================================================

-- 1) plan 자가변경 차단: 가드 트리거가 plan 도 되돌림.
--    단 auth.uid() 가 NULL 인 service_role(=서버)은 통과시켜 정상 부여 허용.
create or replace function public.guard_users_privileged()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is not null and not public.is_admin() then
    new.is_admin      := old.is_admin;
    new.is_suspended  := old.is_suspended;
    new.warning_count := old.warning_count;
    new.lifetime_free := old.lifetime_free;
    new.plan          := old.plan;          -- ★ 추가: 본인이 plan 못 바꿈
  end if;
  return new;
end $$;
-- 트리거(trg_guard_users_privileged)는 이미 존재 → 함수만 교체됨.

-- 2) subscriptions / orders 는 서버(Edge Function)만 생성/수정
revoke insert, update, delete on public.subscriptions from anon, authenticated;
revoke insert, update, delete on public.orders        from anon, authenticated;
-- 조회(select)는 기존 정책 유지: 본인 것 + 관리자만.

-- 참고: service_role 은 모든 권한 + RLS 우회라 Edge Function 에서 정상 동작.
-- =============================================================
