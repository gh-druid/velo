-- =============================================================
-- VÉLO — Storage 정책 & 레이트리밋 (#3)
-- 실행: Supabase 대시보드 > SQL Editor
-- =============================================================
-- 배경: 사진 업로드(bike-photos 버킷)가 anon으로 가능 → 정책 없으면
--       임의 파일 업로드/덮어쓰기/용량 남용 가능.
-- 앱 사용: 자전거 사진 = 로그인 유저(본인 폴더), 제보 사진 = 익명 발견자('claims/').
-- =============================================================

-- 버킷 공개 읽기 (공개 자전거 페이지에서 사진 표시에 필요)
update storage.buckets set public = true where id = 'bike-photos';
-- (선택) 용량/형식 제한 — 대시보드 Storage > 버킷 설정에서:
--   File size limit: 예) 5MB,  Allowed MIME types: image/*
-- SQL로도 가능:
update storage.buckets
   set file_size_limit = 5242880,           -- 5MB
       allowed_mime_types = array['image/jpeg','image/png','image/webp','image/heic']
 where id = 'bike-photos';

-- objects 정책 초기화 후 재생성
do $$
declare r record;
begin
  for r in select policyname from pg_policies where schemaname='storage' and tablename='objects' loop
    execute format('drop policy %I on storage.objects', r.policyname);
  end loop;
end $$;

alter table storage.objects enable row level security;

-- 읽기: bike-photos는 공개
create policy "bikephotos_read" on storage.objects
  for select using (bucket_id = 'bike-photos');

-- 업로드(로그인 유저): 본인 user_id 폴더에만
create policy "bikephotos_user_upload" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'bike-photos' and (storage.foldername(name))[1] = auth.uid()::text);

-- 업로드(익명 발견자): 'claims/' 폴더에만 (현상금 제보 사진)
create policy "bikephotos_claim_upload" on storage.objects
  for insert to anon
  with check (bucket_id = 'bike-photos' and (storage.foldername(name))[1] = 'claims');

-- 수정/삭제: 본인 폴더(또는 관리자). 익명은 불가.
create policy "bikephotos_owner_modify" on storage.objects
  for update to authenticated
  using (bucket_id = 'bike-photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "bikephotos_owner_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'bike-photos' and (storage.foldername(name))[1] = auth.uid()::text);


-- =============================================================
-- 레이트리밋 (어뷰징/스팸/DoS 완화) — 권고
-- =============================================================
-- SQL만으로 완전한 레이트리밋은 어렵습니다. 권장 우선순위:
--
-- 1) 에지(권장): Cloudflare/Vercel 앞단에서 IP·경로별 rate limit.
--    특히 /rest/v1/scan_logs, /bounty_claims, /partnerships POST.
--
-- 2) Supabase Auth 기본 레이트리밋 사용 (대시보드 Auth > Rate Limits):
--    회원가입/로그인/OTP 횟수 제한 활성화.
--
-- 3) DB 트리거로 시간당 insert 횟수 제한 (간이) — 예: partnerships
--    (같은 이메일이 1시간 내 5건 이상 신청 차단). 필요 시 주석 해제:
--
-- create or replace function public.limit_partnership_spam()
-- returns trigger language plpgsql as $$
-- begin
--   if (select count(*) from public.partnerships
--        where email = new.email and created_at > now() - interval '1 hour') >= 5 then
--     raise exception '신청이 너무 잦습니다. 잠시 후 다시 시도해주세요.';
--   end if;
--   return new;
-- end $$;
-- create trigger trg_partnership_spam before insert on public.partnerships
--   for each row execute function public.limit_partnership_spam();
--
-- scan_logs/bounty_claims도 동일 패턴(ip_hash 또는 bike_id 기준) 적용 가능.
-- =============================================================
