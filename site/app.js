// Site da Eleva: menu, índice de bairros, filtros e visor de fotos.
(function () {
  var btn = document.querySelector(".menu-btn"), menu = document.getElementById("menu");
  if (btn && menu) {
    btn.addEventListener("click", function () {
      var aberto = menu.hasAttribute("data-aberto");
      menu.toggleAttribute("data-aberto", !aberto);
      btn.setAttribute("aria-expanded", String(!aberto));
    });
    menu.addEventListener("click", function (ev) {
      if (ev.target.tagName === "A") { menu.removeAttribute("data-aberto"); btn.setAttribute("aria-expanded", "false"); }
    });
  }

  // Menu "Imóveis" com a lista de bairros.
  var sub = document.querySelector(".sub");
  if (sub) {
    var sb = sub.querySelector(".sub-btn");
    var abrir = function (v) { sub.toggleAttribute("data-aberto", v); sb.setAttribute("aria-expanded", String(v)); };
    sb.addEventListener("click", function (ev) { ev.stopPropagation(); abrir(!sub.hasAttribute("data-aberto")); });
    document.addEventListener("click", function (ev) { if (!sub.contains(ev.target)) abrir(false); });
    document.addEventListener("keydown", function (ev) { if (ev.key === "Escape") abrir(false); });
  }

  // Passador genérico (capa e depoimentos).
  function passador(itens, pontos, ant, prox, intervalo, sempre) {
    if (itens.length < 2) { [ant, prox].forEach(function (b) { if (b) b.hidden = true; }); return; }
    var i = 0, t = null, calmo = !sempre && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    var ir = function (n) {
      itens[i].classList.remove("ativo"); if (pontos[i]) pontos[i].removeAttribute("aria-current");
      i = (n + itens.length) % itens.length;
      itens[i].classList.add("ativo"); if (pontos[i]) pontos[i].setAttribute("aria-current", "true");
    };
    var rodar = function () { clearInterval(t); if (intervalo && !calmo) t = setInterval(function () { ir(i + 1); }, intervalo); };
    ant.addEventListener("click", function () { ir(i - 1); rodar(); });
    prox.addEventListener("click", function () { ir(i + 1); rodar(); });
    pontos.forEach(function (p, k) { p.addEventListener("click", function () { ir(k); rodar(); }); });
    var caixa = itens[0].parentNode, x0 = null;
    caixa.addEventListener("mouseenter", function () { clearInterval(t); });
    caixa.addEventListener("mouseleave", rodar);
    caixa.addEventListener("touchstart", function (ev) { x0 = ev.touches[0].clientX; }, { passive: true });
    caixa.addEventListener("touchend", function (ev) {
      if (x0 === null) return;
      var dx = ev.changedTouches[0].clientX - x0; x0 = null;
      if (Math.abs(dx) > 45) { ir(i + (dx < 0 ? 1 : -1)); rodar(); }
    });
    rodar();
  }
  var q = function (s) { return [].slice.call(document.querySelectorAll(s)); };
  if (document.getElementById("slides")) passador(q("#slides .slide"), q("#pontos button"), document.getElementById("sAnt"), document.getElementById("sProx"), 5500, true);
  if (document.getElementById("deps")) passador(q("#deps .dep"), [], document.getElementById("dAnt"), document.getElementById("dProx"), 0);

  // Pedido de simulação: formata os valores e abre o WhatsApp com a mensagem pronta.
  var sim = document.getElementById("simula");
  if (sim) {
    q("#simula input").forEach(function (inp) {
      inp.addEventListener("input", function () {
        var d = inp.value.replace(/\D/g, "").replace(/^0+/, "");
        inp.value = d ? "R$ " + d.replace(/\B(?=(\d{3})+(?!\d))/g, ".") : "";
      });
    });
    sim.addEventListener("submit", function (ev) {
      ev.preventDefault();
      var v = sim.valor.value, r = sim.renda.value, en = sim.entrada.value;
      var msg = "Olá! Vim pelo site da Eleva e quero uma simulação de financiamento.";
      if (v) msg += "\nValor do imóvel: " + v;
      if (r) msg += "\nRenda mensal da família: " + r;
      if (en) msg += "\nEntrada disponível: " + en;
      window.open("https://wa.me/" + sim.dataset.wa + "?text=" + encodeURIComponent(msg), "_blank", "noopener");
    });
  }

  // Filtros da lista de empreendimentos.
  var form = document.getElementById("filtros");
  if (form) {
    var cartoes = [].slice.call(document.querySelectorAll("#grade .cartao"));
    var contagem = document.getElementById("contagem"), vazio = document.getElementById("vazio");
    var aplicar = function () {
      var b = form.bairro.value, f = form.faixa.value.split("-"), n = 0;
      var min = f[0] ? +f[0] : null, max = f[1] ? +f[1] : Infinity;
      cartoes.forEach(function (c) {
        var p = c.dataset.preco ? +c.dataset.preco : null;
        var ok = (!b || c.dataset.bairro === b) && (min === null || (p !== null && p >= min && p <= max));
        c.hidden = !ok;
        if (ok) n++;
      });
      contagem.textContent = n === 1 ? "1 empreendimento" : n + " empreendimentos";
      vazio.hidden = n > 0;
    };
    form.addEventListener("change", aplicar);
    form.addEventListener("submit", function (ev) { ev.preventDefault(); });
    document.getElementById("limpar").addEventListener("click", function () { form.reset(); aplicar(); });
    aplicar();
  }

  // Visor de fotos do empreendimento.
  var galeria = document.getElementById("galeria"), visor = document.getElementById("visor");
  if (galeria && visor) {
    var itens = [].slice.call(galeria.querySelectorAll("a")), img = document.getElementById("vImg");
    var conta = document.getElementById("vConta"), atual = 0, voltarPara;
    var mostrar = function (i) {
      atual = (i + itens.length) % itens.length;
      img.src = itens[atual].getAttribute("href");
      img.alt = itens[atual].querySelector("img").alt;
      conta.textContent = (atual + 1) + " de " + itens.length;
    };
    var fechar = function () { visor.hidden = true; document.documentElement.style.overflow = ""; if (voltarPara) voltarPara.focus(); };
    galeria.addEventListener("click", function (ev) {
      var a = ev.target.closest("a");
      if (!a) return;
      ev.preventDefault();
      voltarPara = a;
      visor.hidden = false;
      document.documentElement.style.overflow = "hidden";
      mostrar(+a.dataset.i);
      document.getElementById("vFechar").focus();
    });
    document.getElementById("vFechar").addEventListener("click", fechar);
    document.getElementById("vAnt").addEventListener("click", function () { mostrar(atual - 1); });
    document.getElementById("vProx").addEventListener("click", function () { mostrar(atual + 1); });
    visor.addEventListener("click", function (ev) { if (ev.target === visor) fechar(); });
    document.addEventListener("keydown", function (ev) {
      if (visor.hidden) return;
      if (ev.key === "Escape") fechar();
      else if (ev.key === "ArrowLeft") mostrar(atual - 1);
      else if (ev.key === "ArrowRight") mostrar(atual + 1);
    });
    var x0 = null;
    visor.addEventListener("touchstart", function (ev) { x0 = ev.touches[0].clientX; }, { passive: true });
    visor.addEventListener("touchend", function (ev) {
      if (x0 === null) return;
      var dx = ev.changedTouches[0].clientX - x0;
      if (Math.abs(dx) > 50) mostrar(atual + (dx < 0 ? 1 : -1));
      x0 = null;
    });
  }
})();
