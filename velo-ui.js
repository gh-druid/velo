// =============================================================
// velo-ui.js — 공통 UX 헬퍼 (토스트 · 확인모달 · 스켈레톤 · 상대시간)
// import { toast, confirmDialog, skeleton, timeAgo } from '/velo-ui.js'
// =============================================================

// 토스트 알림 (alert 대체)
export function toast(msg, type = 'info', ms = 2600) {
  let el = document.getElementById('v-toast')
  if (!el) { el = document.createElement('div'); el.id = 'v-toast'; el.className = 'v-toast'; document.body.appendChild(el) }
  el.textContent = msg
  el.style.background = type === 'error' ? '#d8453f' : type === 'success' ? '#1c3a2a' : '#14180f'
  // 강제 리플로우로 연속 호출에도 애니메이션 재생
  el.classList.remove('show'); void el.offsetWidth; el.classList.add('show')
  clearTimeout(el._t); el._t = setTimeout(() => el.classList.remove('show'), ms)
}

// 확인 다이얼로그 (confirm 대체) → Promise<boolean>
export function confirmDialog(opts = {}) {
  const { title = '확인', message = '', confirmText = '확인', cancelText = '취소', danger = false } = opts
  return new Promise(resolve => {
    const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;' }[c]))
    const ov = document.createElement('div')
    ov.className = 'v-modal-ov'
    ov.innerHTML = `<div class="v-modal" role="dialog" aria-modal="true">
        <div class="v-modal-title">${esc(title)}</div>
        ${message ? `<div class="v-modal-msg">${esc(message)}</div>` : ''}
        <div class="v-modal-actions">
          <button class="v-btn v-btn-out" data-x>${esc(cancelText)}</button>
          <button class="v-btn ${danger ? 'v-btn-danger' : 'v-btn-ink'}" data-ok>${esc(confirmText)}</button>
        </div>
      </div>`
    document.body.appendChild(ov)
    requestAnimationFrame(() => ov.classList.add('show'))
    const close = v => { ov.classList.remove('show'); setTimeout(() => ov.remove(), 200); document.removeEventListener('keydown', onKey); resolve(v) }
    const onKey = e => { if (e.key === 'Escape') close(false); if (e.key === 'Enter') close(true) }
    ov.addEventListener('click', e => { if (e.target === ov) close(false) })
    ov.querySelector('[data-x]').onclick = () => close(false)
    ov.querySelector('[data-ok]').onclick = () => close(true)
    document.addEventListener('keydown', onKey)
    setTimeout(() => ov.querySelector('[data-ok]').focus(), 50)
  })
}

// 스켈레톤 블록 n개 (로딩 표시)
export function skeleton(n = 3, height = 116) {
  return Array.from({ length: n }, () =>
    `<div class="v-skel" style="height:${height}px;margin-bottom:10px;border-radius:14px"></div>`).join('')
}

// 상대 시간 ("3분 전")
export function timeAgo(d) {
  if (!d) return ''
  const t = new Date(d).getTime(); if (isNaN(t)) return ''
  const s = Math.floor((Date.now() - t) / 1000)
  if (s < 60) return '방금 전'
  const m = Math.floor(s / 60); if (m < 60) return `${m}분 전`
  const h = Math.floor(m / 60); if (h < 24) return `${h}시간 전`
  const day = Math.floor(h / 24); if (day < 7) return `${day}일 전`
  const dt = new Date(t); const p = n => String(n).padStart(2, '0')
  return `${dt.getFullYear()}.${p(dt.getMonth() + 1)}.${p(dt.getDate())}`
}

// 빈 화면 HTML
export function emptyState({ icon = '📭', title = '아직 없어요', desc = '', actionLabel = '', actionHref = '' } = {}) {
  return `<div class="v-empty">
    <div class="v-empty-icon">${icon}</div>
    <div class="v-empty-title">${title}</div>
    ${desc ? `<div class="v-empty-desc">${desc}</div>` : ''}
    ${actionLabel ? `<a href="${actionHref}" class="v-btn v-btn-ink" style="margin-top:18px">${actionLabel}</a>` : ''}
  </div>`
}
