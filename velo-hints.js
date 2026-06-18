// =============================================================
// velo-hints.js — 가로 스크롤(스와이프) 가능 힌트
// 넓은 표/탭 줄이 화면보다 넓을 때만 오른쪽 페이드 + "밀어서 더 보기" 칩 표시.
// 끝까지 밀면 자동으로 사라짐. <script defer src="/velo-hints.js"></script>
// =============================================================
(function () {
  function setup() {
    [['.table-wrap', true], ['.tabs', false], ['.setting-tabs', false], ['.filter-tabs', false]]
      .forEach(function (pair) {
        var sel = pair[0], isTable = pair[1]
        document.querySelectorAll(sel).forEach(function (el) {
          if (el._swipeCheck) { el._swipeCheck(); return } // 이미 처리됨 → 재측정만
          var w = document.createElement('div')
          w.className = 'swipe-x' + (isTable ? ' is-table' : '')
          el.parentNode.insertBefore(w, el)
          w.appendChild(el)
          function check() {
            var over = el.scrollWidth - el.clientWidth > 6
            w.classList.toggle('can-swipe', over)
            w.classList.toggle('at-end', el.scrollLeft >= el.scrollWidth - el.clientWidth - 2)
          }
          el._swipeCheck = check
          el.addEventListener('scroll', check, { passive: true })
          window.addEventListener('resize', check)
          check()
        })
      })
  }
  function run() { setup(); setTimeout(setup, 700); setTimeout(setup, 1600) }
  if (document.readyState !== 'loading') run()
  else document.addEventListener('DOMContentLoaded', run)
})()
