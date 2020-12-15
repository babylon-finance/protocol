import React from 'react';
import styled from "styled-components";
import Web3 from "web3";
import Web3Modal from "web3modal";
import { getDefaultProvider, JsonRpcProvider, Web3Provider } from "@ethersproject/providers";
import { Alert, Button, Space, Spin } from "antd";
// @ts-ignore
import WalletConnectProvider from "@walletconnect/web3-provider";
import './App.css';

interface AppProps {}

interface AppState {
  web3: any
  provider: any
  address: string
  initialLoad: boolean
  fetching: boolean
  connected: boolean
  chainId: number
  networkId: number
  showDetails: boolean
  pendingRequest: boolean
}

function initWeb3(provider: any) {
  const web3: any = new Web3(provider);

  web3.eth.extend({
    methods: [
      {
        name: "chainId",
        call: "eth_chainId",
        outputFormatter: web3.utils.hexToNumber
      }
    ]
  });

  return web3;
}

const INITIAL_STATE = {
  initialLoad: true,
  web3: null,
  provider: null,
  address: "",
  fetching: false,
  connected: false,
  chainId: 1,
  networkId: 1,
  showDetails: false,
  pendingRequest: false
}

export default class App extends React.Component<AppProps, AppState> {
  web3Modal: any

  constructor(props: any) {
    super(props);
    this.state = INITIAL_STATE

    this.web3Modal = new Web3Modal({
      // network: this.getNetwork(),
      cacheProvider: true,
      providerOptions: this.getProviderOptions()
    });
  }

  getNetwork() {

  }

  getProviderOptions() {
    return {
      walletconnect: {
        package: WalletConnectProvider, // required
        options: {
          infuraId: process.env.REACT_APP_INFURA_ID,
        },
      }
    }
  }

  componentDidMount() {
    if (this.web3Modal.cachedProvider) {
      this.onConnect();
    } else {
      this.setState({
        initialLoad: false
      })
    }
  }

  onConnect = async () => {
    const provider = await this.web3Modal.connect();

    const web3: any = initWeb3(provider);
    await this.subscribeProvider(provider);


    const accounts = await web3.eth.getAccounts();

    const address = accounts[0];

    const networkId = await web3.eth.net.getId();

    const chainId = await web3.eth.chainId();
    this.setState({
      web3,
      provider: new Web3Provider(provider),
      initialLoad: false,
      connected: true,
      address,
      chainId,
      networkId
    });
    // biz logic
  }

  resetApp = async () => {
    const { web3 } = this.state;
    if (web3 && web3.currentProvider && web3.currentProvider.close) {
      await web3.currentProvider.close();
    }
    await this.web3Modal.clearCachedProvider();
    const newState = {
      ...INITIAL_STATE,
      initialLoad: false
    }
    this.setState(newState);
  };

  subscribeProvider = async (provider: any) => {
    if (!provider.on) {
      return;
    }
    provider.on("close", () => this.resetApp());
    provider.on("accountsChanged", async (accounts: string[]) => {
      await this.setState({ address: accounts[0] });
      //
    });
    provider.on("chainChanged", async (chainId: number) => {
      const { web3 } = this.state;
      const networkId = await web3.eth.net.getId();
      await this.setState({ chainId, networkId });
      //
    });

    provider.on("networkChanged", async (networkId: number) => {
      const { web3 } = this.state;
      const chainId = await web3.eth.chainId();
      await this.setState({ chainId, networkId });
      // biz logic
    });
  };

  render() {
    const networkId = parseInt(process.env.REACT_APP_NETWORK_ID || '0')
    const onMainnet = this.state.chainId === parseInt(
      process.env.REACT_APP_CHAIN_ID || '0') &&
      this.state.networkId === networkId
    return (
      <AppWrapper className="App">
        {this.state.initialLoad && <Spin tip="Loading..." />}
        {!this.state.initialLoad && (
          <ContentWrapper>
            <LogoWrapper>
              <img width="90" src="/logo512.png" />
            </LogoWrapper>
            <h1> Defi Advisor </h1>
            <div style={{
                display: 'flex',
                flexFlow: 'row wrap',
                margin: '10px 0'
              }}>
              {this.state.web3 && (
                <MainLink onClick={this.resetApp} target="_blank">
                  Logout
                </MainLink>
              )}
            </div>
            {this.state.connected && !onMainnet && (
              <Alert message={`You are on a different network. Please connect your wallet to the ${networkId === 1 ? 'mainnet' : 'network with id ' + networkId}`} type="warning" />
            )}
            {!this.state.connected && (
              <Button value="large" type="primary" onClick={this.onConnect}>
                Connect your wallet to get started
              </Button>
            )}
            {this.state.web3 && this.state.connected && onMainnet && (
              <h2> Connected </h2>
            )}
          </ContentWrapper>
        )}

      </AppWrapper>
    );
  }

}

const MainLink = styled.a`
  font-size: 16px;
  padding: 16px;
  color: rgb(170, 149, 133);
  text-decoration: none;

  &:hover {
    color: rgb(128, 94, 73);
  }
`

const AppWrapper = styled.div`
  display: flex;
  flex-flow: column nowrap;
  align-items: center;
  justify-content: center;
  width: 100%;
  min-height: 100vh;
  height: auto;
`

const ContentWrapper = styled.div`
  display: flex;
  flex-flow: column nowrap;
  justify-content: center;
  align-items: center;
  text-align: center;
  width: 100%;
  height: auto;
  padding: 20px;
`

const LogoWrapper = styled.div`
  background: #333;
  width: 124px;
  height: 124px;
  padding: 5px;
  border-radius: 62px;
  display: flex;
  justify-content: center;
  align-items: center;
  margin: 20px 0;
`
