// =============================================
// velo-supabase.js
// 모든 페이지에서 이 파일을 import해서 사용
// =============================================

import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm'

const SUPABASE_URL = 'https://kfeksnbxucmkilxrbhth.supabase.co'
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtmZWtzbmJ4dWNta2lseHJiaHRoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODAyMjQ1NTksImV4cCI6MjA5NTgwMDU1OX0.lXBqhrM_xgrNqZ6WqEWYwgo4NTyodLx9rV3TS25nyjM' // 여기에 anon key 입력

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY)

// =============================================
// AUTH (인증)
// =============================================

// 회원가입
export async function signUp({ email, password, name, phone }) {
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
      email
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
export async function getUserProfile() {
  const user = await getUser()
  if (!user) return null
  const { data, error } = await supabase
    .from('users')
    .select('*')
    .eq('id', user.id)
    .single()
  if (error) throw error
  return data
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
      ip_hash: await hashString(navigator.userAgent) // 간단한 해시
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
export async function registerBike({ serial, brand, model, year, color, memo, partnerCode, photos }) {
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
      partner_code: partnerCode || null
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
