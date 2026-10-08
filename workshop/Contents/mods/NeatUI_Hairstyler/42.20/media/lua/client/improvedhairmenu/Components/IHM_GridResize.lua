--[[ ============================================================================
    IHM_GridResize - la griglia si ridimensiona trascinando l'angolo.

    Prende il posto dei contatori "Righe" e "Colonne": trascini l'angolo in
    basso a destra e il numero di anteprime segue.

    ------------------------------------------------------------------------
    Perche' qui c'e' ISResizeWidget e non una maniglia nostra
    ------------------------------------------------------------------------

    La prima versione era scritta a mano e sbagliava una cosa sola, ma grossa:
    **due pezzi di codice possedevano la stessa misura**. Il trascinamento
    allungava la cornice inseguendo il mouse, la ricostruzione la rimetteva a
    misura di griglia, e vinceva l'ultimo arrivato. Da fuori si vedeva un
    pannello alto con dentro tre righe di anteprime e la freccia staccata in
    fondo, dove finiva la cornice e non il contenuto.

    Il widget di vanilla non ha quel problema, e il motivo e' elegante: misura
    il mouse **rispetto a se stesso**. Mentre il bersaglio cresce il widget si
    sposta verso il nuovo angolo, la distanza dal cursore si accorcia, e
    l'anello si chiude da solo. Riscriverlo a mano vuol dire riscrivere anche
    quella compensazione, e non e' ovvia finche' non la si e' vista fallire.

    E' anche il modo in cui Neat Rocco fa tutti i suoi pannelli ridimensionabili
    (NR_Utils/NR_ResizeWidget.lua e NR_LiteraturePanel:onResize): widget figlio
    del bersaglio, e una sola funzione che decide la misura e riposiziona il
    widget.

    ------------------------------------------------------------------------
    Perche' il conteggio si applica al rilascio e non durante
    ------------------------------------------------------------------------

    Il widget e' figlio di cio' che ridimensiona. In tutti e due i contesti -
    la finestra di gioco e il modale della creazione personaggio - ricostruire
    la griglia **distrugge e ricrea quel pannello**: HairMenuWindow:rebuildPanel
    fa removeChild e ne costruisce uno nuovo, e _IHM_rebuildMenu pure. Il widget
    morirebbe con lui, a meta' gesto, portandosi via la cattura del mouse.

    Quindi durante il trascinamento si muove solo la cornice, che e' continua e
    costa due setWidth, e il conteggio si applica quando lasci. La sensazione di
    fluidita' viene dalla cornice; il contenuto arriva un istante dopo, quando
    non c'e' piu' un gesto da spezzare.

    (Un modo "dal vivo" era stato scritto e poi tolto: nessuno dei due contesti
    ha un bersaglio che sopravviva alla propria ricostruzione, quindi restava
    codice irraggiungibile che descriveva una cosa non vera.)

    La geometria e' quella di HairMenuPanel:new, invertita:

        larghezza = tile * colonne + gap * (colonne - 1) + bordo * 2
        altezza   = tile * righe   + gap * (righe   - 1) + testa + bordo * 2
============================================================================ ]]--

if isServer() then return end

require "ISUI/ISResizeWidget"

IHM_GridResize = IHM_GridResize or {}
local G = IHM_GridResize

G.MIN = 1

--- Tetto di sicurezza. Il limite che conta davvero e' lo schermo, qui sotto.
G.MAX = 10

--- Quanto dello schermo puo' occupare la griglia al massimo. Non tutto: la
--- finestra deve restare afferrabile per il titolo e spostabile.
G.SCREEN_FRACTION = 0.80

--- Il lato della freccia. In Rocco (NR_ResizeWidget.SIZE) e' sempre 16.
G.SIZE = 16

--- Vero mentre si ridimensiona, e per un momento dopo.
---
--- Le finestre che si chiudono quando il clic finisce fuori da loro devono
--- saperlo: trascinando l'angolo verso l'esterno il rilascio cade quasi sempre
--- fuori, e senza questa guardia si chiudevano a ogni ridimensionamento. Vive
--- sul modulo perche' il pannello, nel frattempo, puo' essere ricreato.
G.activeUntil = 0

function G.isResizing()
    return getTimestampMs() < (G.activeUntil or 0)
end

--- Vero se vale il trascinamento, falso se valgono i contatori Righe/Colonne.
---
--- L'opzione sta in Options > Mods > NeatUI Hairstyler. Si legge a ogni frame
--- invece che una volta all'aggancio perche' cosi' cambia sotto gli occhi: la
--- maniglia smette di disegnarsi e di rispondere nello stesso istante in cui la
--- si spegne, senza dover riaprire il menu.
---
--- La maniglia resta appesa all'albero anche da spenta. Toglierla sarebbe piu'
--- pulito da guardare ma non da scrivere: un elemento invisibile non riceve
--- prerender, quindi non avrebbe modo di accorgersi che l'opzione e' tornata
--- accesa. Sedici pixel che non disegnano niente non costano nulla.
function G.enabled()
    local MS = rawget(_G, "IHM_ModSettings")
    if MS and MS.useDragResize then
        local ok, v = pcall(MS.useDragResize)
        if ok then return v end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Geometria
-- ---------------------------------------------------------------------------
local function metrics(panel)
    return panel.gridSizeX or 96,
           panel.gridSizeY or 96,
           panel.gridGap or 3,
           panel.gridPad or 0,
           panel.gridHeaderH or 0
end

--- Quante colonne e righe stanno davvero sullo schermo.
---
--- Si ricava dalla misura di una casella, quindi segue da sola la dimensione
--- delle anteprime: chi le tiene grandi ne avra' meno in fila.
---@return number colonne, number righe
function G.maxFor(panel)
    local tileW, tileH, gap, pad, head = metrics(panel)

    local ok, sw = pcall(function() return getCore():getScreenWidth() end)
    if not ok or not sw or sw <= 0 then sw = 1920 end
    local okH, sh = pcall(function() return getCore():getScreenHeight() end)
    if not okH or not sh or sh <= 0 then sh = 1080 end

    local cols = math.floor((sw * G.SCREEN_FRACTION - pad * 2 + gap) / (tileW + gap))
    local rows = math.floor((sh * G.SCREEN_FRACTION - pad * 2 - head + gap) / (tileH + gap))

    return math.max(G.MIN, math.min(cols, G.MAX)),
           math.max(G.MIN, math.min(rows, G.MAX))
end

--- Da una misura in pixel al numero di caselle che ci stanno.
---@return number colonne, number righe
function G.gridFor(panel, width, height)
    local tileW, tileH, gap, pad, head = metrics(panel)

    -- Il pannello puo' essere piu' largo della griglia che contiene: in
    -- creazione personaggio ReplaceCombobox lo allarga perche' ci stia
    -- l'intestazione (pagine, nome dello stile, i tasti in alto a destra), e
    -- quei pixel non sono caselle. Contarli come tali faceva comparire una
    -- colonna che non c'era: il numero saliva, la ricostruzione lo rimetteva
    -- giu', e il trascinamento si sentiva incerto.
    width  = width  - (panel._ihmChromeW or 0)
    height = height - (panel._ihmChromeH or 0)

    local cols = math.floor((width - pad * 2 + gap) / (tileW + gap) + 0.5)
    local rows = math.floor((height - head - pad * 2 + gap) / (tileH + gap) + 0.5)

    local maxCols, maxRows = G.maxFor(panel)
    return math.max(G.MIN, math.min(cols, maxCols)),
           math.max(G.MIN, math.min(rows, maxRows))
end

--- E il contrario: quanto misura esattamente una griglia di tot caselle.
---@return number larghezza, number altezza
function G.sizeFor(panel, cols, rows)
    local tileW, tileH, gap, pad, head = metrics(panel)
    return tileW * cols + gap * (cols - 1) + pad * 2,
           tileH * rows + gap * (rows - 1) + head + pad * 2
end

-- ---------------------------------------------------------------------------
-- Aggancio
-- ---------------------------------------------------------------------------
--- La maniglia si mette all'angolo **da sola**, ogni frame, subito prima di
--- disegnarsi.
---
--- Prima la posizione si aggiornava solo dentro resizeFunction, cioe' solo
--- mentre si trascinava: qualunque altra cosa cambiasse la misura del pannello
--- - una ricostruzione, il layout della finestra, un cambio di pagina - la
--- lasciava indietro, e si vedeva staccata dall'angolo. Facendolo qui non c'e'
--- nessun percorso che possa dimenticarsene: due assegnazioni per frame su un
--- elemento di sedici pixel.
local function drawGrip(widget)
    local t = widget.target
    if t then
        widget:setX(t:getWidth() - G.SIZE)
        widget:setY(t:getHeight() - G.SIZE)
    end

    if not G.enabled() then return end

    local alpha = (widget.resizing or widget.mouseOver) and 0.8 or 0.6
    for _, p in ipairs({ "media/ui/NeatUI/Resize/ResizeIcon.png",
                         "media/ui/IHMNeat/Icon/ResizeIcon.png" }) do
        local ok, tex = pcall(getTexture, p)
        if ok and tex then
            widget:drawTextureScaledAspect(tex, 0, 0, widget.width, widget.height, alpha, 1, 1, 1)
            return
        end
    end
    widget:drawRect(0, 0, widget.width, widget.height, alpha * 0.4, 0.9, 0.9, 0.9)
end

--- Rimette la freccia nell'angolo, subito.
---
--- Il padrone della posizione e' il prerender della maniglia, che la rifa' ogni
--- frame. Questa serve solo a non aspettare il frame dopo quando la misura e'
--- appena cambiata.
function G.position(panel)
    local w = panel and panel._ihmGrip
    if not w then return end
    w:setX(panel:getWidth() - G.SIZE)
    w:setY(panel:getHeight() - G.SIZE)
end

--- Attacca la maniglia al pannello.
---
---@param panel table il pannello da ridimensionare, e genitore della maniglia
---@param apply function(cols, rows) chi salva il conteggio e ricostruisce
function G.attach(panel, apply)
    if not panel or panel._ihmGrip then return end

    local widget = ISResizeWidget:new(panel:getWidth() - G.SIZE, panel:getHeight() - G.SIZE,
                                      G.SIZE, G.SIZE, panel)
    -- Le ancore di serie sposterebbero il widget insieme al bordo del genitore,
    -- e la posizione la decide gia' il prerender qui sopra. Due padroni per la
    -- stessa cosa e' il difetto da cui viene tutto questo file.
    widget.anchorRight = false
    widget.anchorBottom = false
    widget:initialise()
    widget.prerender = drawGrip

    widget.resizeFunction = function(target, w, h)
        G.activeUntil = getTimestampMs() + 400

        -- La cornice si ferma dove si ferma la griglia: tirandola oltre si
        -- staccherebbe dal contenuto, che e' come si presentava il difetto.
        local maxCols, maxRows = G.maxFor(target)
        local cw, ch = target._ihmChromeW or 0, target._ihmChromeH or 0
        local minW, minH = G.sizeFor(target, G.MIN, G.MIN)
        local maxW, maxH = G.sizeFor(target, maxCols, maxRows)
        w = math.max(minW + cw, math.min(w, maxW + cw))
        h = math.max(minH + ch, math.min(h, maxH + ch))

        target:setWidth(w)
        target:setHeight(h)
        G.position(target)

        -- Solo il conteggio, annotato. Applicarlo qui vorrebbe dire ricostruire,
        -- e ricostruire distrugge questo pannello insieme alla maniglia che sta
        -- trascinando.
        target._ihmCols, target._ihmRows = G.gridFor(target, w, h)
    end

    -- Alla presa si misura quanto della cornice non e' griglia. Si fa adesso e
    -- non all'aggancio perche' all'aggancio il pannello non ha ancora la misura
    -- definitiva: chi lo allarga per l'intestazione lo fa dopo initialise.
    local ogDown = widget.onMouseDown
    widget.onMouseDown = function(self, x, y)
        -- Falso, non nil: il clic deve passare al pannello sotto invece di
        -- morire su un quadratino che non si vede.
        if not G.enabled() then return false end

        local t = self.target
        local c, r = t.gridCols, t.gridRows
        if c and r then
            local gw, gh = G.sizeFor(t, c, r)
            t._ihmChromeW = math.max(0, t:getWidth()  - gw)
            t._ihmChromeH = math.max(0, t:getHeight() - gh)
        end

        -- I limiti di vanilla, allineati ai nostri. ISResizeWidget:resize li
        -- legge sul bersaglio e, se sono nil, ci scrive zero: senza questa riga
        -- il pannello si potrebbe schiacciare fino a sparire prima ancora che il
        -- nostro clamp veda il numero.
        local minW, minH = G.sizeFor(t, G.MIN, G.MIN)
        t.minimumWidth  = minW + (t._ihmChromeW or 0)
        t.minimumHeight = minH + (t._ihmChromeH or 0)

        G.activeUntil = getTimestampMs() + 400
        return ogDown(self, x, y)
    end

    -- Al rilascio: e' qui che il conteggio diventa vero e la griglia si rifa'.
    local function finish(self)
        if not self.resizing then return end
        local target = self.target
        local cols = target._ihmCols
        local rows = target._ihmRows
        if not cols or not rows then
            cols, rows = G.gridFor(target, target:getWidth(), target:getHeight())
        end

        -- Adesso si puo': il gesto e' finito, e se la ricostruzione porta via
        -- questo pannello non c'e' piu' niente da spezzare.
        pcall(apply, cols, rows)
        G.activeUntil = getTimestampMs() + 300
    end

    local ogUp, ogUpOut = widget.onMouseUp, widget.onMouseUpOutside
    widget.onMouseUp = function(self, x, y)
        finish(self)
        return ogUp(self, x, y)
    end
    widget.onMouseUpOutside = function(self, x, y)
        finish(self)
        return ogUpOut(self, x, y)
    end

    panel:addChild(widget)
    widget:setAlwaysOnTop(true)
    panel._ihmGrip = widget

    panel._ihmCols, panel._ihmRows = G.gridFor(panel, panel:getWidth(), panel:getHeight())
end

return G
