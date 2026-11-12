import { createRouter, createMemoryHistory } from 'vue-router';
import cannedRoutes from '../canned.routes';

// The real components pull in the whole dashboard route tree, which imports
// canned.routes back before it is initialized.
vi.mock('../../SettingsWrapper.vue', () => ({
  default: { render: () => null },
}));
vi.mock('../Index.vue', () => ({ default: { render: () => null } }));

const buildRouter = () =>
  createRouter({ history: createMemoryHistory(), routes: cannedRoutes.routes });

describe('canned.routes', () => {
  it('exposes the canned responses page outside settings for every role', () => {
    const route = buildRouter().resolve({
      name: 'canned_responses_index',
      params: { accountId: 1 },
    });

    expect(route.path).toBe('/app/accounts/1/canned-responses');
    expect(route.meta.permissions).toEqual([
      'administrator',
      'agent',
      'custom_role',
    ]);
    expect(route.meta.featureFlag).toBe('canned_responses');
  });

  it.each([
    '/app/accounts/7/settings/canned-response',
    '/app/accounts/7/settings/canned-response/list',
  ])('redirects %s to canned_responses_index', async oldPath => {
    const router = buildRouter();

    await router.push(oldPath);

    expect(router.currentRoute.value.name).toBe('canned_responses_index');
    expect(router.currentRoute.value.params.accountId).toBe('7');
  });

  it('no longer registers the canned_list route', () => {
    expect(buildRouter().hasRoute('canned_list')).toBe(false);
  });
});
