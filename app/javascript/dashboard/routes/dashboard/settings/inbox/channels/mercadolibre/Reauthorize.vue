<script setup>
import { ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import InboxReconnectionRequired from '../../components/InboxReconnectionRequired.vue';
import mercadolibreClient from 'dashboard/api/channel/mercadolibreClient';

const props = defineProps({
  inbox: {
    type: Object,
    required: true,
  },
});

const { t } = useI18n();

const isRequestingAuthorization = ref(false);

async function requestAuthorization() {
  try {
    isRequestingAuthorization.value = true;
    const {
      data: { url },
    } = await mercadolibreClient.generateAuthorization({
      flow: props.inbox.mercadolibre_flow,
    });
    window.location.href = url;
  } catch (error) {
    useAlert(t('INBOX_MGMT.ADD.MERCADOLIBRE.ERROR_MESSAGE'));
  } finally {
    isRequestingAuthorization.value = false;
  }
}
</script>

<template>
  <InboxReconnectionRequired class="mx-6" @reauthorize="requestAuthorization" />
</template>
