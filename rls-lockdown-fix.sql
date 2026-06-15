-- =============================================================
-- VÉLO — RLS 잠금 보정 (FIX) — 기존(레거시) 정책까지 싹 정리 후 재설정
-- 실행: Supabase 대시보드 > SQL Editor (전체 실행)
-- =============================================================
-- 왜 필요한가: 이전 rls-lockdown.sql 은 "내가 만든 이름의 정책"만 drop 했는데,
-- 테이블에 예전부터 있던 다른 이름의 "허용(using true)" 정책이 남아 있었음.
-- RLS 정책은 OR로 합쳐지므로, 남은 허용 정책 때문에 anon이 partnerships PII를
-- 계속 읽을 수 있었고, referrals/withdrawals 는 users를 직접 참조하는 잔존 정책
-- 때문에 401(permission denied for table users)이 났음.
-- => 아래는 대상 6개 테이블의 "모든 정책"을 드롭하고 올바른 정책만 다시 만든다.
-- =============================================================

-- 관리자 판별 헬퍼 (SECURITY DEFINER → users RLS/grant 우회)
create or replace function public.is_admin()
returns boolean language sql security definer stable set search_path = public as $$
  select coalesce((select is_admin from public.users where id = auth.uid()), false);
$$;
grant execute on function public.is_admin() to anon, authenticated;

-- 1) 대상 테이블의 기존 정책 전부 제거 (잔존 정책 청소)
do $$
declare r record; tbl text;
begin
  foreach tbl in array array['orders','partner_orders','referral_withdrawals',
                             'referral_logs','partnerships','referrals']
  loop
    for r in select policyname from pg_policies
             where schemaname = 'public' and tablename = tbl
    loop
      execute format('drop policy %I on public.%I', r.policyname, tbl);
    end loop;
  end loop;
end $$;

-- 2) RLS 활성화 + 불필요한 anon 쓰기 권한 회수
alter table public.orders                enable row level security;
alter table public.partner_orders        enable row level security;
alter table public.referral_withdrawals  enable row level security;
alter table public.referral_logs         enable row level security;
alter table public.partnerships          enable row level security;
alter table public.referrals             enable row level security;

revoke insert, update, delete on public.orders                from anon;
revoke select, insert, update, delete on public.partner_orders from anon;
revoke insert, update, delete on public.referral_withdrawals  from anon;
revoke insert, update, delete on public.referral_logs         from anon;
revoke update, delete on public.partnerships                  from anon; -- INSERT(신청)은 유지
revoke insert, update, delete on public.referrals             from anon;

-- 3) 올바른 정책 재생성
-- orders: 본인 or 관리자
create policy orders_sel on public.orders for select using (auth.uid() = user_id or public.is_admin());
create policy orders_ins on public.orders for insert with check (auth.uid() = user_id);
create policy orders_upd on public.orders for update using (public.is_admin()) with check (public.is_admin());
create policy orders_del on public.orders for delete using (public.is_admin());

-- partner_orders: 관리자 전용 (앱 미사용)
create policy partner_orders_admin on public.partner_orders for all using (public.is_admin()) with check (public.is_admin());

-- referral_withdrawals: 본인(referral 소유자) or 관리자
create policy rw_sel on public.referral_withdrawals for select using (
  public.is_admin() or exists (select 1 from public.referrals r
    where r.id = referral_withdrawals.referral_id and r.user_id = auth.uid()));
create policy rw_ins on public.referral_withdrawals for insert with check (
  exists (select 1 from public.referrals r
    where r.id = referral_withdrawals.referral_id and r.user_id = auth.uid()));
create policy rw_upd on public.referral_withdrawals for update using (public.is_admin()) with check (public.is_admin());
create policy rw_del on public.referral_withdrawals for delete using (public.is_admin());

-- referral_logs: 본인 or 관리자 (읽기)
create policy rl_sel on public.referral_logs for select using (
  public.is_admin() or referred_user_id = auth.uid()
  or exists (select 1 from public.referrals r
    where r.id = referral_logs.referral_id and r.user_id = auth.uid()));

-- partnerships: 신청(INSERT)은 누구나 / 조회는 본인(email·uid) or 관리자 / 변경은 관리자
create policy pa_sel on public.partnerships for select using (
  public.is_admin() or user_id = auth.uid() or email = (auth.jwt() ->> 'email'));
create policy pa_ins on public.partnerships for insert with check (true);
create policy pa_upd on public.partnerships for update using (public.is_admin()) with check (public.is_admin());
create policy pa_del on public.partnerships for delete using (public.is_admin());

-- referrals: 본인 or 관리자
create policy rf_sel on public.referrals for select using (auth.uid() = user_id or public.is_admin());
create policy rf_ins on public.referrals for insert with check (auth.uid() = user_id);
create policy rf_upd on public.referrals for update using (auth.uid() = user_id or public.is_admin()) with check (auth.uid() = user_id or public.is_admin());
create policy rf_del on public.referrals for delete using (public.is_admin());

-- =============================================================
-- 점검: 다른 테이블에도 잔존 허용 정책이 있는지 확인하려면 ↓ 실행 후 검토
-- select tablename, policyname, cmd, roles, qual, with_check
--   from pg_policies where schemaname='public' order by tablename, policyname;
-- =============================================================
