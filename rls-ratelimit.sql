-- =============================================================
-- VÉLO — 레이트리밋 트리거 (insert 스팸/어뷰징 완화)
-- 실행: Supabase 대시보드 > SQL Editor (전체 실행). idempotent.
-- =============================================================
-- 설계:
--  • 모든 함수 SECURITY DEFINER → RLS 우회하여 "전체" 최근 행을 카운트
--    (invoker(anon)로 세면 RLS에 가려 카운트가 0이 되어 무력화됨)
--  • 사용자 대면 흐름(신청/제보/출금/결제): 초과 시 RAISE EXCEPTION → 에러 안내
--  • 백그라운드 흐름(스캔로그/알림): 초과 시 RETURN NULL → 조용히 건너뜀
--    (페이지/스캔 동작을 막지 않음)
--  • 한도는 보수적으로 넉넉하게 잡음. 운영 보며 조절하세요.
-- =============================================================

-- ── partnerships: 같은 이메일 1시간 5건 초과 차단 ──────────────
create or replace function public.rl_partnerships()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.email is not null and (
    select count(*) from public.partnerships
    where email = new.email and created_at > now() - interval '1 hour'
  ) >= 5 then
    raise exception '파트너 신청이 너무 잦습니다. 잠시 후 다시 시도해주세요.';
  end if;
  return new;
end $$;
drop trigger if exists trg_rl_partnerships on public.partnerships;
create trigger trg_rl_partnerships before insert on public.partnerships
  for each row execute function public.rl_partnerships();

-- ── bounty_claims: 한 자전거에 1시간 20건 초과 제보 차단 ────────
create or replace function public.rl_bounty_claims()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.bike_id is not null and (
    select count(*) from public.bounty_claims
    where bike_id = new.bike_id and created_at > now() - interval '1 hour'
  ) >= 20 then
    raise exception '제보가 너무 많습니다. 잠시 후 다시 시도해주세요.';
  end if;
  return new;
end $$;
drop trigger if exists trg_rl_bounty_claims on public.bounty_claims;
create trigger trg_rl_bounty_claims before insert on public.bounty_claims
  for each row execute function public.rl_bounty_claims();

-- ── referral_withdrawals: 같은 referral 1시간 3건 초과 차단 ─────
create or replace function public.rl_referral_withdrawals()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.referral_id is not null and (
    select count(*) from public.referral_withdrawals
    where referral_id = new.referral_id and created_at > now() - interval '1 hour'
  ) >= 3 then
    raise exception '출금 신청이 너무 잦습니다. 잠시 후 다시 시도해주세요.';
  end if;
  return new;
end $$;
drop trigger if exists trg_rl_referral_withdrawals on public.referral_withdrawals;
create trigger trg_rl_referral_withdrawals before insert on public.referral_withdrawals
  for each row execute function public.rl_referral_withdrawals();

-- ── orders: 같은 유저 1시간 10건 초과 차단 ─────────────────────
create or replace function public.rl_orders()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.user_id is not null and (
    select count(*) from public.orders
    where user_id = new.user_id and created_at > now() - interval '1 hour'
  ) >= 10 then
    raise exception '주문이 너무 잦습니다. 잠시 후 다시 시도해주세요.';
  end if;
  return new;
end $$;
drop trigger if exists trg_rl_orders on public.orders;
create trigger trg_rl_orders before insert on public.orders
  for each row execute function public.rl_orders();

-- ── notifications: 같은 수신자 1시간 50건 초과 시 조용히 건너뜀 ──
--   (스캔 알림 등 백그라운드 생성이라 에러 대신 무시)
create or replace function public.rl_notifications()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.user_id is not null and (
    select count(*) from public.notifications
    where user_id = new.user_id and created_at > now() - interval '1 hour'
  ) >= 50 then
    return null;  -- 한도 초과 → 알림 생성 생략(에러 없음)
  end if;
  return new;
end $$;
drop trigger if exists trg_rl_notifications on public.notifications;
create trigger trg_rl_notifications before insert on public.notifications
  for each row execute function public.rl_notifications();

-- ── scan_logs: 같은 ip_hash 1분 60건 초과 시 조용히 건너뜀 ──────
--   (스캔 페이지 로딩을 막으면 안 되므로 에러 대신 기록만 생략)
create or replace function public.rl_scan_logs()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.ip_hash is not null and (
    select count(*) from public.scan_logs
    where ip_hash = new.ip_hash and scanned_at > now() - interval '1 minute'
  ) >= 60 then
    return null;  -- 한도 초과 → 로그 생략(에러 없음)
  end if;
  return new;
end $$;
drop trigger if exists trg_rl_scan_logs on public.scan_logs;
create trigger trg_rl_scan_logs before insert on public.scan_logs
  for each row execute function public.rl_scan_logs();

-- =============================================================
-- 한도 조절: 위 숫자(5/20/3/10/50/60)와 간격(interval)만 바꾸면 됩니다.
-- 제거: drop trigger trg_rl_<table> on public.<table>;
-- =============================================================
