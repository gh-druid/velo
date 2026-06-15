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

-- =============================================================
-- ⚠ storage.objects 정책은 SQL로 못 만듭니다.
--   SQL 에디터(postgres)는 storage.objects 소유자가 아니라서
--   "ERROR: 42501: must be owner of table objects" 가 납니다.
--   (RLS는 storage.objects에 이미 기본 활성화되어 있음)
--
--   => 아래 4개 정책은 대시보드 UI로 생성하세요:
--      Storage > 버킷(bike-photos) > Policies > New policy > "custom"
--   각 정책의 설정값(Allowed operation / Target roles / USING·WITH CHECK):
--
--   [1] 읽기 공개      SELECT / anon,authenticated
--        USING:      bucket_id = 'bike-photos'
--
--   [2] 유저 업로드     INSERT / authenticated
--        WITH CHECK: bucket_id = 'bike-photos'
--                    and (storage.foldername(name))[1] = auth.uid()::text
--
--   [3] 익명 제보 업로드 INSERT / anon
--        WITH CHECK: bucket_id = 'bike-photos'
--                    and (storage.foldername(name))[1] = 'claims'
--
--   [4] 소유자 수정/삭제 UPDATE,DELETE / authenticated
--        USING:      bucket_id = 'bike-photos'
--                    and (storage.foldername(name))[1] = auth.uid()::text
--
--   참고: 빠르게 하려면 UI의 "Get started quickly" 템플릿 중
--   "Give users access to own folder" 를 쓰고 표현식만 위로 바꿔도 됩니다.
-- =============================================================


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
