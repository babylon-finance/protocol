import { loadContractFromNameAndAddress } from "../hooks/ContractLoader";

export interface Vault {
  name: string
  address: string
  contract: any
}

export async function getVaults(YRegistry: any, provider: any): Promise<Vault[]> {
  const addresses = await YRegistry.getVaults();
  const promises = addresses.map(async address => {
    const vault = await loadContractFromNameAndAddress(address, "IVault", provider);
    return { name: await vault?.name(), address: address, contract: vault }
  });
  return await Promise.all(promises);
}

export function getVaultByName(vaults: Vault[], vaultName: string) {
  return vaults.find( ({ name }) => name === vaultName);
}
