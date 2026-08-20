# Feature bot-first — voice agent Shell sobre el canal telefónico

Estado: **diseño cerrado, esperando OK de Alex para implementar**. Acordado entre
esta sesión (fork) y la sesión `shell-bot` (repo `/Users/alex/macssen/shell`,
voice agent con OpenAI Realtime / gpt-realtime). Fecha: 05/08/2026.

La demo web `shelldemo.macssen.com` fue dada de baja: el canal telefónico de
`agentes.macssen.com` (este fork) es el único objetivo.

## Objetivo

Que una llamada entrante a un inbox de voz marcado *bot-first* sea atendida
primero por el agente de voz Shell (OpenAI Realtime), con escalado a agente
humano cuando el bot lo decide. Hoy el canal de voz solo contempla agentes
humanos (ver `docs/voice-channel-oss.md`); este feature agrega el punto de
entrada para el bot, que **no existe** en el código actual.

## Contrato del canal existente (base, ya en prod)

- Twilio Programmable Voice, modelo de **conferencias**. El audio vive en Twilio,
  nunca pasa por Chatwoot.
- Inbound: el número Twilio apunta su voice_url a
  `POST /twilio/voice/call/:phone` (`app/controllers/twilio/voice_controller.rb`).
  `Voice::InboundCallBuilder` crea el `Call` + la conversación y el cliente queda
  en hold (`start_conference_on_enter=false`) hasta que entra el agente humano.
- Imagen en prod (`agentes.macssen.com`): `roles-4.15.1-r4`, salió de `main`.
  **Verificado**: el backend de voz (`e790ed381 feat(voice)`) es anterior al fix
  de r4 en `main` y los 27 archivos de voice están en el árbol → el código de voz
  está desplegado.

## Arquitectura acordada (conference-scoped)

El bot es **un participante más de la misma conferencia** que el cliente. Esto
hace barato el ring-a-humano y el cierre limpio (ver Handoff). Descartado el
modelo 1:1 bot↔cliente con transferencia.

### 1. Lado fork (este repo) — a implementar

- **Marca por inbox**: bandera `bot_first` en `provider_config` (jsonb) de
  `Channel::TwilioSms`. Mismo patrón que `inbound_calls_enabled`. Sin migración.
- **`render_inbound_leg`** (en `Twilio::VoiceController`): si el inbox es
  bot-first, tras crear el `Call` con `InboundCallBuilder`:
  - el cliente entra a la conferencia con `start_conference_on_enter=true` (sin
    hold), con un **`waitUrl`** (tono/mensaje corto) que cubre los 1-3 s hasta
    que el bot conecta.
  - el fork dispara la **pata SIP del bot** hacia la conferencia vía **Twilio
    REST Conference Participants API** (no TwiML del cliente), guardando el
    **participant SID** del bot (se necesita para removerlo en el handoff).
- **URI SIP del bot**: `sip:{openai_project_id}@sip.api.openai.com;transport=tls`,
  media SRTP. El user part es el project id de OpenAI (`proj_...`). Se guarda en
  `provider_config` del inbox como `openai_project_id`.
- **X-headers en la URI SIP** (Twilio los embebe como
  `sip:...;transport=tls?X-Foo=bar`; OpenAI los entrega en `sip_headers` del
  webhook `realtime.call.incoming`):
  - `X-CW-Account-Id`
  - `X-CW-Conversation-Id`
  - `X-CW-Inbox-Id`
  - `X-CW-Auth` — secreto compartido, en `provider_config` del inbox (lado fork)
    y env var (lado shell-bot). **Nunca en código ni commits** (repo público).
- **Timeout + fallback (criterio de aceptación de v1, no opcional)**: si la pata
  del bot no entra a la conferencia en N s (arrancar con N=8, ajustable) o falla
  al dialear, el fork cae solo al comportamiento actual: hold + ring a humanos.
  Sin esto el peor caso es un cliente en conferencia muda para siempre; con esto
  el peor caso es "atiende un humano como hoy".
  - El fallback debe distinguir **"bot no conectó"** de **"bot conectó y se cortó
    por handoff"** (si no, un handoff normal dispararía el fallback). Se resuelve
    con el estado del `Call`. Asunto del fork, no cambia el contrato de shell-bot.
  - `waitUrl` y fallback viven en el mismo render del TwiML del cliente → no
    agregan superficie para shell-bot.
- **Endpoint de handoff bot→humano**:
  - `POST /api/v1/accounts/:account_id/conversations/:id/handoff`
  - Auth: header `api_access_token` (token del agent bot). Mismo esquema que las
    escrituras de mensajes.
  - Payload mínimo: `{ reason: string }`. El call/conversation sale del path.
  - Efecto: (1) ring a los agentes del inbox reusando el mismo broadcast de cable
    que hoy usa el inbound; (2) remover la pata SIP del bot de la conferencia vía
    Twilio REST (Conference Participant delete con el participant SID guardado);
    (3) nota en la conversación con el `reason`.
  - Respuesta: `200 { status: 'ringing_agents' }`.

### 2. Lado shell-bot (repo `/Users/alex/macssen/shell`) — no es este repo

- Handler del webhook `realtime.call.incoming` de OpenAI: valida la firma con el
  webhook secret del proyecto **y** `X-CW-Auth` (rechaza el INVITE si no matchea,
  no acepta la sesión); acepta la llamada SIP y configura la sesión (prompt
  rioplatense + tools `buscar_en_kb` / `escalar_a_humano` / `crear_ticket`, KB de
  17 entradas).
- Ejecución server-side de tools por el WebSocket sideband de Realtime.
- Transcripción y notas a la conversación vía API REST de Chatwoot con token de
  agent bot. `escalar_a_humano` invoca el endpoint de handoff del fork.

### 3. Cierre de la sesión Realtime (resuelto, cero superficie nueva)

Cuando el fork remueve la pata SIP del bot (handoff), Twilio manda **BYE** al
endpoint SIP de OpenAI y la sesión Realtime cierra sola. shell-bot no necesita
escuchar ningún evento del fork: **el corte de la pata ES la señal**. La
telemetría del motivo sale del `reason` ya escrito por API REST.

## Auth (esquema, sin valores)

- API REST de Chatwoot (escritura + handoff): header `api_access_token`.
- INVITE SIP fork→OpenAI: doble validación del lado shell-bot — firma del webhook
  del proyecto OpenAI + `X-CW-Auth` compartido. El From no se valida (no es
  autenticable).
- Webhooks de voz de Twilio hacia el fork: validación por `AccountSid` del canal
  (la firma `X-Twilio-Signature` sigue pendiente, ver `docs/voice-channel-oss.md`).

## Prerrequisitos (dependen de Alex, bloquean la implementación)

- [ ] **Flag `channel_voice`** habilitado en la cuenta objetivo (super admin, o
      `account.enable_features!('channel_voice')`). **No verificado**: el
      `kubectl exec` a prod para leer la DB fue bloqueado por el clasificador de
      permisos. No darlo por hecho.
- [ ] **`OPENAI_API_KEY`** vigente con acceso a `gpt-realtime` (lado shell-bot).
- [ ] **OK de arquitectura de Alex** antes de escribir código.

## Al implementar (recordatorios de este repo)

- Specs explícitas (CLAUDE.md las pide; van bajo `spec/`, mirror del layout OSS;
  si toca enterprise, `spec/enterprise`).
- Chequear `enterprise/` por overrides antes de tocar core (canal de voz es MIT,
  fuera de enterprise, pero el endpoint nuevo pasa por policies/controllers).
- Repo **público**: nada de secretos ni detalles de seguridad en commits/issues.
- i18n: solo `en.yml` / `en.json`.
