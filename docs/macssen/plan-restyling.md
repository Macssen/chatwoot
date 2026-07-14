# Plan de Restyling — Chatwoot → Macssen

Fecha: 2026-07-14
Estado: pendiente de ejecución

## Objetivo

Que ningún usuario final vea "Chatwoot" en el producto (dashboard, widget, emails, favicon),
con identidad Macssen y tema visual neutro, **sin** renombrar internals del código.

## Principio rector (no negociable)

**No hacer find-replace masivo de "chatwoot" en el código.** Hay ~4.311 ocurrencias en
1.333 archivos solo en `app/`, `lib/` y `config/` (módulos Ruby como `ChatwootApp`,
`ChatwootHub`, claves de config, imports, specs). Renombrar internals rompe cada rebase
con upstream, y este fork vive de seguir a `chatwoot/develop`. Se rebrandea únicamente
la capa visible al usuario.

## Fase 1 — InstallationConfig (una tarde, cero deuda de merge)

Configurar vía super admin console o `rails console` en producción:

| Config | Valor |
|---|---|
| `INSTALLATION_NAME` | `Macssen` |
| `BRAND_NAME` | `Macssen` |
| `LOGO` | `/brand-assets/logo.svg` (SVG propio) |
| `LOGO_DARK` | `/brand-assets/logo_dark.svg` (SVG propio) |
| `LOGO_THUMBNAIL` | `/brand-assets/logo_thumbnail.svg` (512×512, es el favicon) |
| `BRAND_URL` | `https://macssen.com` (aparece en "Powered by" de emails) |
| `WIDGET_BRAND_URL` | `https://macssen.com` (aparece en "Powered by" del widget) |
| `TERMS_URL` | URL de términos de Macssen |
| `PRIVACY_URL` | URL de privacidad de Macssen |
| `DISPLAY_MANIFEST` | `false` (mata favicons y metadata de Chatwoot) |

## Fase 2 — Assets

- Reemplazar los SVGs en `public/brand-assets/` (`logo.svg`, `logo_dark.svg`,
  `logo_thumbnail.svg`) por versiones Macssen. Commit en el fork.

## Fase 3 — Strings hardcodeados visibles

- Inventariar los "Chatwoot" que quedan visibles en UI que las configs no cubren
  (buscar en `en.json` / `en.yml` y templates).
- Parchear usando `replaceInstallationName` de `shared/composables/useBranding`
  (patrón ya adoptado en el fork) — **no** hardcodear "Macssen" en los strings.
- Solo tocar `en.json` y `en.yml`; el resto de idiomas es de la comunidad.

## Fase 4 — Tema de colores

Decisión: **NO blanco y negro puro.** Una inbox de soporte depende del color para
estados (abierta/resuelta, agente online, errores, SLA, badges de no-leído);
monocromo total destruye la jerarquía visual.

Enfoque: paleta neutra (grises) + un solo color de acento, conservando los
semánticos (rojo/verde/amarillo).

- Tocar únicamente tokens: paleta `woot` en `tailwind.config.js` y las variables
  CSS de design tokens. Nunca clases sueltas en componentes.
- Cambio acotado y mantenible en rebases.

## Fase 5 — Cortar el cordón

- `DISABLE_TELEMETRY=true` en producción: la instancia deja de reportar a
  `hub.2.chatwoot.com` (`lib/chatwoot_hub.rb`).
- Seguro contra reset de branding: si algún día se corre build enterprise sin plan
  pago, `enterprise/config/premium_installation_config.yml` resetea el branding a
  "Chatwoot" en cada check de versiones. Hoy no aplica (`DISABLE_ENTERPRISE`), pero
  conviene vaciar ese YAML en el fork como seguro.

## Límites legales

- `LICENSE` queda intacta: MIT exige conservar "Copyright (c) Chatwoot Inc.".
  Rebranding de producto sí; borrar atribución de licencia no.
- `enterprise/` es licencia propietaria: el rebranding no lo blanquea. Se mantiene
  deshabilitado (`DISABLE_ENTERPRISE`).

## Flujo de ramas del fork

- `develop` — espejo de `upstream/develop` (chatwoot/chatwoot). No se commitea acá.
- `main` — rama de integración Macssen: develop + features propias (voice, roles, …).
  Es lo que se despliega.
- `feat/*` — una rama por feature, partiendo de `main` (o `develop` si es candidata
  a PR upstream).

Merge de una feature a main (ejemplo actual, `feat/roles`):

```bash
git checkout main
git merge --ff-only feat/roles   # o --no-ff si se quiere merge commit explícito
git push origin main             # main aún no existe en origin; esto la publica
```

Sync con upstream:

```bash
git fetch upstream
git checkout develop && git merge --ff-only upstream/develop
git checkout main && git merge develop   # resolver conflictos de las features propias acá
```

El trabajo de restyling se hace en una rama `feat/restyling` partiendo de `main`.
