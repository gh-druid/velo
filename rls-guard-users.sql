-- =============================================================
-- VÉLO — 권한 상승 차단 가드 (CRITICAL)
-- 실행: Supabase 대시보드 > SQL Editor
-- =============================================================
-- 문제: users UPDATE 정책이 "본인 행"을 허용하는데, RLS는 컬럼 단위
--       제한을 못 하므로 일반 유저가 본인 행의 is_admin=true 로
--       스스로 관리자가 될 수 있었음 (펜테스트로 확인됨).
-- 해결: BEFORE UPDATE 트리거로 "비관리자"는 권한/정지/경고/평생무료
--       컬럼을 못 바꾸게 막음(변경 시도 시 옛값으로 되돌림, 에러 없음).
--       name/phone 등 일반 수정은 그대로 허용 → 앱 동작 영향 없음.
-- =============================================================

create or replace function public.is_admin()
returns boolean language sql security definer stable set search_path = public as $$
  select coalesce((select is_admin from public.users where id = auth.uid()), false);
$$;
grant execute on function public.is_admin() to anon, authenticated;

create or replace function public.guard_users_privileged()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    new.is_admin      := old.is_admin;
    new.is_suspended  := old.is_suspended;
    new.warning_count := old.warning_count;
    new.lifetime_free := old.lifetime_free;
    -- plan 은 현재 앱이 클라이언트에서 구독 처리 시 변경하므로 막지 않음.
    -- ⚠ 단, 이 때문에 유저가 스스로 plan='lifetime' 설정 가능(구독 우회).
    --    근본 해결은 결제 웹훅 기반 서버 검증. (아래 보고서 참고)
  end if;
  return new;
end $$;

drop trigger if exists trg_guard_users_privileged on public.users;
create trigger trg_guard_users_privileged
  before update on public.users
  for each row execute function public.guard_users_privileged();
