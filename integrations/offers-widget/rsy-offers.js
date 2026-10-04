/* <rsy-offers src="https://shop.example" limit="6"></rsy-offers>
 * Renders the shop's active offers from the fluentcart-offers feed. No framework, no innerHTML: feed text only ever
 * reaches the page through textContent, and a link is used only when it is https on the same host as `src`. */
(function () {
  'use strict';

  function money(minor, currency, zeroDecimal) {
    if (typeof minor !== 'number') return '';
    var v = zeroDecimal ? minor : minor / 100;
    try { return new Intl.NumberFormat('es-CR', { style: 'currency', currency: currency, maximumFractionDigits: zeroDecimal ? 0 : 2 }).format(v); }
    catch (e) { return v + ' ' + currency; }
  }

  function priceText(o, feed) {
    if (o.price_min == null) return '';
    var a = money(o.price_min, feed.currency, feed.zero_decimal), b = money(o.price_max, feed.currency, feed.zero_decimal);
    return o.price_max != null && o.price_max !== o.price_min ? a + ' – ' + b : a;
  }

  function discountText(o) {
    if (!o.discount) return '';
    return o.discount.type === 'percent' ? o.discount.amount + '% de descuento' : 'Descuento ' + o.discount.amount;
  }

  function safeLink(link, src) {
    try {
      var u = new URL(link, src), s = new URL(src);
      return u.protocol === 'https:' && u.host === s.host ? u.href : null;
    } catch (e) { return null; }
  }

  function safeImage(url) {
    try { var u = new URL(url); return u.protocol === 'https:' ? u.href : null; } catch (e) { return null; }
  }

  function el(tag, cls, text) {
    var n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text) n.textContent = text;
    return n;
  }

  function card(o, feed, src) {
    var link = safeLink(o.link, src), img = o.image && safeImage(o.image);
    var c = el(link ? 'a' : 'div', 'rsy-offer');
    if (link) { c.href = link; c.rel = 'noopener'; }
    if (img) { var i = el('img', 'rsy-offer-img'); i.src = img; i.alt = ''; i.loading = 'lazy'; c.appendChild(i); }
    var b = el('div', 'rsy-offer-body');
    b.appendChild(el('strong', 'rsy-offer-title', o.title));
    if (o.days) b.appendChild(el('span', 'rsy-offer-days', o.days));
    var p = priceText(o, feed) || discountText(o);
    if (p) b.appendChild(el('span', 'rsy-offer-price', p));
    if (o.code) b.appendChild(el('span', 'rsy-offer-code', 'Código: ' + o.code));
    c.appendChild(b);
    return c;
  }

  var CSS = ':host{display:block}.rsy-offers{display:grid;gap:12px;grid-template-columns:repeat(auto-fill,minmax(220px,1fr))}' +
    '.rsy-offer{display:flex;flex-direction:column;border:1px solid rgba(128,128,128,.35);border-radius:10px;overflow:hidden;color:inherit;text-decoration:none;background:transparent}' +
    '.rsy-offer-img{width:100%;aspect-ratio:4/3;object-fit:cover}.rsy-offer-body{display:flex;flex-direction:column;gap:4px;padding:12px}' +
    '.rsy-offer-days{font-size:.85em;opacity:.75}.rsy-offer-price{font-weight:600}.rsy-offer-code{font-family:monospace}';

  if (typeof customElements !== 'undefined' && typeof HTMLElement !== 'undefined') {
    customElements.define('rsy-offers', class extends HTMLElement {
      connectedCallback() {
        var src = this.getAttribute('src') || '', root = this.attachShadow({ mode: 'open' });
        var style = el('style'); style.textContent = CSS; root.appendChild(style);
        var grid = el('div', 'rsy-offers'); root.appendChild(grid);
        var limit = Math.max(1, Math.min(20, parseInt(this.getAttribute('limit'), 10) || 6));
        if (!/^https:\/\//.test(src)) { this.hidden = true; return; }
        fetch(src.replace(/\/$/, '') + '/wp-json/rapscalyon/v1/offers/active?limit=' + limit, { credentials: 'omit' })
          .then(function (r) { return r.ok ? r.json() : Promise.reject(); })
          .then(function (feed) {
            var list = (feed && feed.offers) || [];
            if (!list.length) { this.hidden = true; return; }
            list.forEach(function (o) { grid.appendChild(card(o, feed, src)); });
          }.bind(this))
          .catch(function () { this.hidden = true; }.bind(this));
      }
    });
  }

  if (typeof module !== 'undefined') module.exports = { money: money, priceText: priceText, discountText: discountText, safeLink: safeLink, safeImage: safeImage };
})();
