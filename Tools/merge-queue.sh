#!/bin/zsh
# Cola de merge de /orquesta: por PR en orden, espera CI, rebasa si hay conflicto (CHANGELOG y
# docs/DECISIONS.md por unión: se conservan ambos lados), mergea plano (--squash --delete-branch) con reintentos acotados y confirma con el estado real; auto-merge está deshabilitado en el repo (2026-09-15).
# Uso: nohup Tools/merge-queue.sh <PR> [<PR>...] > cola.log 2>&1 &   (nunca en foreground: Bash lo mata a los 600 s)
set -u
ROOT=~/code/noop
UNION_FILES='CHANGELOG.md|docs/DECISIONS.md'
union_file() { # $1 archivo con marcadores de conflicto
  python3 - "$1" <<'PY'
import re, sys
p=sys.argv[1]; s=open(p).read()
s=re.sub(r'<<<<<<< [^\n]*\n(.*?)=======\n(.*?)>>>>>>> [^\n]*\n', lambda m: m.group(1)+m.group(2), s, flags=re.S)
open(p,'w').write(s)
PY
}
close_issue() { # $1 PR — cierra el issue en Multica SOLO tras confirmar state==MERGED (nunca incondicional).
  # Dueño del cierre: evita que un script de fondo aparte corra `multica done` a ciegas tras un merge que falló (retro FER-428).
  local N=$1 ID
  ID=$(gh pr view $N --json body -q .body | grep -ioE 'Closes FER-[0-9]+' | grep -oiE 'FER-[0-9]+' | head -1)
  [ -n "$ID" ] || { echo "PR $N: sin 'Closes FER-NN' en el cuerpo; no cierro issue"; return 0; }
  if multica issue status "$ID" done >/dev/null 2>&1; then echo "issue $ID -> done"; else echo "PR $N: no pude cerrar $ID en Multica"; fi
}
rebase_pr() { # $1 branch
  local B=$1 W=$ROOT/.claude/worktrees/dir-$1
  git -C $ROOT worktree add -q "$W" "$B" 2>/dev/null || git -C $ROOT worktree add -q --detach "$W" "origin/$B" 2>/dev/null || true
  [ -d "$W" ] || { echo "no pude crear worktree para $B (¿rama en uso?)"; return 1; }
  ( cd "$W" || exit 1; git fetch -q origin && git reset -q --hard "origin/$B" && git rebase origin/iOS >/dev/null 2>&1
    while git status --short | grep -q "^UU"; do
      if git status --short | grep "^UU" | grep -qvE "$UNION_FILES"; then echo "CONFLICTO NO TRIVIAL en $B: $(git status --short | grep '^UU')"; git rebase --abort; return 1; fi
      for f in $(git status --short | grep "^UU" | awk '{print $2}'); do union_file "$f"; git add "$f"; done
      GIT_EDITOR=true git rebase --continue >/dev/null 2>&1
    done
    git push -q --force-with-lease origin "HEAD:$B" && echo "rebasado $B" )
}
for N in "$@"; do
  B=$(gh pr view $N --json headRefName -q .headRefName)
  for attempt in 1 2 3; do
    sleep 90
    until [ "$(gh pr checks $N --json bucket -q '[.[]|select(.bucket=="pending")]|length' 2>/dev/null)" = "0" ] && [ "$(gh pr checks $N --json bucket -q 'length' 2>/dev/null)" -gt 3 ]; do sleep 45; done
    if [ "$(gh pr checks $N --json bucket -q '[.[]|select(.bucket=="fail" or .bucket=="cancel")]|length')" != "0" ]; then echo "PR $N CI ROJA:"; gh pr checks $N --json name,bucket -q '.[]|select(.bucket!="pass")|.name+" "+.bucket'; break; fi
    M=$(gh pr view $N --json mergeable -q .mergeable)
    if [ "$M" = "CONFLICTING" ]; then rebase_pr "$B" || break; continue; fi
    if gh pr merge $N --squash --delete-branch >/dev/null 2>&1; then sleep 5; S=$(gh pr view $N --json state -q .state); echo "PR $N $S"; [ "$S" = "MERGED" ] && close_issue $N; break; fi
    # Primer merge plano falló (checks aún settling o mergeStateStatus no CLEAN): reintentar acotado (auto-merge deshabilitado).
    for intento in $(seq 1 ${MERGE_REINTENTOS:-10}); do
      sleep 60
      pend=$(gh pr checks $N --json bucket -q '[.[]|select(.bucket=="pending")]|length' 2>/dev/null)
      [ "$pend" = "0" ] || continue
      gh pr merge $N --squash --delete-branch >/dev/null 2>&1 || true
      S=$(gh pr view $N --json state -q .state)
      if [ "$S" = "MERGED" ]; then echo "PR $N MERGED (intento $intento)"; close_issue $N; break 2; fi
    done
    echo "PR $N NO MERGEADO tras ${MERGE_REINTENTOS:-10} intentos: $(gh pr view $N --json mergeStateStatus -q .mergeStateStatus 2>/dev/null)"
    break
  done
  git -C $ROOT worktree remove --force $ROOT/.claude/worktrees/dir-$B 2>/dev/null || true
done
echo COLA-FIN
