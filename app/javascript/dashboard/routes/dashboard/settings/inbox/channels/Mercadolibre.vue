<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import mercadolibreClient from 'dashboard/api/channel/mercadolibreClient';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';

const { t } = useI18n();

const app = ref(null);
const appId = ref('');
const appSecret = ref('');
const isEditingApp = ref(false);
const isSavingApp = ref(false);
const flow = ref('pre_sale');
const isRequestingAuthorization = ref(false);
const errorMessage = ref('');

const showAppForm = computed(
  () => app.value && (!app.value.configured || isEditingApp.value)
);

const flows = computed(() => [
  {
    id: 'pre_sale',
    label: t('INBOX_MGMT.ADD.MERCADOLIBRE.FLOWS.PRE_SALE.TITLE'),
    description: t('INBOX_MGMT.ADD.MERCADOLIBRE.FLOWS.PRE_SALE.DESCRIPTION'),
  },
  {
    id: 'post_sale',
    label: t('INBOX_MGMT.ADD.MERCADOLIBRE.FLOWS.POST_SALE.TITLE'),
    description: t('INBOX_MGMT.ADD.MERCADOLIBRE.FLOWS.POST_SALE.DESCRIPTION'),
  },
]);

onMounted(async () => {
  const urlParams = new URLSearchParams(window.location.search);
  errorMessage.value = urlParams.get('error_message') || '';
  // Drop the error params so a reload lets the user try again
  window.history.replaceState({}, document.title, window.location.pathname);

  const { data } = await mercadolibreClient.getApp();
  app.value = data;
  appId.value = data.app_id ? String(data.app_id) : '';
});

const saveApp = async () => {
  isSavingApp.value = true;
  try {
    const { data } = await mercadolibreClient.updateApp({
      app_id: appId.value,
      app_secret: appSecret.value,
    });
    app.value = data;
    appSecret.value = '';
    isEditingApp.value = false;
  } catch (error) {
    useAlert(
      error?.response?.data?.message ||
        t('INBOX_MGMT.ADD.MERCADOLIBRE.APP.SAVE_ERROR')
    );
  } finally {
    isSavingApp.value = false;
  }
};

const requestAuthorization = async () => {
  isRequestingAuthorization.value = true;
  try {
    const {
      data: { url },
    } = await mercadolibreClient.generateAuthorization({ flow: flow.value });
    window.location.href = url;
  } catch (error) {
    isRequestingAuthorization.value = false;
    useAlert(t('INBOX_MGMT.ADD.MERCADOLIBRE.ERROR_MESSAGE'));
  }
};
</script>

<template>
  <div class="h-full p-6 w-full max-w-full flex-shrink-0 flex-grow-0">
    <div
      v-if="app"
      class="flex flex-col gap-6 w-full max-w-2xl mx-auto px-8 py-10 rounded-2xl outline outline-1 outline-n-weak"
    >
      <div>
        <h6 class="text-2xl font-medium">
          {{ $t('INBOX_MGMT.ADD.MERCADOLIBRE.TITLE') }}
        </h6>
        <p class="pt-2 text-sm text-n-slate-11">
          {{ $t('INBOX_MGMT.ADD.MERCADOLIBRE.HELP') }}
        </p>
      </div>

      <p v-if="errorMessage" class="text-sm text-n-ruby-11">
        {{ $t('INBOX_MGMT.ADD.MERCADOLIBRE.ERROR_MESSAGE') }}
        {{ errorMessage }}
      </p>

      <form
        v-if="showAppForm"
        class="flex flex-col gap-4"
        @submit.prevent="saveApp"
      >
        <p class="text-sm text-n-slate-11">
          {{ $t('INBOX_MGMT.ADD.MERCADOLIBRE.APP.HELP') }}
        </p>
        <div class="flex flex-col gap-1 text-sm">
          <span class="text-n-slate-11">
            {{ $t('INBOX_MGMT.ADD.MERCADOLIBRE.APP.REDIRECT_URI') }}
          </span>
          <code class="break-all">{{ app.redirect_uri }}</code>
          <span class="pt-2 text-n-slate-11">
            {{ $t('INBOX_MGMT.ADD.MERCADOLIBRE.APP.NOTIFICATIONS_URL') }}
          </span>
          <code class="break-all">{{ app.notifications_url }}</code>
        </div>
        <Input
          v-model="appId"
          :label="$t('INBOX_MGMT.ADD.MERCADOLIBRE.APP.APP_ID')"
        />
        <Input
          v-model="appSecret"
          type="password"
          :label="$t('INBOX_MGMT.ADD.MERCADOLIBRE.APP.APP_SECRET')"
        />
        <Button
          type="submit"
          :is-loading="isSavingApp"
          :disabled="!appId || !appSecret"
          :label="$t('INBOX_MGMT.ADD.MERCADOLIBRE.APP.SAVE')"
        />
      </form>

      <template v-else>
        <div class="flex items-center justify-between text-sm text-n-slate-11">
          <span>
            {{
              $t('INBOX_MGMT.ADD.MERCADOLIBRE.APP.CONFIGURED', {
                appId: app.app_id,
              })
            }}
          </span>
          <Button
            link
            sm
            :label="$t('INBOX_MGMT.ADD.MERCADOLIBRE.APP.EDIT')"
            @click="isEditingApp = true"
          />
        </div>
        <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <RadioCard
            v-for="item in flows"
            :id="item.id"
            :key="item.id"
            :label="item.label"
            :description="item.description"
            :is-active="flow === item.id"
            @select="flow = item.id"
          />
        </div>
        <Button
          lg
          icon="i-ri-shake-hands-line"
          :is-loading="isRequestingAuthorization"
          :disabled="isRequestingAuthorization"
          :label="$t('INBOX_MGMT.ADD.MERCADOLIBRE.CONNECT')"
          @click="requestAuthorization"
        />
      </template>
    </div>
  </div>
</template>
