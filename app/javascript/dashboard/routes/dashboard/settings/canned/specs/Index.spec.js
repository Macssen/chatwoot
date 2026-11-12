import { mount } from '@vue/test-utils';
import { computed, ref } from 'vue';
import { useStore, useStoreGetters } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import CannedResponseIndex from '../Index.vue';

vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables/useAdmin');
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const CURRENT_USER_ID = 1;

const ownResponse = {
  id: 10,
  short_code: 'own',
  content: 'Own content',
  created_by: { id: CURRENT_USER_ID, name: 'Current User' },
};
const otherResponse = {
  id: 11,
  short_code: 'other',
  content: 'Other content',
  created_by: { id: 2, name: 'Maya Chen' },
};
const ownerlessResponse = {
  id: 12,
  short_code: 'ownerless',
  content: 'Ownerless content',
  created_by: null,
};

const dispatch = vi.fn();

const mountIndex = ({ isAdmin, customRoleId }) => {
  useAdmin.mockReturnValue({ isAdmin: ref(isAdmin) });
  useStore.mockReturnValue({ dispatch });
  useStoreGetters.mockReturnValue({
    getCurrentUserID: computed(() => CURRENT_USER_ID),
    getCurrentCustomRoleId: computed(() => customRoleId),
    getSortedCannedResponses: computed(() => () => [
      ownResponse,
      otherResponse,
      ownerlessResponse,
    ]),
    getUIFlags: computed(() => ({ fetchingList: false })),
  });

  return mount(CannedResponseIndex, {
    global: {
      stubs: {
        SettingsLayout: {
          template:
            '<div><slot name="header" /><slot name="body" /><slot /></div>',
        },
        BaseSettingsHeader: {
          template:
            '<header><slot name="count" /><slot name="actions" /></header>',
        },
        BaseTable: {
          props: ['headers', 'items'],
          template:
            '<table><thead><tr><th v-for="header in headers" :key="header" data-test="header">{{ header }}</th></tr></thead><tbody><slot name="row" :items="items" /></tbody></table>',
        },
        BaseTableRow: {
          props: ['item'],
          template: '<tr :data-row="item.short_code"><slot /></tr>',
        },
        BaseTableCell: { template: '<td><slot /></td>' },
        Button: {
          props: ['label', 'icon', 'isLoading'],
          emits: ['click'],
          template:
            '<button :data-icon="icon" :data-label="label" @click="$emit(\'click\')">{{ label }}</button>',
        },
        Icon: true,
        AddCanned: true,
        EditCanned: true,
        WootDeleteModal: {
          props: ['show', 'onConfirm'],
          template:
            '<div v-if="show" data-test="delete-modal"><button data-test="confirm-delete" @click="onConfirm()" /></div>',
        },
      },
    },
  });
};

const row = (wrapper, shortCode) => wrapper.find(`[data-row="${shortCode}"]`);
const headers = wrapper =>
  wrapper.findAll('[data-test="header"]').map(header => header.text());
const createButton = wrapper => wrapper.find('header [data-label]');
const hasManageButtons = (wrapper, shortCode) =>
  row(wrapper, shortCode).find('[data-icon="i-woot-edit-pen"]').exists() &&
  row(wrapper, shortCode).find('[data-icon="i-woot-bin"]').exists();
const hasAnyManageButton = (wrapper, shortCode) =>
  row(wrapper, shortCode).find('[data-icon="i-woot-edit-pen"]').exists() ||
  row(wrapper, shortCode).find('[data-icon="i-woot-bin"]').exists();

describe('Canned responses Index.vue', () => {
  it('fetches canned responses on mount', () => {
    mountIndex({ isAdmin: false, customRoleId: null });

    expect(dispatch).toHaveBeenCalledWith('getCannedResponse');
  });

  describe('when the user is an administrator', () => {
    it('shows create, the actions column and edit/delete on every row', () => {
      const wrapper = mountIndex({ isAdmin: true, customRoleId: null });

      expect(createButton(wrapper).exists()).toBe(true);
      expect(headers(wrapper)).toEqual(['Short code', 'Created by', 'Actions']);
      expect(hasManageButtons(wrapper, 'own')).toBe(true);
      expect(hasManageButtons(wrapper, 'other')).toBe(true);
      expect(hasManageButtons(wrapper, 'ownerless')).toBe(true);
    });

    it('keeps full management when the administrator also has a custom role', () => {
      const wrapper = mountIndex({ isAdmin: true, customRoleId: 5 });

      expect(createButton(wrapper).exists()).toBe(true);
      expect(headers(wrapper)).toContain('Actions');
      expect(hasManageButtons(wrapper, 'other')).toBe(true);
      expect(hasManageButtons(wrapper, 'ownerless')).toBe(true);
    });
  });

  describe('when the user is an agent without a custom role', () => {
    it('shows create and the actions column', () => {
      const wrapper = mountIndex({ isAdmin: false, customRoleId: null });

      expect(createButton(wrapper).exists()).toBe(true);
      expect(headers(wrapper)).toEqual(['Short code', 'Created by', 'Actions']);
    });

    it('shows edit/delete only on the canned responses the agent owns', () => {
      const wrapper = mountIndex({ isAdmin: false, customRoleId: null });

      expect(hasManageButtons(wrapper, 'own')).toBe(true);
      expect(hasAnyManageButton(wrapper, 'other')).toBe(false);
      expect(hasAnyManageButton(wrapper, 'ownerless')).toBe(false);
    });
  });

  describe('when the user is an agent with a custom role', () => {
    it('hides create, the actions column and every edit/delete button', () => {
      const wrapper = mountIndex({ isAdmin: false, customRoleId: 5 });

      expect(createButton(wrapper).exists()).toBe(false);
      expect(headers(wrapper)).toEqual(['Short code', 'Created by']);
      expect(hasAnyManageButton(wrapper, 'own')).toBe(false);
      expect(hasAnyManageButton(wrapper, 'other')).toBe(false);
      expect(hasAnyManageButton(wrapper, 'ownerless')).toBe(false);
      expect(row(wrapper, 'own').findAll('td')).toHaveLength(2);
    });

    it('still lists every canned response', () => {
      const wrapper = mountIndex({ isAdmin: false, customRoleId: 5 });

      expect(row(wrapper, 'own').exists()).toBe(true);
      expect(row(wrapper, 'other').exists()).toBe(true);
      expect(row(wrapper, 'ownerless').exists()).toBe(true);
    });
  });

  describe('created by column', () => {
    it('renders "You", the owner name or "No owner" with their text colors', () => {
      const wrapper = mountIndex({ isAdmin: false, customRoleId: null });

      const ownCell = row(wrapper, 'own').findAll('td')[1].find('span');
      const otherCell = row(wrapper, 'other').findAll('td')[1].find('span');
      const ownerlessCell = row(wrapper, 'ownerless')
        .findAll('td')[1]
        .find('span');

      expect(ownCell.text()).toBe('You');
      expect(ownCell.classes()).toContain('text-n-slate-12');
      expect(otherCell.text()).toBe('Maya Chen');
      expect(otherCell.classes()).toContain('text-n-slate-11');
      expect(ownerlessCell.text()).toBe('No owner');
      expect(ownerlessCell.classes()).toContain('text-n-slate-10');
    });
  });

  it('lets an agent delete an owned canned response through the confirmation modal', async () => {
    dispatch.mockResolvedValue();
    const wrapper = mountIndex({ isAdmin: false, customRoleId: null });

    await row(wrapper, 'own').find('[data-icon="i-woot-bin"]').trigger('click');
    await wrapper.find('[data-test="confirm-delete"]').trigger('click');

    expect(dispatch).toHaveBeenCalledWith(
      'deleteCannedResponse',
      ownResponse.id
    );
  });
});
