// =============================================
// velo-supabase.js
// 모든 페이지에서 이 파일을 import해서 사용
// =============================================

import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm'
import { SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from '/velo-config.js'

export const supabase = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY)

// =============================================
// XSS 방어 — innerHTML 템플릿에 들어가는 사용자/DB 문자열은 반드시 이걸로 감쌀 것
// HTML 텍스트/속성 컨텍스트용 이스케이프
// =============================================
export function escapeHtml(v) {
  if (v === null || v === undefined) return ''
  return String(v).replace(/[&<>"']/g, c => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ))
}

// =============================================
// AUTH (인증)
// =============================================

// 회원가입
export async function signUp({ email, password, name, phone, userAgent }) {
  // 1단계: auth에만 가입
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
  })
  if (error) throw error

  // 2단계: users 테이블에 직접 저장
  if (data.user) {
    const { error: insertError } = await supabase.from('users').insert({
      id: data.user.id,
      name: name || '',
      phone: phone || '',
      email,
      user_agent: userAgent || navigator.userAgent,
    })
    if (insertError) {
      console.error('users 저장 오류:', insertError)
    }
  }
  return data
}

// 로그인
export async function signIn({ email, password }) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password })
  if (error) throw error
  return data
}

// 로그아웃
export async function signOut() {
  const { error } = await supabase.auth.signOut()
  if (error) throw error
}

// 현재 유저 가져오기
export async function getUser() {
  const { data: { user } } = await supabase.auth.getUser()
  return user
}

// 현재 유저 프로필 가져오기
// 주의: users.email 컬럼은 anon/authenticated 가 읽을 수 없음(이메일 보호).
//       본인 이메일은 auth 세션에서 가져와 합쳐준다.
export async function getUserProfile() {
  const user = await getUser()
  if (!user) return null
  const { data, error } = await supabase
    .from('users')
    .select('id, name, phone, plan, created_at, is_admin, lifetime_free, referral_code, avg_rating, warning_count, is_suspended')
    .eq('id', user.id)
    .single()
  if (error) throw error
  return { ...data, email: user.email }
}

// 프로필 수정
export async function updateProfile({ name, phone }) {
  const user = await getUser()
  if (!user) throw new Error('로그인이 필요합니다')
  const { error } = await supabase
    .from('users')
    .update({ name, phone })
    .eq('id', user.id)
  if (error) throw error
}

// =============================================
// BIKES (자전거)
// =============================================

// 내 자전거 목록
export async function getMyBikes() {
  const user = await getUser()
  if (!user) throw new Error('로그인이 필요합니다')
  const { data, error } = await supabase
    .from('bikes')
    .select('*, parts(*)')
    .eq('user_id', user.id)
    .order('created_at', { ascending: false })
  if (error) throw error
  return data || []
}

// 차대번호로 자전거 조회 (NFC 스캔용 — 비로그인 가능)
export async function getBikeBySerial(serial) {
  const { data, error } = await supabase
    .from('bikes')
    .select(`
      *,
      parts(*),
      users(name, phone)
    `)
    .eq('serial', serial.toUpperCase())
    .single()
  if (error) throw error

  // 스캔 로그 기록
  if (data) {
    await supabase.from('scan_logs').insert({
      bike_id: data.id,
      ip_hash: await hashString(navigator.userAgent),
      user_agent: navigator.userAgent,
    })
  }
  return data
}

// NFC UID로 자전거 조회
export async function getBikeByNfcUid(nfcUid) {
  const { data, error } = await supabase
    .from('bikes')
    .select(`
      *,
      parts(*),
      users(name, phone)
    `)
    .eq('nfc_uid', nfcUid)
    .single()
  if (error) throw error
  return data
}

// 자전거 등록
export async function registerBike({ serial, brand, model, year, color, memo, partnerCode, photos, bounty }) {
  const user = await getUser()
  if (!user) throw new Error('로그인이 필요합니다')

  const { data, error } = await supabase
    .from('bikes')
    .insert({
      user_id: user.id,
      serial: serial ? serial.toUpperCase() : null,
      brand,
      model,
      year,
      color,
      memo,
      photos,
      status: 'normal',
      partner_code: partnerCode || null,
      bounty: bounty || null,
      bounty_paid: false
    })
    .select()
    .single()
  if (error) throw error
  return data
}

// 부품 추가
export async function addPart(bikeId, { type, name, serial }) {
  const { data, error } = await supabase
    .from('parts')
    .insert({ bike_id: bikeId, type, name, serial })
    .select()
    .single()
  if (error) throw error
  return data
}

// 부품 삭제
export async function deletePart(partId) {
  const { error } = await supabase
    .from('parts')
    .delete()
    .eq('id', partId)
  if (error) throw error
}

// 도난 신고
export async function reportStolen(bikeId) {
  const user = await getUser()
  if (!user) throw new Error('로그인이 필요합니다')

  // 구독 확인
  const profile = await getUserProfile()
  if (profile.plan === 'free') throw new Error('도난 신고는 구독자만 가능합니다')

  const { error } = await supabase
    .from('bikes')
    .update({ status: 'stolen', stolen_at: new Date().toISOString() })
    .eq('id', bikeId)
    .eq('user_id', user.id)
  if (error) throw error
}

// 도난 신고 취소
export async function cancelStolen(bikeId) {
  const user = await getUser()
  if (!user) throw new Error('로그인이 필요합니다')
  const { error } = await supabase
    .from('bikes')
    .update({ status: 'normal', stolen_at: null })
    .eq('id', bikeId)
    .eq('user_id', user.id)
  if (error) throw error
}

// 전체 등록 현황 (랜딩 페이지용 — 개인정보 마스킹)
export async function getPublicRegistry(limit = 50) {
  const { data, error } = await supabase
    .from('bikes')
    .select('id, brand, model, created_at, users(name)')
    .order('created_at', { ascending: false })
    .limit(limit)
  if (error) throw error

  // 이름 마스킹: 홍길동 → 홍*동
  return data.map(b => ({
    ...b,
    ownerName: maskName(b.users?.name || '')
  }))
}

// =============================================
// TRANSFERS (양도)
// =============================================

// 양도 코드 생성
export async function createTransferCode(bikeId) {
  const user = await getUser()
  if (!user) throw new Error('로그인이 필요합니다')

  // 도난 상태 확인
  const { data: bike } = await supabase
    .from('bikes')
    .select('status')
    .eq('id', bikeId)
    .single()
  if (bike.status === 'stolen') throw new Error('도난 신고 상태에서는 양도가 불가합니다')

  // 영문+숫자 6자리 코드 생성
  const code = generateCode()
  const expiresAt = new Date(Date.now() + 60 * 60 * 1000) // 1시간

  const { data, error } = await supabase
    .from('transfers')
    .insert({
      bike_id: bikeId,
      from_user_id: user.id,
      code,
      code_expires_at: expiresAt.toISOString()
    })
    .select()
    .single()
  if (error) throw error
  return data
}

// 양도 코드 확인
export async function verifyTransferCode(code) {
  const { data, error } = await supabase
    .from('transfers')
    .select('*, bikes(*, users(name))')
    .eq('code', code.toUpperCase())
    .eq('status', 'pending')
    .single()

  if (error || !data) throw new Error('유효하지 않은 코드입니다')

  // 만료 확인
  if (new Date(data.code_expires_at) < new Date()) {
    await supabase.from('transfers').update({ status: 'expired' }).eq('id', data.id)
    throw new Error('만료된 코드입니다')
  }

  // 시도 횟수 증가
  await supabase
    .from('transfers')
    .update({ attempts: data.attempts + 1 })
    .eq('id', data.id)

  // 5회 초과 시 만료
  if (data.attempts >= 5) {
    await supabase.from('transfers').update({ status: 'expired' }).eq('id', data.id)
    throw new Error('시도 횟수 초과로 코드가 만료되었습니다')
  }

  return data
}

// 양도 수락
export async function acceptTransfer(transferId) {
  const user = await getUser()
  if (!user) throw new Error('로그인이 필요합니다')

  const { data: transfer } = await supabase
    .from('transfers')
    .select('*')
    .eq('id', transferId)
    .single()

  if (!transfer) throw new Error('양도 정보를 찾을 수 없습니다')

  // 소유자 변경
  await supabase
    .from('bikes')
    .update({ user_id: user.id })
    .eq('id', transfer.bike_id)

  // 양도 완료 처리
  await supabase
    .from('transfers')
    .update({
      to_user_id: user.id,
      status: 'completed',
      completed_at: new Date().toISOString()
    })
    .eq('id', transferId)
}

// =============================================
// SUBSCRIPTIONS (구독)
// =============================================

// 구독 시작
export async function startSubscription(plan) {
  const user = await getUser()
  if (!user) throw new Error('로그인이 필요합니다')

  const expiresAt = plan === 'yearly'
    ? new Date(Date.now() + 365 * 24 * 60 * 60 * 1000)
    : new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)

  await supabase.from('subscriptions').insert({
    user_id: user.id,
    plan,
    expires_at: expiresAt.toISOString()
  })

  await supabase.from('users').update({ plan }).eq('id', user.id)
}

// =============================================
// BOUNTY (현상금) — 도난 자전거 제보 & 지급
// =============================================

// 제보 사진 업로드 (발견자 — 비로그인 가능)
export async function uploadClaimPhotos(files, bikeId) {
  const urls = []
  for (const file of files) {
    const ext = (file.name.split('.').pop() || 'jpg')
    const path = `claims/${bikeId}_${Date.now()}_${Math.random().toString(36).slice(2, 7)}.${ext}`
    const { error } = await supabase.storage.from('bike-photos').upload(path, file, { upsert: true })
    if (error) throw error
    const { data: { publicUrl } } = supabase.storage.from('bike-photos').getPublicUrl(path)
    urls.push(publicUrl)
  }
  return urls
}

// 제보 등록 (발견자 — 비로그인 가능)
export async function submitBountyClaim({ bikeId, finderName, finderPhone, finderBank, finderAccount, location, locationDetail, photos, foundAt }) {
  const { data, error } = await supabase
    .from('bounty_claims')
    .insert({
      bike_id: bikeId,
      finder_name: finderName,
      finder_phone: finderPhone,
      finder_bank: finderBank,
      finder_account: finderAccount,
      location,
      location_detail: locationDetail || null,
      photos: photos || [],
      found_at: foundAt || new Date().toISOString(),
      status: 'pending'
    })
    .select()
    .single()
  if (error) throw error
  return data
}

// 특정 자전거의 제보 목록 (소유자용)
export async function getBountyClaims(bikeId) {
  const { data, error } = await supabase
    .from('bounty_claims')
    .select('*')
    .eq('bike_id', bikeId)
    .order('found_at', { ascending: false })
  if (error) throw error
  return data || []
}

// 단일 제보 조회 (발견자가 자기 제보 상태 확인용)
export async function getBountyClaim(claimId) {
  const { data, error } = await supabase
    .from('bounty_claims')
    .select('*')
    .eq('id', claimId)
    .single()
  if (error) throw error
  return data
}

// 바운티 N분할 지급 (소유자) — 선택한 제보자들에게 균등 분할
export async function payBounty(bikeId, claimIds) {
  const user = await getUser()
  if (!user) throw new Error('로그인이 필요합니다')
  if (!claimIds || !claimIds.length) throw new Error('지급할 제보자를 선택해주세요')

  const { data: bike } = await supabase
    .from('bikes')
    .select('id, user_id, bounty')
    .eq('id', bikeId)
    .single()
  if (!bike) throw new Error('자전거를 찾을 수 없습니다')
  if (bike.user_id !== user.id) throw new Error('본인 자전거만 지급할 수 있습니다')

  const total = bike.bounty || 0
  const share = claimIds.length ? Math.floor(total / claimIds.length) : 0

  // 선택된 제보 → 지급 완료
  const { error: e1 } = await supabase
    .from('bounty_claims')
    .update({ status: 'paid' })
    .in('id', claimIds)
  if (e1) throw e1

  // 자전거 바운티 지급 처리
  await supabase.from('bikes').update({ bounty_paid: true }).eq('id', bikeId)

  return { share, count: claimIds.length, total }
}

// 제보 거절 (소유자/관리자)
export async function rejectClaim(claimId) {
  const { error } = await supabase
    .from('bounty_claims')
    .update({ status: 'rejected' })
    .eq('id', claimId)
  if (error) throw error
}

// 이의 제기 (발견자) — 억울한 경우 벨로에 이의 제기
export async function submitDispute(claimId, reason) {
  const { error } = await supabase
    .from('bounty_claims')
    .update({ status: 'disputed' })
    .eq('id', claimId)
  if (error) throw error
  // 사유는 별도 테이블에 best-effort 저장 (테이블 없어도 무방)
  try {
    await supabase.from('bounty_disputes').insert({ claim_id: claimId, reason: reason || null, status: 'open' })
  } catch (e) { /* noop */ }
  return true
}

// =============================================
// BOUNTY — 관리자 (admin)
// =============================================

// 전체 제보 목록 (admin)
export async function getAllBountyClaims() {
  const { data, error } = await supabase
    .from('bounty_claims')
    .select('*')
    .order('found_at', { ascending: false })
  if (error) throw error
  return data || []
}

// 이의 제기 목록 (admin) — disputed 상태 제보
export async function getDisputedClaims() {
  const { data, error } = await supabase
    .from('bounty_claims')
    .select('*')
    .eq('status', 'disputed')
    .order('found_at', { ascending: false })
  if (error) throw error
  return data || []
}

// 제보 상태 변경 (admin) — 승인(paid)/거절(rejected)/대기(pending)
export async function adminUpdateClaimStatus(claimId, status) {
  const { error } = await supabase
    .from('bounty_claims')
    .update({ status })
    .eq('id', claimId)
  if (error) throw error
}

// 바운티 금액 조정 (admin)
export async function adminAdjustBounty(bikeId, amount) {
  const { error } = await supabase
    .from('bikes')
    .update({ bounty: amount })
    .eq('id', bikeId)
  if (error) throw error
}

// 계정 경고 (admin) — 경고 3회면 자동 정지
export async function adminWarnUser(userId) {
  const { data: u } = await supabase.from('users').select('warning_count').eq('id', userId).single()
  const warningCount = (u?.warning_count || 0) + 1
  const updates = { warning_count: warningCount }
  if (warningCount >= 3) updates.is_suspended = true
  const { error } = await supabase.from('users').update(updates).eq('id', userId)
  if (error) throw error
  return { warningCount, suspended: warningCount >= 3 }
}

// 계정 정지/해제 (admin)
export async function adminSetSuspended(userId, suspended) {
  const { error } = await supabase.from('users').update({ is_suspended: !!suspended }).eq('id', userId)
  if (error) throw error
}

// =============================================
// DISCOUNT CODES (할인코드)
// =============================================

// 할인코드 검증
export async function validateDiscountCode(code) {
  const { data, error } = await supabase
    .from('discount_codes')
    .select('*')
    .eq('code', code.toUpperCase())
    .eq('is_active', true)
    .single()

  if (error || !data) throw new Error('유효하지 않은 할인코드입니다.')

  // 만료 확인
  if (data.expires_at && new Date(data.expires_at) < new Date()) {
    throw new Error('만료된 할인코드입니다.')
  }

  // 사용 횟수 확인
  if (data.max_uses !== null && data.used_count >= data.max_uses) {
    throw new Error('사용 가능 횟수가 초과된 할인코드입니다.')
  }

  // 이미 사용했는지 확인
  const user = await getUser()
  if (user) {
    const { data: used } = await supabase
      .from('discount_code_uses')
      .select('id')
      .eq('code_id', data.id)
      .eq('user_id', user.id)
      .single()
    if (used) throw new Error('이미 사용한 할인코드입니다.')
  }

  return data
}

// 할인코드 사용 처리
export async function useDiscountCode(codeId) {
  const user = await getUser()
  if (!user) throw new Error('로그인이 필요합니다.')

  // 사용 기록 추가
  await supabase.from('discount_code_uses').insert({
    code_id: codeId,
    user_id: user.id
  })

  // used_count 증가
  await supabase.rpc('increment_discount_code_use', { code_id: codeId })
}

// 알림 목록 가져오기
export async function getNotifications() {
  const user = await getUser()
  if (!user) return []
  const { data, error } = await supabase
    .from('notifications')
    .select('*')
    .eq('user_id', user.id)
    .order('created_at', { ascending: false })
    .limit(20)
  if (error) return []
  return data || []
}

// 읽지 않은 알림 수
export async function getUnreadCount() {
  const user = await getUser()
  if (!user) return 0
  const { count } = await supabase
    .from('notifications')
    .select('*', { count: 'exact', head: true })
    .eq('user_id', user.id)
    .eq('is_read', false)
  return count || 0
}

// 알림 읽음 처리
export async function markAllRead() {
  const user = await getUser()
  if (!user) return
  await supabase
    .from('notifications')
    .update({ is_read: true })
    .eq('user_id', user.id)
    .eq('is_read', false)
}

// 알림 생성
export async function createNotification(userId, type, message, bikeId = null) {
  await supabase.from('notifications').insert({
    user_id: userId,
    type,
    message,
    bike_id: bikeId
  })
}

// 이미지 업로드
export async function uploadBikePhoto(file, bikeId) {
  const user = await getUser()
  if (!user) throw new Error('로그인이 필요합니다')

  const ext = file.name.split('.').pop()
  const path = `${user.id}/${bikeId}_${Date.now()}.${ext}`

  const { data, error } = await supabase.storage
    .from('bike-photos')
    .upload(path, file, { upsert: true })

  if (error) throw error

  // 공개 URL 반환
  const { data: { publicUrl } } = supabase.storage
    .from('bike-photos')
    .getPublicUrl(path)

  return publicUrl
}

// 자전거 사진 여러 장 업로드
export async function uploadBikePhotos(files, bikeId) {
  const urls = []
  for (const file of files) {
    const url = await uploadBikePhoto(file, bikeId)
    urls.push(url)
  }
  return urls
}

// 자전거 사진 URL 저장
export async function saveBikePhotos(bikeId, photoUrls) {
  const { error } = await supabase
    .from('bikes')
    .update({ photos: photoUrls })
    .eq('id', bikeId)
  if (error) throw error
}

// 이름 마스킹: 홍길동 → 홍*동
function maskName(name) {
  if (!name || name.length < 2) return name
  if (name.length === 2) return name[0] + '*'
  return name[0] + '*'.repeat(name.length - 2) + name[name.length - 1]
}

// 연락처 마스킹: 010-1234-5678 → 010-1234-****
export function maskPhone(phone) {
  if (!phone) return ''
  return phone.replace(/(\d{3}-\d{4}-)(\d{4})/, '$1****')
}

// 양도 코드 생성 (영문+숫자 6자리)
function generateCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789' // 혼동 문자 제외 (0,O,1,I)
  let code = ''
  for (let i = 0; i < 6; i++) {
    code += chars[Math.floor(Math.random() * chars.length)]
  }
  return code
}

// 간단한 해시 (스캔 로그용)
async function hashString(str) {
  const msgBuffer = new TextEncoder().encode(str)
  const hashBuffer = await crypto.subtle.digest('SHA-256', msgBuffer)
  const hashArray = Array.from(new Uint8Array(hashBuffer))
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('').slice(0, 16)
}

// 인증 상태 변화 감지
export function onAuthChange(callback) {
  return supabase.auth.onAuthStateChange(callback)
}

