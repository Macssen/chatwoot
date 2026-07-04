# Canal de voz (fork Macssen — implementación MIT)

Implementación propia del canal de llamadas de voz sobre el árbol MIT, sin
código de `enterprise/`. Dos transportes:

- **WhatsApp Calling** — WebRTC browser ↔ Meta (Cloud API). Sin costo por
  minuto en llamadas entrantes del cliente; las salientes las factura Meta.
- **Twilio Voice** — número Twilio con modelo de conferencias + Voice JS SDK.
  Cubre PSTN y, vía SIP Trunking / SIP Domains, cualquier línea IP.

## Habilitación

1. Feature flag por cuenta: super admin → cuenta → habilitar `channel_voice`
   (o `account.enable_features!('channel_voice')` en consola).
2. **WhatsApp**: el inbox debe ser provider `whatsapp_cloud`. En la config del
   inbox usar "Enable WhatsApp calling" (activa calling en Meta y re-registra
   el webhook con el campo `calls`).
3. **Twilio**: crear inbox de voz (type `voice`) con `account_sid`,
   `auth_token`, `api_key_sid`, `api_key_secret` y el número. Al activarse se
   aprovisiona una TwiML App y se apuntan los webhooks del número a
   `/twilio/voice/call/:phone`.

## Líneas SIP genéricas (cualquier PBX / troncal IP)

Chatwoot upstream no soporta SIP; acá entra por Twilio:

- **Opción A — Elastic SIP Trunking (origination)**: crear un trunk en Twilio,
  asociar el número Twilio del inbox y configurar el PBX/proveedor para
  enrutar hacia el trunk. Sin cambios de código.
- **Opción B — SIP Domain**: crear un SIP Domain en Twilio
  (`xxx.sip.twilio.com`), permitir la IP del PBX (ACL/credenciales) y setear
  su Voice URL a la URL `/twilio/voice/call/<numero>` del inbox. Los INVITE
  llegan con `From` como URI SIP; el controlador normaliza el caller-id
  (`Twilio::VoiceController#normalized_caller`).

Costo: minutos de Twilio (~US$0.004–0.01/min según dirección/país). No hay
costo por asiento.

## Variables de entorno

- `VOICE_CALL_STUN_URLS` — lista separada por comas de STUN servers para
  WhatsApp WebRTC (default: STUN de Google). **Pendiente**: desplegar
  coturn (TURN) para agentes detrás de NAT simétrico y sumarlo acá cuando
  el modelo soporte TURN con credenciales.
- `FRONTEND_URL` — usado para construir las URLs de webhooks y grabaciones.

## Arquitectura (archivos nuevos/tocados, todos MIT)

- `app/models/call.rb` — modelo Call (tabla `calls`, ya migrada upstream).
- `app/services/voice/*` — builders inbound/outbound, broadcaster de eventos
  de cable (`voice_call.*`), orquestación de conferencias Twilio.
- `app/services/whatsapp/incoming_call_service.rb` — webhooks `field=calls`.
- `app/services/whatsapp/call_service.rb` / `outbound_call_service.rb` —
  acciones de agente y llamadas salientes (con flujo de permiso de llamada).
- `app/services/whatsapp/providers/whatsapp_cloud_service.rb` — Calling API
  de Meta (`/calls`, settings, permission request).
- `app/controllers/api/v1/accounts/whatsapp_calls_controller.rb`,
  `conference_controller.rb`, `contacts/calls_controller.rb`.
- `app/controllers/twilio/voice_controller.rb` — TwiML + status webhooks.
- `app/services/twilio/voice_{webhook_setup,teardown,token}_service.rb`.
- `app/jobs/voice/recording_attachment_job.rb` — descarga grabaciones Twilio.
- `config/routes.rb` — rutas de voz sin gate enterprise.

El frontend (widget de llamadas, WebRTC de WhatsApp, SDK de Twilio) es el
MIT de upstream, sin cambios.

## Limitaciones conocidas

- Grabación de llamadas WhatsApp es client-side (MediaRecorder); si el browser
  crashea antes del upload, se pierde.
- Sin TURN server todavía — llamadas WhatsApp pueden fallar con NAT simétrico.
- La respuesta de permiso de llamada (interactive `call_permission_reply`)
  crea un mensaje vacío en la conversación; no rompe el flujo (el agente
  reintenta la llamada y sale).
- Webhooks de Twilio validan `AccountSid` pero no la firma X-Twilio-Signature
  (hardening pendiente).
- Transcripción (`calls.transcript`) es un placeholder, igual que upstream.

## Build/Deploy

La imagen debe construirse desde este fork **excluyendo `enterprise/`**
(build tipo CE) para no arrastrar código con licencia enterprise. Ver task de
build. El deploy actual (`chatwoot/chatwoot:latest-ce` en OCI k8s) debe pasar
a la imagen propia.
