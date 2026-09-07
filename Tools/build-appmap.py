#!/usr/bin/env python3
"""Construye el mapa de estados (docs/appmap/index.html) como un CANVAS tipo Figma:
nodos = capturas REALES del simulador, conectados por flechas de flujo, con pan + zoom.

Filosofía (enfoque B): el PNG ES la pantalla — renderizada por el código real vía el harness
(CenitUITests/CenitScreenshotTests + ScreenshotFixtures). Este script NO redibuja UI: la acomoda
en un lienzo navegable, la etiqueta y traza las transiciones entre estados.

Regenerar tras capturar estados nuevos:  python3 Tools/build-appmap.py
El mismo manifiesto alimenta la galería viva autocontenida (Tools/build-galeria-artifact.py).
"""
import os, html, base64, json, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APPMAP = os.path.join(ROOT, "docs", "appmap")
MAPA_DIR = os.path.join(APPMAP, "mapa")   # los manifiestos JSON, una fuente de verdad (FER-381)

NODE_W = 300                       # ancho de imagen mostrada
IMG_H  = round(NODE_W * 2622/1206) # alto proporcional a la captura (~652)

# --- Manifiesto guiado por JSON (FER-381) ----------------------------------------------------
# Cada familia declara sus nodos (estado capturable) y aristas (flujo) en `docs/appmap/mapa/<f>.json`.
# El MISMO JSON lo lee el harness (`CenitScreenshotTests.test_mapa`) para capturar y este script
# para dibujar — así una pieza/estado nuevo entra con un renglón, sin tocar código.
#
# Formas que el resto del módulo (y `build-galeria-artifact.py`, que importa MAP/COMPONENTS) espera:
#   MAP        = [ {name, blurb, nodes:{id:(png,title,cond,x,y)}, edges:[(a,b,label)], unit} , … ]
#   COMPONENTS = [ (nombre, familia_de_pieza), … ]   (mismo contrato que antes)
# Orden de familias en el lienzo: hoy → entrenar → resto (alfabético) → componentes al final.
_FAM_ORDER = {"hoy": 0, "entrenar": 1, "componentes": 99}

def _manifest_paths():
    return sorted(glob.glob(os.path.join(MAPA_DIR, "*.json")),
                  key=lambda p: (_FAM_ORDER.get(os.path.splitext(os.path.basename(p))[0], 50),
                                 os.path.basename(p)))

def _autolayout(nodos, cols=4):
    """Rellena x/y para los nodos que no los traen (cuadrícula por familia — mismas celdas que
    el grupo de componentes)."""
    cellW, cellH = NODE_W + 130, IMG_H + 150
    i = 0
    for n in nodos:
        if n.get("x") is None or n.get("y") is None:
            n["x"], n["y"] = (i % cols) * cellW, (i // cols) * cellH
        i += 1

def _frame_png(node, frame):
    """Nombre del PNG de un frame. Frame 0 = el nombre de muro (`png`, ej. hoy-apunto.png), para no
    romper el muro ni la galería; frames de scroll = `<base>-f<n>.png`."""
    base = node.get("png") or f"{node['_familia']}-{node['id']}.png"
    if frame == 0:
        return base
    stem, ext = os.path.splitext(base)
    return f"{stem}-f{frame}{ext or '.png'}"

def load_manifests():
    """Devuelve (MAP, COMPONENTS, NODES) leídos de los JSON. NODES es la lista plana de nodos con
    su familia y su lista de frames — la usan el harness (indirecto) y `check-shots.py`/`sync_shots`."""
    groups, components, flat = [], [], []
    for path in _manifest_paths():
        m = json.load(open(path, encoding="utf-8"))
        fam = m["familia"]
        nodos = m.get("nodos", [])
        for n in nodos:
            n["_familia"] = fam
        _autolayout(nodos)
        nodes = {}
        for n in nodos:
            png0 = _frame_png(n, 0)
            # En componentes el subtítulo del nodo es su familia de pieza (como el muro FER-315).
            cond = n.get("condicion") or (n.get("grupo", "") if fam == "componentes" else "")
            nodes[n["id"]] = (png0, n.get("titulo", n["id"]), cond, n["x"], n["y"])
            frames = int(n.get("frames", 1) or 1)
            flat.append({"familia": fam, "id": n["id"],
                         "pngs": [_frame_png(n, f) for f in range(frames)]})
            if fam == "componentes":
                components.append((n["id"], n.get("grupo", "")))
        edges = [(a["de"], a["a"], a.get("etiqueta", "")) for a in m.get("aristas", [])]
        groups.append({"name": m.get("titulo", fam), "blurb": m.get("blurb", ""),
                       "nodes": nodes, "edges": edges, "unit": m.get("unidad", "estados")})
    return groups, components, flat

MAP, COMPONENTS, NODES = load_manifests()

def esc(s): return html.escape(s, quote=True)

def _anchors(x, y):
    cy = y + IMG_H/2
    return {"r": (x+NODE_W, cy), "l": (x, cy)}

def node_html(nid, png, title, cond, x, y, src):
    return (f'<figure class="node" data-state="{esc(title)}" style="left:{x}px;top:{y}px;width:{NODE_W}px">'
            f'<div class="phone"><img loading="lazy" src="{src}" alt="{esc(title)}"></div>'
            f'<figcaption><b>{esc(title)}</b><span>{esc(cond)}</span></figcaption></figure>')

def edges_svg(nodes, edges):
    # bounding para el lienzo SVG
    maxx = max(x+NODE_W for (_,_,_,x,y) in nodes.values()) + 200
    maxy = max(y+IMG_H+120 for (_,_,_,x,y) in nodes.values()) + 200
    paths = []
    for a, b, label in edges:
        # Aristas cross-familia (`familia/id`) o a un nodo que no existe: se omiten aquí (cada grupo
        # es su propio board, no hay lienzo global) con un aviso — no rompen el dibujo (FER-381 · D5).
        if a not in nodes or b not in nodes:
            print(f"  (arista omitida: {a} → {b} — endpoint fuera de este board)")
            continue
        (_,_,_,ax,ay) = nodes[a]; (_,_,_,bx,by) = nodes[b]
        s = _anchors(ax,ay)["r"]; t = _anchors(bx,by)["l"]
        dx = max(80, (t[0]-s[0])*0.45)
        d = f'M {s[0]:.0f} {s[1]:.0f} C {s[0]+dx:.0f} {s[1]:.0f}, {t[0]-dx:.0f} {t[1]:.0f}, {t[0]:.0f} {t[1]:.0f}'
        paths.append(f'<path d="{d}" class="edge"/>')
        if label:
            mx=(s[0]+t[0])/2; my=(s[1]+t[1])/2
            paths.append(f'<g class="elabel" transform="translate({mx:.0f},{my:.0f})">'
                         f'<rect x="-{len(label)*3.3+8:.0f}" y="-11" width="{len(label)*6.6+16:.0f}" height="22" rx="11"/>'
                         f'<text x="0" y="4" text-anchor="middle">{esc(label)}</text></g>')
    return (f'<svg class="edges" width="{maxx}" height="{maxy}">'
            f'<defs><marker id="arw" markerWidth="12" markerHeight="12" refX="9" refY="5" orient="auto">'
            f'<path d="M0 0 L10 5 L0 10 z" fill="#7A8B84"/></marker></defs>{"".join(paths)}</svg>')

def group_html(g, src_of):
    nodes = g["nodes"]
    body = edges_svg(nodes, g["edges"])
    for nid,(png,title,cond,x,y) in nodes.items():
        body += node_html(nid,png,title,cond,x,y, src_of(png))
    maxx = max(x+NODE_W for (_,_,_,x,y) in nodes.values()) + 240
    maxy = max(y+IMG_H+120 for (_,_,_,x,y) in nodes.values()) + 160
    label=(f'<div class="glabel"><h2>{esc(g["name"])}</h2><p>{esc(g["blurb"])}</p>'
           f'<span class="count">{len(nodes)} {g.get("unit","estados")}</span></div>')
    return f'<section class="board" style="width:{maxx}px;height:{maxy}px">{label}{body}</section>'

STYLE = """
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%;overflow:hidden;background:#1E1C1B;font-family:'Space Grotesk',system-ui,sans-serif;color:#EDE9DF}
.topbar{position:fixed;top:0;left:0;right:0;height:58px;z-index:50;display:flex;align-items:center;gap:18px;
  padding:0 22px;background:rgba(24,22,21,.86);backdrop-filter:blur(10px);border-bottom:1px solid #38342F}
.topbar h1{font-size:16px;font-weight:700;color:#fff}
.topbar .sub{font-size:12px;color:#8C857A}
.topbar .spacer{flex:1}
.zoom{display:flex;align-items:center;gap:2px;background:#2A2724;border:1px solid #3C3833;border-radius:10px;padding:3px}
.zoom button{width:30px;height:28px;border:0;background:transparent;color:#CFC9BD;font-size:17px;cursor:pointer;border-radius:7px}
.zoom button:hover{background:#38342F}
.zoom .fit{width:auto;padding:0 12px;font-size:12px;font-weight:600;letter-spacing:.5px}
.hint{position:fixed;bottom:16px;left:50%;transform:translateX(-50%);z-index:50;font-size:11.5px;color:#7A736A;
  background:rgba(24,22,21,.8);padding:6px 14px;border-radius:20px;border:1px solid #38342F}
#vp{position:absolute;inset:58px 0 0 0;overflow:hidden;cursor:grab}
#vp.drag{cursor:grabbing}
#world{position:absolute;top:0;left:0;transform-origin:0 0;will-change:transform}
.board{position:relative;margin:120px 160px}
.glabel{position:absolute;top:-96px;left:0;max-width:760px}
.glabel h2{font-size:14px;font-weight:600;letter-spacing:2px;text-transform:uppercase;color:#EDE9DF}
.glabel p{font-size:12.5px;color:#8C857A;margin-top:7px;line-height:1.5}
.glabel .count{display:inline-block;margin-top:8px;font-size:10.5px;font-weight:600;letter-spacing:1px;color:#6E675E;text-transform:uppercase}
.edges{position:absolute;top:0;left:0;pointer-events:none;overflow:visible}
.edge{fill:none;stroke:#5C6B64;stroke-width:2.5;marker-end:url(#arw)}
.elabel rect{fill:#2A2724;stroke:#4A5450}
.elabel text{fill:#B7C3BD;font-size:11px;font-weight:600;font-family:'Space Grotesk',sans-serif}
.node{position:absolute;margin:0}
.phone{border-radius:34px;overflow:hidden;background:#000;box-shadow:0 16px 40px rgba(0,0,0,.5);border:1px solid #000;line-height:0}
.phone img{width:100%;display:block}
figcaption{margin-top:12px}
figcaption b{display:block;font-size:14px;font-weight:600;color:#fff}
figcaption span{display:block;font-size:11.5px;color:#948D82;margin-top:5px;line-height:1.45}

/* --- Anotaciones (FER-927) --- */
#annotate-btn{display:flex;align-items:center;gap:6px;height:34px;padding:0 14px;border-radius:10px;
  border:1px solid #3C3833;background:#2A2724;color:#CFC9BD;font-size:12px;font-weight:600;cursor:pointer}
#annotate-btn:hover{background:#38342F}
#annotate-btn.on{background:#0C8F62;border-color:#0C8F62;color:#fff}
body.annotating #vp{cursor:crosshair}
body.annotating .node{cursor:crosshair}
.pin{position:absolute;width:22px;height:22px;margin-left:-11px;margin-top:-11px;border-radius:50%;
  background:#0C8F62;color:#fff;font-size:11px;font-weight:700;display:flex;align-items:center;justify-content:center;
  box-shadow:0 3px 8px rgba(0,0,0,.45),0 0 0 2px rgba(255,255,255,.15);cursor:pointer;z-index:5}
.pin:hover{transform:scale(1.12)}
.pin .pin-note{display:none;position:absolute;left:26px;top:-6px;min-width:160px;max-width:240px;
  background:#2A2724;border:1px solid #38342F;border-radius:8px;padding:8px 10px;font-size:11.5px;
  line-height:1.4;color:#EDE9DF;box-shadow:0 8px 24px rgba(0,0,0,.5);z-index:6;white-space:normal}
.pin:hover .pin-note,.pin.open .pin-note{display:block}
.pin .pin-note button{margin-top:6px;background:transparent;border:1px solid #4A443D;color:#B7C3BD;
  font-size:10.5px;border-radius:6px;padding:2px 8px;cursor:pointer}

#annot-panel{position:fixed;top:58px;right:0;bottom:0;width:280px;z-index:45;background:rgba(24,22,21,.94);
  border-left:1px solid #38342F;backdrop-filter:blur(10px);display:flex;flex-direction:column;
  transform:translateX(100%);transition:transform .18s ease}
#annot-panel.open{transform:translateX(0)}
#annot-panel .ap-head{padding:14px 16px;border-bottom:1px solid #38342F;display:flex;align-items:center;gap:8px}
#annot-panel .ap-head h3{font-size:12px;font-weight:700;letter-spacing:1px;text-transform:uppercase;color:#EDE9DF;flex:1}
#annot-panel .ap-head button{background:transparent;border:0;color:#8C857A;font-size:16px;cursor:pointer}
#annot-list{flex:1;overflow:auto;padding:6px 10px}
.ap-item{padding:9px 8px;border-bottom:1px solid #302C28;font-size:11.5px;color:#CFC9BD}
.ap-item b{color:#fff;font-size:11px}
.ap-item .ap-state{display:block;color:#0C8F62;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.4px;margin-bottom:3px}
.ap-item .ap-head{display:flex;align-items:center;gap:8px}
.ap-item .ap-head .ap-state{flex:1;margin-bottom:0}
.ap-item .ap-del{background:transparent;border:0;color:#948D82;cursor:pointer;font-size:14px;order:2}
.ap-item .ap-note{width:100%;margin-top:7px;background:#1E1C1B;border:1px solid #3C3833;border-radius:7px;
  padding:7px 9px;color:#EDE9DF;font-size:11.5px;font-family:inherit;outline:none}
.ap-item .ap-note:focus{border-color:#0C8F62}
#annot-panel .ap-actions{padding:10px 14px;border-top:1px solid #38342F;display:flex;gap:8px}
#annot-panel .ap-actions button{flex:1;background:#2A2724;border:1px solid #3C3833;color:#CFC9BD;
  border-radius:8px;padding:8px 6px;font-size:11px;font-weight:600;cursor:pointer}
#annot-panel .ap-actions button:hover{background:#38342F}
#annot-toggle-tab{position:fixed;top:70px;right:0;z-index:44;background:#2A2724;border:1px solid #38342F;
  border-right:0;border-radius:8px 0 0 8px;color:#CFC9BD;font-size:11px;padding:8px 6px;cursor:pointer;writing-mode:vertical-rl}
"""

PANZOOM_JS = """
const vp=document.getElementById('vp'),world=document.getElementById('world');
let s=0.62,tx=80,ty=40,down=false,px=0,py=0,movedPx=0;
function apply(){world.style.transform=`translate(${tx}px,${ty}px) scale(${s})`}
function zoomAt(cx,cy,ns){ns=Math.min(2.2,Math.max(0.12,ns));const wx=(cx-tx)/s,wy=(cy-ty)/s;s=ns;tx=cx-wx*s;ty=cy-wy*s;apply()}
vp.addEventListener('wheel',e=>{e.preventDefault();const r=vp.getBoundingClientRect();
  if(e.ctrlKey||e.metaKey){zoomAt(e.clientX-r.left,e.clientY-r.top,s*(e.deltaY<0?1.1:0.9))}
  else{tx-=e.deltaX;ty-=e.deltaY;apply()}},{passive:false});
vp.addEventListener('pointerdown',e=>{
  // En modo Anotar, un pointerdown sobre un frame es para clavar un pin (lo maneja ANNOT_JS en el
  // node), NO para hacer pan — no arranques el arrastre del lienzo.
  if(document.body.classList.contains('annotating')&&e.target.closest('.node'))return;
  down=true;px=e.clientX;py=e.clientY;movedPx=0;vp.classList.add('drag');vp.setPointerCapture(e.pointerId)});
vp.addEventListener('pointermove',e=>{if(!down)return;const dx=e.clientX-px,dy=e.clientY-py;movedPx+=Math.abs(dx)+Math.abs(dy);
  tx+=dx;ty+=dy;px=e.clientX;py=e.clientY;apply()});
vp.addEventListener('pointerup',e=>{down=false;vp.classList.remove('drag')});
function fit(){const r=vp.getBoundingClientRect();
  const cw=world.scrollWidth,ch=world.scrollHeight;
  // Guard contra la carrera de layout: si el viewport o el mundo aún miden 0 (fit disparado antes
  // de que el navegador termine el layout), reintenta en el próximo frame en vez de fijar scale(0).
  if(!r.width||!r.height||!cw||!ch){return requestAnimationFrame(fit)}
  s=Math.max(0.12,Math.min(r.width/cw,r.height/ch)*0.92);
  tx=(r.width-cw*s)/2;ty=(r.height-ch*s)/2;apply()}
document.getElementById('zin').onclick=()=>{const r=vp.getBoundingClientRect();zoomAt(r.width/2,r.height/2,s*1.2)};
document.getElementById('zout').onclick=()=>{const r=vp.getBoundingClientRect();zoomAt(r.width/2,r.height/2,s*0.83)};
document.getElementById('fit').onclick=fit;
window.addEventListener('resize',fit);
window.addEventListener('load',fit);
if(document.readyState==='complete')fit();
apply();
"""

ANNOT_JS = """
(function(){
  const STORAGE_KEY='appmap-annotations';
  let annotating=false;
  let dragStart=null; // {x,y} en pointerdown sobre un node, para distinguir clic de arrastre
  const btn=document.getElementById('annotate-btn');
  const panel=document.getElementById('annot-panel');
  const tab=document.getElementById('annot-toggle-tab');
  const list=document.getElementById('annot-list');
  const copyBtn=document.getElementById('annot-copy');
  const clearBtn=document.getElementById('annot-clear');
  const closeBtn=document.getElementById('annot-close');

  function load(){try{return JSON.parse(localStorage.getItem(STORAGE_KEY))||[]}catch(e){return []}}
  function save(list){localStorage.setItem(STORAGE_KEY,JSON.stringify(list))}
  let annots=load();

  function nextId(){return annots.reduce((m,a)=>Math.max(m,a.id),0)+1}

  function renderPins(){
    document.querySelectorAll('.pin').forEach(p=>p.remove());
    annots.forEach(a=>{
      const node=document.querySelector(`.node[data-state="${CSS.escape(a.state)}"]`);
      if(!node) return;
      const pin=document.createElement('div');
      pin.className='pin';
      pin.style.left=(a.xPct*100)+'%';
      pin.style.top=(a.yPct*100)+'%';
      pin.textContent=a.id;
      const note=document.createElement('div');
      note.className='pin-note';
      note.innerHTML=`<div>${a.note.replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]))}</div>`;
      const delBtn=document.createElement('button');
      delBtn.textContent='Borrar';
      delBtn.onclick=(e)=>{e.stopPropagation();removeAnnot(a.id)};
      note.appendChild(delBtn);
      pin.appendChild(note);
      pin.addEventListener('click',(e)=>{e.stopPropagation();pin.classList.toggle('open')});
      node.appendChild(pin);
    });
  }

  function renderList(){
    list.innerHTML='';
    if(annots.length===0){list.innerHTML='<div class="ap-item" style="color:#6E675E">Sin anotaciones aún. Activa «✎ Anotar» y haz clic sobre un frame.</div>';return}
    annots.forEach(a=>{
      const row=document.createElement('div');
      row.className='ap-item';
      row.innerHTML=`<div class="ap-head"><button class="ap-del" title="Borrar">×</button><span class="ap-state">${a.id} · ${a.state}</span></div>`;
      const inp=document.createElement('input');
      inp.className='ap-note';inp.value=a.note;inp.placeholder='escribe la instrucción… («sube esto 2pt»)';
      inp.addEventListener('input',()=>{a.note=inp.value;save(annots);renderPins()});
      row.appendChild(inp);
      row.querySelector('.ap-del').onclick=()=>removeAnnot(a.id);
      list.appendChild(row);
    });
  }

  function renderAll(){renderPins();renderList()}

  function removeAnnot(id){annots=annots.filter(a=>a.id!==id);save(annots);renderAll()}

  // Clic sobre un frame → cae el pin de inmediato (nota vacía); la instrucción se escribe en el
  // panel (input inline). Sin prompt() bloqueante — mejor UX y funciona en cualquier navegador.
  function addAnnot(state,xPct,yPct){
    annots.push({id:nextId(),state,xPct,yPct,note:''});
    save(annots);renderAll();
    panel.classList.add('open');
    requestAnimationFrame(()=>{const inp=list.querySelector('.ap-item:last-child .ap-note');if(inp)inp.focus()});
  }

  btn.addEventListener('click',()=>{
    annotating=!annotating;
    document.body.classList.toggle('annotating',annotating);
    btn.classList.toggle('on',annotating);
    btn.textContent=annotating?'✎ Anotando…':'✎ Anotar';
  });

  document.querySelectorAll('.node').forEach(node=>{
    node.addEventListener('pointerdown',(e)=>{
      if(!annotating) return;
      dragStart={x:e.clientX,y:e.clientY,node};
    });
    node.addEventListener('pointerup',(e)=>{
      if(!annotating||!dragStart) return;
      const moved=Math.abs(e.clientX-dragStart.x)+Math.abs(e.clientY-dragStart.y);
      dragStart=null;
      if(moved>=5) return; // fue un drag, no un clic
      if(e.target.closest('.pin')) return;
      const r=node.getBoundingClientRect();
      const xPct=(e.clientX-r.left)/r.width, yPct=(e.clientY-r.top)/r.height;
      addAnnot(node.dataset.state,xPct,yPct);
    });
  });
  // (El pan de #vp ya se abstiene solo cuando anotas sobre un node — ver PANZOOM_JS.)

  tab.addEventListener('click',()=>panel.classList.toggle('open'));
  closeBtn.addEventListener('click',()=>panel.classList.remove('open'));
  clearBtn.addEventListener('click',()=>{
    if(annots.length===0) return;
    if(!confirm('¿Borrar todas las anotaciones?')) return;
    annots=[];save(annots);renderAll();
  });
  copyBtn.addEventListener('click',()=>{
    const lines=[`# Anotaciones del mapa (${annots.length})`];
    annots.forEach(a=>lines.push(`[${a.state}] @ (${Math.round(a.xPct*100)}%, ${Math.round(a.yPct*100)}%) — "${a.note}"`));
    const text=lines.join('\\n');
    if(navigator.clipboard && navigator.clipboard.writeText){navigator.clipboard.writeText(text)}
    copyBtn.textContent='¡Copiado!';setTimeout(()=>copyBtn.textContent='⧉ Copiar para Claude',1400);
  });

  renderAll();
})();
"""

def render(src_of, font_css="", total_note=""):
    boards = "".join(group_html(g, src_of) for g in MAP)
    total = sum(len(g["nodes"]) for g in MAP)
    return f"""<!doctype html><html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Cénit · Mapa de estados</title>{font_css}
<style>{STYLE}</style></head><body>
<div class="topbar"><h1>Cénit · Mapa de estados</h1>
<span class="sub">capturas reales del simulador · {total} estados{total_note}</span>
<span class="spacer"></span>
<button id="annotate-btn">✎ Anotar</button>
<div class="zoom"><button id="zout">−</button><button id="zin">+</button><button class="fit" id="fit">Ajustar</button></div></div>
<div id="vp"><div id="world">{boards}</div></div>
<div class="hint">Arrastra para mover · rueda para desplazar · ⌘/Ctrl + rueda para zoom</div>
<button id="annot-toggle-tab">Anotaciones</button>
<div id="annot-panel">
  <div class="ap-head"><h3>Anotaciones</h3><button id="annot-close">×</button></div>
  <div id="annot-list"></div>
  <div class="ap-actions">
    <button id="annot-copy">⧉ Copiar para Claude</button>
    <button id="annot-clear">Borrar todo</button>
  </div>
</div>
<script>{PANZOOM_JS}</script>
<script>{ANNOT_JS}</script></body></html>"""

SHOT_W = 800   # ancho al que se reescalan las capturas para el repo/muro (nítido, ligero)

# COMPONENTS y el grupo «Componentes» ya salen de load_manifests() (componentes.json) al importar el
# módulo — mismo contrato `[(nombre, familia_de_pieza), …]` que consume build-galeria-artifact.py.

def sync_shots(staging_dir):
    """Copia+reescala los PNG que el harness dejó en staging_dir a docs/appmap/shots/ a SHOT_W de
    ancho. El harness ya escribe el nombre de muro de cada frame (ver `_frame_png`), así que aquí no
    hay remapeo: recorre los nodos del manifiesto (NODES) y copia cada frame. Devuelve (copiados, faltantes)."""
    import shutil, subprocess
    dst = os.path.join(APPMAP, "shots"); os.makedirs(dst, exist_ok=True)
    copied, missing = [], []
    for node in NODES:
        for png in node["pngs"]:
            src = os.path.join(staging_dir, png)
            if not os.path.exists(src):
                missing.append(png); continue
            out = os.path.join(dst, png)
            shutil.copyfile(src, out)
            subprocess.run(["sips", "--resampleWidth", str(SHOT_W), out],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            copied.append(png)
    print(f"sync_shots: {len(copied)} copiados a {SHOT_W}px" + (f" · faltan {missing}" if missing else ""))
    return copied, missing

def build_served():
    css=('<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
         '<link href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@400;500;600;700&display=swap" rel="stylesheet">')
    doc=render(lambda png: f"shots/{png}", css)
    open(os.path.join(APPMAP,"index.html"),"w").write(doc)
    print("escrito docs/appmap/index.html ·", sum(len(g['nodes']) for g in MAP),"estados")

if __name__ == "__main__":
    build_served()
