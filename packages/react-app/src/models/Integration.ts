export enum IntegrationType {
  passive = "passive",
  trade = "trade",
  liquidity = "liquidity",
  leverage = "leverage"
}

export type IntegrationTypes = keyof typeof IntegrationType

export interface Integration {
  name: string
  address: string
  type: IntegrationType
}

export interface IntegrationList {
  integrations: Integration[]
}

export const integrations = [
  { name: "YearnVaultIntegration", type: IntegrationType.passive },
  { name: "KyberTradeIntegration", type: IntegrationType.trade },
];

export function getIntegrationsWithAddress(): IntegrationList {
  const integrationList = integrations.map(item => {
      const address = require(`../contracts/${item.name}.address.js`);
      const integration = { name: item.name, type: item.type, address: address } ;
      return integration;
    }
  );

  return { integrations: integrationList };
};

export type GroupedIntegrations = any;

export function integrationsGroupedByKey(key: string): GroupedIntegrations {
  return getIntegrationsWithAddress().integrations.reduce(function(storage, item) {
    var group = item[key];
    storage[group] = storage[group] || [];
    storage[group].push(item);
    return storage;
  }, {});
};
