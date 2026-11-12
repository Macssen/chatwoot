import { FEATURE_FLAGS } from '../../../../featureFlags';
import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import CannedHome from './Index.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/canned-responses'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'canned_responses_index',
          meta: {
            featureFlag: FEATURE_FLAGS.CANNED_RESPONSES,
            permissions: ['administrator', 'agent', 'custom_role'],
          },
          component: CannedHome,
        },
      ],
    },
    {
      path: frontendURL('accounts/:accountId/settings/canned-response'),
      redirect: to => ({ name: 'canned_responses_index', params: to.params }),
    },
    {
      path: frontendURL('accounts/:accountId/settings/canned-response/list'),
      redirect: to => ({ name: 'canned_responses_index', params: to.params }),
    },
  ],
};
