-- =============================================================
-- VÉLO — 나머지 테이블 RLS (#2)
-- 실행: Supabase 대시보드 > SQL Editor (전체 실행)
-- =============================================================
-- 대상: bikes, parts, notifications, transfers, subscriptions,
--       discount_codes, discount_code_uses, scan_logs,
--       bounty_claims, bounty_disputes, user_ratings
-- 방식: 기존 정책 전부 제거(잔존 허용정책 청소) 후 올바른 정책만 생성.
-- ⚠ 적용 후 테스트: 공개 스캔 페이지, 자전거 등록, 도난신고, 양도,
--   결제, 할인코드, 현상금 제보/이의, 알림.
-- =============================================================

create or replace function public.is_admin()
returns boolean language sql security definer stable set search_path = public as $$
  select coalesce((select is_admin from public.users where id = auth.uid()), false);
$$;
grant execute on function public.is_admin() to anon, authenticated;

-- bike 소유자 판별 헬퍼
create or replace function public.owns_bike(bid uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists(select 1 from public.bikes b where b.id = bid and b.user_id = auth.uid());
$$;
grant execute on function public.owns_bike(uuid) to anon, authenticated;

-- 1) 기존 정책 전부 제거
do $$
declare r record; tbl text;
begin
  foreach tbl in array array['bikes','parts','notifications','transfers','subscriptions',
                             'discount_codes','discount_code_uses','scan_logs',
                             'bounty_claims','bounty_disputes','user_ratings']
  loop
    if exists (select 1 from information_schema.tables where table_schema='public' and table_name=tbl) then
      for r in select policyname from pg_policies where schemaname='public' and tablename=tbl loop
        execute format('drop policy %I on public.%I', r.policyname, tbl);
      end loop;
      execute format('alter table public.%I enable row level security', tbl);
    end if;
  end loop;
end $$;

-- 2) 정책 생성

-- bikes: 공개 조회(스캔/레지스트리), 본인만 등록/수정/삭제
create policy bikes_sel on public.bikes for select using (true);
create policy bikes_ins on public.bikes for insert with check (auth.uid() = user_id);
create policy bikes_upd on public.bikes for update using (auth.uid() = user_id or public.is_admin()) with check (auth.uid() = user_id or public.is_admin());
create policy bikes_del on public.bikes for delete using (auth.uid() = user_id or public.is_admin());

-- parts: 공개 조회(스캔 페이지), 쓰기는 자전거 소유자/관리자
--  ⚠ 공개 페이지의 "분실 신고"는 이제 소유자 로그인 상태에서만 동작합니다.
create policy parts_sel on public.parts for select using (true);
create policy parts_ins on public.parts for insert with check (public.owns_bike(bike_id) or public.is_admin());
create policy parts_upd on public.parts for update using (public.owns_bike(bike_id) or public.is_admin()) with check (public.owns_bike(bike_id) or public.is_admin());
create policy parts_del on public.parts for delete using (public.owns_bike(bike_id) or public.is_admin());

-- notifications: 본인 알림만 조회/수정. INSERT는 스캔 알림 때문에 개방(누구나 생성).
--  ⚠ 개방형 insert는 알림 스팸 여지가 있음(서버 트리거로 옮기는 것을 권장).
create policy notif_sel on public.notifications for select using (auth.uid() = user_id or public.is_admin());
create policy notif_ins on public.notifications for insert with check (true);
create policy notif_upd on public.notifications for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy notif_del on public.notifications for delete using (auth.uid() = user_id or public.is_admin());

-- transfers: 소유 이력 표시 위해 조회 허용. 생성은 양도자, 수정은 당사자/관리자.
create policy tr_sel on public.transfers for select using (true);
create policy tr_ins on public.transfers for insert with check (auth.uid() = from_user_id);
create policy tr_upd on public.transfers for update using (auth.uid() = from_user_id or auth.uid() = to_user_id or public.is_admin()) with check (true);
create policy tr_del on public.transfers for delete using (public.is_admin());

-- subscriptions: 본인/관리자
create policy sub_sel on public.subscriptions for select using (auth.uid() = user_id or public.is_admin());
create policy sub_ins on public.subscriptions for insert with check (auth.uid() = user_id);
create policy sub_upd on public.subscriptions for update using (public.is_admin()) with check (public.is_admin());
create policy sub_del on public.subscriptions for delete using (public.is_admin());

-- discount_codes: 조회는 공개(코드 검증), 쓰기는 관리자만
create policy dc_sel on public.discount_codes for select using (true);
create policy dc_ins on public.discount_codes for insert with check (public.is_admin());
create policy dc_upd on public.discount_codes for update using (public.is_admin()) with check (public.is_admin());
create policy dc_del on public.discount_codes for delete using (public.is_admin());

-- discount_code_uses: 본인/관리자
create policy dcu_sel on public.discount_code_uses for select using (auth.uid() = user_id or public.is_admin());
create policy dcu_ins on public.discount_code_uses for insert with check (auth.uid() = user_id);

-- scan_logs: 누구나 기록(insert), 조회는 관리자만
create policy scan_ins on public.scan_logs for insert with check (true);
create policy scan_sel on public.scan_logs for select using (public.is_admin());

-- bounty_claims: 발견자(익명) 제보 insert. 조회/지급은 소유자/관리자.
--  익명 발견자는 본인 제보 "상태"만 봐야 하므로 컬럼권한(rls-hardening.sql C)과 병행.
--  익명 update는 '이의 제기(disputed)'로만 한정, 지급/거절은 소유자·관리자.
create policy bc_sel on public.bounty_claims for select using (true);
create policy bc_ins on public.bounty_claims for insert with check (true);
create policy bc_upd_anon on public.bounty_claims for update to anon using (true) with check (status = 'disputed');
create policy bc_upd_auth on public.bounty_claims for update to authenticated using (public.owns_bike(bike_id) or public.is_admin()) with check (public.owns_bike(bike_id) or public.is_admin());
create policy bc_del on public.bounty_claims for delete using (public.owns_bike(bike_id) or public.is_admin());

-- bounty_disputes: 누구나 제기(insert), 조회/처리는 관리자
create policy bd_ins on public.bounty_disputes for insert with check (true);
create policy bd_sel on public.bounty_disputes for select using (public.is_admin());
create policy bd_upd on public.bounty_disputes for update using (public.is_admin()) with check (public.is_admin());

-- user_ratings: 현재 앱 미사용 → 관리자 전용으로 잠금
create policy ur_admin on public.user_ratings for all using (public.is_admin()) with check (public.is_admin());

-- 불필요한 anon 쓰기 권한 회수(정책으로도 막히지만 이중 방어)
revoke insert, update, delete on public.discount_codes from anon;
revoke insert, update, delete on public.subscriptions from anon;
revoke update, delete on public.scan_logs from anon;
revoke select, insert, update, delete on public.user_ratings from anon;
