-- =============================================================
-- VÉLO — users 이메일/민감컬럼 보호 (#10)
-- 실행: Supabase 대시보드 > SQL Editor
-- =============================================================
-- 문제: 로그인 유저(누구나 가입)가 users_sel(using true)+전체 컬럼 권한으로
--       전 유저의 email/phone 을 읽을 수 있었음(펜테스트 확인).
-- 해결: email/ip/user_agent 컬럼을 anon·authenticated 에게서 회수.
--       (이름/전화는 공개 자전거 페이지 소유자 표시에 필요하므로 유지)
--       관리자는 아래 SECURITY DEFINER RPC 로만 이메일 조회.
-- ⚠ 앱 코드도 함께 수정됨(getUserProfile/대시보드/관리자) — 같이 배포 필요.
-- =============================================================

revoke select on public.users from anon, authenticated;
grant select (id, name, phone, plan, created_at, is_admin, lifetime_free,
              referral_code, avg_rating, warning_count, is_suspended)
  on public.users to anon, authenticated;
-- (email, ip, user_agent 는 제외 → 일반 유저가 못 읽음)

-- 관리자 전용: 전체 유저(이메일 포함) 조회
create or replace function public.admin_list_users()
returns setof public.users language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  return query select * from public.users order by created_at desc;
end $$;
revoke execute on function public.admin_list_users() from anon;
grant execute on function public.admin_list_users() to authenticated;

-- 관리자 전용: 이메일로 유저 찾기(평생무료 부여용)
create or replace function public.admin_find_user_by_email(p_email text)
returns public.users language plpgsql security definer set search_path = public as $$
declare u public.users;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  select * into u from public.users where email = p_email;
  return u;
end $$;
revoke execute on function public.admin_find_user_by_email(text) from anon;
grant execute on function public.admin_find_user_by_email(text) to authenticated;
