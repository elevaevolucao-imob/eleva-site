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

  // Capa: passar o mouse num bairro mostra um empreendimento de lá.
  var capa = document.getElementById("capaImg");
  if (capa && window.matchMedia("(hover:hover)").matches) {
    var original = capa.getAttribute("src"), espera;
    var trocar = function (src) {
      clearTimeout(espera);
      if (capa.getAttribute("src") === src) return;
      capa.classList.add("trocando");
      espera = setTimeout(function () {
        var pre = new Image();
        pre.onload = pre.onerror = function () { capa.src = src; capa.classList.remove("trocando"); };
        pre.src = src;
      }, 180);
    };
    document.querySelectorAll(".indice a").forEach(function (a) {
      a.addEventListener("mouseenter", function () { trocar(a.dataset.capa); });
      a.addEventListener("focus", function () { trocar(a.dataset.capa); });
    });
    var lista = document.querySelector(".indice");
    lista.addEventListener("mouseleave", function () { trocar(original); });
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
