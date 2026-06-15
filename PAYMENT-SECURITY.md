# 결제 보안 점검 & 수정 가이드

## 점검 결과: 현재 결제는 무결제 우회가 가능 (CRITICAL)

라이브(publishable 키 + 가입 계정)로 확인한 우회 경로:

| # | 우회 | 결과 |
|---|------|------|
| 1 | 로그인 유저가 본인 `users.plan` 을 `yearly` 로 PATCH | 204 → 실제 `yearly` 로 바뀜 |
| 2 | `orders` 에 `status:"paid"` 가짜 주문 insert | 201 |
| 3 | `subscriptions` 직접 insert (yearly) | 201 |
| 4 | `/velo-payment.html?paymentKey=x&plan=yearly` URL 직접 열기 | `handleSuccess`가 권한 부여 |

### 근본 원인
- **서버가 없음**(정적 사이트, `api/` 없음) → Toss **서버 승인(confirm) 단계가 아예 없음**.
  결제 위젯을 통과(successUrl 리다이렉트)했다고 돈이 캡처되는 게 아니라, 가맹점 서버가
  secret key로 `POST /v1/payments/confirm` 을 호출해야 실제 결제됨. 그게 없음.
- **권한 부여를 클라이언트가 함**: `handleSuccess`가 URL 파라미터(plan/amount)만 보고
  `orders` insert + `startSubscription()` 호출. 검증 0.
- **가격이 클라이언트 값**: `products`/`subs` 배열. 위변조 가능.
- `TOSS_CLIENT_KEY = 'YOUR_TOSS_CLIENT_KEY'` — placeholder (아직 결제 미설정 상태).

> 정적 클라이언트만으로는 무결제 우회를 막을 수 없습니다. 반드시 **서버(Edge Function)** 가
> secret key로 결제를 확정하고, 그 서버만 권한을 부여해야 합니다.

---

## 수정 (3개 함께 배포)

### 1) Edge Function 배포 — `supabase/functions/confirm-payment/index.ts`
서버에서 ①호출자 JWT 확인 ②기대 금액 서버계산 ③Toss confirm(secret) ④service_role로 권한부여.
```
supabase functions deploy confirm-payment
supabase secrets set TOSS_SECRET_KEY=test_sk_xxx   # 실제 발급키로 교체
```

### 2) 클라이언트 수정 — `velo-payment.html`
`startPayment` 의 successUrl 에 product/plan 추가:
```js
const PRODUCT_KEYS = ['tag_basic','tag_card','transfer']  // selectedProd 인덱스 매핑
// ...
successUrl: window.location.origin + '/velo-payment.html?plan=' + sub.plan
          + '&product=' + PRODUCT_KEYS[selectedProd],
```
`handleSuccess` 를 "클라가 직접 부여" → "서버 함수 호출" 로 교체:
```js
async function handleSuccess(params) {
  document.getElementById('payForm').style.display = 'none'
  const { data: { session } } = await supabase.auth.getSession()
  const res = await fetch('https://<PROJECT>.functions.supabase.co/confirm-payment', {
    method: 'POST',
    headers: { 'Content-Type':'application/json', 'Authorization':'Bearer '+session.access_token },
    body: JSON.stringify({
      paymentKey: params.get('paymentKey'),
      orderId:    params.get('orderId'),
      amount:     parseInt(params.get('amount')) || 0,
      plan:       params.get('plan'),
      product:    params.get('product'),
    }),
  })
  if (res.ok) document.getElementById('successBox').classList.add('show')
  else { document.getElementById('failBox').classList.add('show'); /* 결제 확정 실패 */ }
}
```
→ 클라이언트는 더 이상 orders/subscriptions/users.plan 을 직접 쓰지 않음.
   `startSubscription()` 클라 호출도 제거(서버가 함).

### 3) DB 잠금 — `payment-lockdown.sql`
일반 유저의 `users.plan` 변경 / `subscriptions`·`orders` insert 를 차단(서버 service_role만 허용).
**반드시 1·2 배포 후 실행** (먼저 실행하면 정상 결제도 권한 부여가 막힘).

---

## 즉시 임시 조치 (백엔드 구축 전, 아직 결제 미오픈이라면)
`payment-lockdown.sql` 만 먼저 실행 → 무결제 자가부여는 즉시 차단됨.
단 이 상태에선 **정상 구독 부여 경로도 없음**(Edge Function 미배포). 결제를 실제 오픈하기
전까지의 안전한 기본값으로 적절. 결제 오픈 시 1·2를 배포하면 정상 동작.

## 그 외 권고
- 가격/플랜은 서버(Edge Function의 PRODUCT_PRICE/SUB_PRICE)가 단일 출처.
- 할인코드 적용·검증도 결국 서버 confirm 시점에 재계산해야 안전(현재는 클라 계산).
- 구독 만료/갱신도 Toss 빌링(자동결제) 웹훅으로 서버 처리 권장.
