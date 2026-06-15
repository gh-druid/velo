// =============================================================
// velo-config.js — 공개 설정 (한 곳에서 관리)
// =============================================================
// ⚠️ 여기 값들은 브라우저로 전송되는 "공개" 값입니다.
//   - SUPABASE_URL: 프로젝트 주소(공개)
//   - SUPABASE_PUBLISHABLE_KEY: 브라우저용 공개 키.
//     데이터 보호는 이 키가 아니라 RLS(행 보안 정책)가 담당합니다.
//
// ❌ service_role / secret 키는 절대 이 파일(또는 어떤 클라이언트 파일)에
//    넣지 마세요. 서버 전용입니다.
//
// 🔁 키 교체(rotate) 시 이 파일 한 곳만 바꾸면 모든 페이지에 반영됩니다.
// =============================================================

export const SUPABASE_URL = 'https://kfeksnbxucmkilxrbhth.supabase.co'
export const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_2uHPO55MzcH9WY1sxPUOpA_cmjop6ai'
