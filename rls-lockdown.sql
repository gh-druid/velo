-- =============================================================
-- VÉLO — 금융/PII 테이블 RLS 잠금 (orders, partner_orders,
--        referral_withdrawals, referral_logs, partnerships, referrals)
-- 실행: Supabase 대시보드 > SQL Editor (위에서 아래로 전체 실행)
-- idempotent — 여러 번 실행해도 안전.
-- =============================================================
-- 배경: anon(공개 키)에 이 테이블들의 GRANT가 열려 있어, RLS가 없으면
--       누구나 덤프/수정 가능. 아래는 RLS를 켜고 역할별 정책을 부여함.
-- 적용 후 반드시 테스트: 로그인 → 결제, 파트너 신청, 레퍼럴 출금, 관리자 페이지.
-- =============================================================

-- 관리자 판별 헬퍼 (SECURITY DEFINER → users RLS 우회, 정책 재귀 방지)
create or replace function public.is_admin()
returns boolean language sql security definer stable set search_path = public as $$
  select coalesce((select is_admin from public.users where id = auth.uid()), false);
$$;
grant execute on function public.is_admin() to anon, authenticated;

-- 현재 로그인 유저의 이메일 (파트너십 본인 조회용)
-- auth.jwt() ->> 'email' 사용


-- -------------------------------------------------------------
-- orders — 주문/배송지/결제. 본인 또는 관리자만.
--   INSERT: 결제 시 본인(user_id) / UPDATE·DELETE: 관리자(배송처리)
-- -------------------------------------------------------------
alter table public.orders enable row level security;
revoke insert, update, delete on public.orders from anon;
drop policy if exists orders_sel on public.orders;
drop policy if exists orders_ins on public.orders;
drop policy if exists orders_upd on public.orders;
drop policy if exists orders_del on public.orders;
create policy orders_sel on public.orders for select
  using (auth.uid() = user_id or public.is_admin());
create policy orders_ins on public.orders for insert
  with check (auth.uid() = user_id);
create policy orders_upd on public.orders for update
  using (public.is_admin()) with check (public.is_admin());
create policy orders_del on public.orders for delete
  using (public.is_admin());


-- -------------------------------------------------------------
-- partner_orders — 앱에서 미사용. 관리자 전용으로 잠금.
-- -------------------------------------------------------------
alter table public.partner_orders enable row level security;
revoke insert, update, delete, select on public.partner_orders from anon;
drop policy if exists partner_orders_admin on public.partner_orders;
create policy partner_orders_admin on public.partner_orders for all
  using (public.is_admin()) with check (public.is_admin());


-- -------------------------------------------------------------
-- referral_withdrawals — 은행/계좌. 본인(referral 소유자) 또는 관리자.
--   INSERT: 본인 referral 에 대해 / UPDATE: 관리자(입금완료)
-- -------------------------------------------------------------
alter table public.referral_withdrawals enable row level security;
revoke insert, update, delete on public.referral_withdrawals from anon;
drop policy if exists rw_sel on public.referral_withdrawals;
drop policy if exists rw_ins on public.referral_withdrawals;
drop policy if exists rw_upd on public.referral_withdrawals;
drop policy if exists rw_del on public.referral_withdrawals;
create policy rw_sel on public.referral_withdrawals for select using (
  public.is_admin() or exists (
    select 1 from public.referrals r
    where r.id = referral_withdrawals.referral_id and r.user_id = auth.uid()));
create policy rw_ins on public.referral_withdrawals for insert with check (
  exists (select 1 from public.referrals r
          where r.id = referral_withdrawals.referral_id and r.user_id = auth.uid()));
create policy rw_upd on public.referral_withdrawals for update
  using (public.is_admin()) with check (public.is_admin());
create policy rw_del on public.referral_withdrawals for delete
  using (public.is_admin());


-- -------------------------------------------------------------
-- referral_logs — 본인 referral 로그 또는 관리자. (클라이언트는 읽기만)
-- -------------------------------------------------------------
alter table public.referral_logs enable row level security;
revoke insert, update, delete on public.referral_logs from anon;
drop policy if exists rl_sel on public.referral_logs;
create policy rl_sel on public.referral_logs for select using (
  public.is_admin()
  or referred_user_id = auth.uid()
  or exists (select 1 from public.referrals r
             where r.id = referral_logs.referral_id and r.user_id = auth.uid()));


-- -------------------------------------------------------------
-- partnerships — 신청은 누구나(INSERT), 조회는 본인(email/user_id) 또는 관리자,
--   승인/거절(UPDATE)은 관리자.
-- -------------------------------------------------------------
alter table public.partnerships enable row level security;
revoke update, delete on public.partnerships from anon;  -- INSERT(신청)은 유지
drop policy if exists pa_sel on public.partnerships;
drop policy if exists pa_ins on public.partnerships;
drop policy if exists pa_upd on public.partnerships;
drop policy if exists pa_del on public.partnerships;
create policy pa_sel on public.partnerships for select using (
  public.is_admin()
  or user_id = auth.uid()
  or email = (auth.jwt() ->> 'email'));
create policy pa_ins on public.partnerships for insert with check (true);  -- 신청(비로그인 포함)
create policy pa_upd on public.partnerships for update
  using (public.is_admin()) with check (public.is_admin());
create policy pa_del on public.partnerships for delete
  using (public.is_admin());


-- -------------------------------------------------------------
-- referrals — 본인 또는 관리자.
-- -------------------------------------------------------------
alter table public.referrals enable row level security;
revoke insert, update, delete on public.referrals from anon;
drop policy if exists rf_sel on public.referrals;
drop policy if exists rf_ins on public.referrals;
drop policy if exists rf_upd on public.referrals;
drop policy if exists rf_del on public.referrals;
create policy rf_sel on public.referrals for select
  using (auth.uid() = user_id or public.is_admin());
create policy rf_ins on public.referrals for insert
  with check (auth.uid() = user_id);
create policy rf_upd on public.referrals for update
  using (auth.uid() = user_id or public.is_admin())
  with check (auth.uid() = user_id or public.is_admin());
create policy rf_del on public.referrals for delete
  using (public.is_admin());


-- =============================================================
-- 검증: 적용 후 anon 키로 아래가 모두 [] 또는 차단되어야 함
--   curl ".../rest/v1/orders?select=*"               -> [] (본인 것만, 비로그인은 0)
--   curl ".../rest/v1/referral_withdrawals?select=*" -> []
--   curl ".../rest/v1/partnerships?select=*"         -> []
-- 그리고 로그인 상태에서 결제/파트너신청/레퍼럴/관리자 정상 동작 확인.
-- =============================================================
