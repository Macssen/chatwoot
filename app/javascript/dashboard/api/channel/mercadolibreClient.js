/* global axios */
import ApiClient from '../ApiClient';

class MercadolibreChannel extends ApiClient {
  constructor() {
    super('mercadolibre', { accountScoped: true });
  }

  getApp() {
    return axios.get(`${this.url}/app`);
  }

  updateApp(payload) {
    return axios.patch(`${this.url}/app`, payload);
  }

  generateAuthorization(payload) {
    return axios.post(`${this.url}/authorization`, payload);
  }
}

export default new MercadolibreChannel();
