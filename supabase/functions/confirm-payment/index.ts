// =============================================================
// Supabase Edge Function: confirm-payment
// 결제를 "서버에서" 확정/검증한 뒤에만 구독·주문 권한을 부여한다.
// 클라이언트는 절대 plan/subscriptions/orders 를 직접 못 쓰게 막고(아래 SQL),
// 오직 이 함수(service_role)만 권한을 부여한다 → 무결제 우회 차단.
//
// 배포:
//   supabase functions deploy confirm-payment
//   supabase secrets set TOSS_SECRET_KEY=live_sk_xxx   (테스트는 test_sk_xxx)
//   (SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY 는 런타임에 자동 주입됨)
// =============================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// ★ 가격은 "서버"가 정한다(클라이언트 값 신뢰 금지)
const PRODUCT_PRICE: Record<string, number> = {
  'tag_basic': 7900,   // 칩 2개(기본)
  'tag_card': 9900,    // 칩 2개 + 카드
  'transfer': 490,     // 양도 수수료
}
const SUB_PRICE: Record<string, number> = { free: 0, monthly: 490, yearly: 4900 }

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}
const json = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...cors, 'Content-Type': 'application/json' } })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  try {
    const { paymentKey, orderId, amount, plan = 'free', product } = await req.json()
    if (!paymentKey || !orderId || typeof amount !== 'number') return json({ error: 'bad request' }, 400)

    // 1) 호출자 신원은 JWT에서 확인(body의 userId 신뢰 금지)
    const authHeader = req.headers.get('Authorization') ?? ''
    const userClient = createClient(
      Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    )
    const { data: { user } } = await userClient.auth.getUser()
    if (!user) return json({ error: 'unauthorized' }, 401)

    // 2) 서버가 기대 금액 계산 → 클라이언트가 보낸 amount와 PG amount가 일치해야 함
    const expected = (PRODUCT_PRICE[product] ?? -1) + (SUB_PRICE[plan] ?? -1)
    if (expected < 0 || amount !== expected) return json({ error: 'amount mismatch', expected }, 400)

    // 3) Toss 서버 승인(secret key) — 여기서 실제로 결제가 캡처됨
    const tossRes = await fetch('https://api.tosspayments.com/v1/payments/confirm', {
      method: 'POST',
      headers: {
        'Authorization': 'Basic ' + btoa(Deno.env.get('TOSS_SECRET_KEY')! + ':'),
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ paymentKey, orderId, amount }),
    })
    if (!tossRes.ok) return json({ error: 'payment not confirmed', detail: await tossRes.text() }, 402)

    // 4) 확정된 경우에만 service_role 로 권한 부여(RLS/가드 우회 가능 역할)
    const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
    await admin.from('orders').insert({
      user_id: user.id, product_name: product, amount, payment_key: paymentKey,
      status: 'paid', delivery_status: 'pending',
    })
    if (plan !== 'free') {
      const days = plan === 'yearly' ? 365 : 30
      await admin.from('subscriptions').insert({
        user_id: user.id, plan, expires_at: new Date(Date.now() + days * 864e5).toISOString(),
      })
      await admin.from('users').update({ plan }).eq('id', user.id)
    }
    return json({ ok: true })
  } catch (e) {
    return json({ error: String(e) }, 500)
  }
})
