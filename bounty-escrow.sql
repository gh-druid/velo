-- =============================================================
-- 바운티 에스크로(예치) 상태 관리
-- 실행: Supabase SQL Editor 에 붙여넣고 Run
--
-- bounty_status:
--   'none'     현상금 없음
--   'held'     결제되어 벨로가 안전 보관 중(에스크로)
--   'paid'     제보자에게 지급 완료
--   'refunded' 소유자에게 환급 완료
-- =============================================================

alter table public.bikes add column if not exists bounty_status   text not null default 'none';
alter table public.bikes add column if not exists bounty_held_at   timestamptz;
alter table public.bikes add column if not exists bounty_settled_at timestamptz;

-- 허용 값 제약(이미 있으면 무시)
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'bikes_bounty_status_chk') then
    alter table public.bikes
      add constraint bikes_bounty_status_chk
      check (bounty_status in ('none','held','paid','refunded'));
  end if;
end $$;

-- 기존 데이터 백필: bounty_paid 불리언 → 상태값으로 환산
update public.bikes
   set bounty_status = case
         when bounty_paid is true                 then 'paid'
         when bounty is not null and bounty >= 10000 then 'held'
         else 'none'
       end
 where bounty_status = 'none';

update public.bikes set bounty_held_at = coalesce(bounty_held_at, created_at)
 where bounty_status in ('held','paid');

-- 조회 성능
create index if not exists idx_bikes_bounty_status on public.bikes (bounty_status);

-- 참고: bounty_status 변경은 본인 자전거 UPDATE 정책 범위 안에서 가능.
-- 결제 확정(held)은 confirm-payment Edge Function(service_role)에서 세팅하는 것을 권장.
