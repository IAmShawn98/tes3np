(() => {
    "use strict";
    // Only the public map's top-level document; never touch other origins or iframes.
    if (window.top !== window || location.origin !== "https://map.nerevarineprophecies.com") return;
    /* TES3NP_THEME_FONT_LOAD */
    function findFilterPanel(doc) {
    const node = doc.getElementById("filter-container");
    if (!node || node === doc.body || node === doc.documentElement ||
        node.querySelector('.leaflet-map-pane, .leaflet-tile-pane, canvas, input[type="search"], input[placeholder*="search markers" i]')) return null;
    return node;
}
    function setFilterVisibility(panel, hidden, savedDisplay) {
    if (hidden) panel.style.setProperty("display", "none", "important");
    else if (savedDisplay.value) panel.style.setProperty("display", savedDisplay.value, savedDisplay.priority);
    else panel.style.removeProperty("display");
}

    let panel = null, savedDisplay = null, button = null, host = null;
    let collapsed = true, scheduled = false;
    const texture = "/* TES3NP_MAP_BORDER_TEXTURE */";
    const apply = (element, styles) => {
        for (const [name, value] of Object.entries(styles)) element.style.setProperty(name, value, "important");
    };
    function fitPanel() {
        if (!panel || collapsed || !host) return;
        const room = Math.max(48, Math.floor(host.getBoundingClientRect().top - panel.getBoundingClientRect().top - 6));
        apply(panel, {"max-height": room + "px", "overflow-y": "auto", "box-sizing": "border-box"});
    }
    function update() {
        if (!panel || !button) return;
        setFilterVisibility(panel, collapsed, savedDisplay);
        button.setAttribute("aria-expanded", String(!collapsed));
        button.title = collapsed ? "Show map filters" : "Hide map filters";
        fitPanel();
    }
    function createButton() {
        host = document.createElement("div");
        host.id = "tes3np-map-filter-toggle";
        apply(host, {position:"fixed", right:"10px", bottom:"22px", "z-index":"2147483646", "pointer-events":"auto"});
        const shadow = host.attachShadow({mode:"closed"});
        button = document.createElement("button");
        button.type = "button";
        button.textContent = "Filter";
        apply(button, {
            // Square, raised gold rim; the live map remains visible through the face.
            display:"block", color:"#d9b574", "font-family":"'TES3NP Theme', Georgia, serif",
            "font-size":"clamp(12px, 4.2vw, 22px)", "font-weight":"400", "line-height":"1.12",
            "box-sizing":"border-box", "min-width":"clamp(64px, 18vw, 108px)",
            padding:"3px 10px", border:"clamp(3px, 1vw, 5px) solid transparent", "border-radius":"0",
            "border-color":"#e5cb8c #6c4c27 #49301b #d7b477",
            background:"transparent",
            // No fill keyword: the border image paints only the rim, never its center.
            "border-image-source": texture.startsWith("data:image/png;base64,") ? "url(" + texture + ")" : "none",
            "border-image-slice":"5", "border-image-repeat":"round",
            "text-shadow":"1px 1px 1px #17110c",
            "box-shadow":"inset 0 0 0 1px #c4a367, inset 1px 2px 2px #0a1413, 0 0 0 1px #392715, 1px 2px 1px #17110c",
            cursor:"pointer", "white-space":"nowrap", "touch-action":"manipulation"
        });
        button.addEventListener("click", event => {
            event.preventDefault();
            event.stopPropagation();
            if (!panel || !panel.isConnected) { scan(); if (!panel) return; }
            collapsed = !collapsed;
            update();
        });
        shadow.appendChild(button);
        document.documentElement.appendChild(host);
    }
    function scan() {
        if (panel && panel.isConnected && host && host.isConnected) return;
        if (!panel || !panel.isConnected) {
            panel = findFilterPanel(document);
            if (!panel) {
                if (host) host.remove();
                host = button = null;
                return;
            }
            savedDisplay = {value:panel.style.getPropertyValue("display"), priority:panel.style.getPropertyPriority("display")};
        }
        if (!host || !host.isConnected) createButton();
        update();
    }
    function schedule() {
        if (scheduled || (panel && panel.isConnected && host && host.isConnected)) return;
        scheduled = true;
        setTimeout(() => { scheduled = false; scan(); }, 150);
    }
    function start() {
        scan();
        new MutationObserver(schedule).observe(document.documentElement, {childList:true, subtree:true});
        window.addEventListener("resize", () => { schedule(); fitPanel(); });
    }
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start, {once:true});
    else start();
})();
