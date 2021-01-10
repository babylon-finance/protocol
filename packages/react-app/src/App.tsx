import AppHeader from "./components/AppHeader";
import FundDetailPage from "./components/FundDetailPage";
import FundSummaryPage from "./components/FundSummaryPage";

import React from 'react';
import {
  BrowserRouter as Router,
  Switch,
  Route
} from "react-router-dom";
import styled from "styled-components";
import Web3 from "web3";
import Web3Modal from "web3modal";
import { Web3Provider } from "@ethersproject/providers";
import { Flex } from 'rimble-ui';
import { Alert, Spin } from "antd";
// @ts-ignore
import WalletConnectProvider from "@walletconnect/web3-provider";
import './App.css';

interface AppProps { }

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
  contract: any
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
  pendingRequest: false,
  contract: null
}

export default class App extends React.Component<AppProps, AppState> {
  web3Modal: any

  constructor(props: any) {
    super(props);
    this.state = INITIAL_STATE;

    this.web3Modal = new Web3Modal({
      // network: this.getNetwork(),
      cacheProvider: true,
      providerOptions: this.getProviderOptions()
    });
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
    const web3Provider = new Web3Provider(provider);

    this.setState({
      web3,
      provider: web3Provider,
      initialLoad: false,
      connected: true,
      address,
      chainId,
      networkId,
    });
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
      this.setState({ address: accounts[0] });
      //
    });
    provider.on("chainChanged", async (chainId: number) => {
      const { web3 } = this.state;
      const networkId = await web3.eth.net.getId();
      this.setState({ chainId, networkId });
      //
    });

    provider.on("networkChanged", async (networkId: number) => {
      const { web3 } = this.state;
      const chainId = await web3.eth.chainId();
      this.setState({ chainId, networkId });
      // biz logic, maybe force a page refresh to avoid complicated rehydration
    });
  };

  renderFundSummary = () => {
    return (
      !this.state.initialLoad && this.state.connected && (
        <FundSummaryPage appState={this.state} />
      )
    );
  }

  render() {
    const networkId = parseInt(process.env.REACT_APP_NETWORK_ID || '0');
    const onMainnet = this.state.chainId === parseInt(process.env.REACT_APP_CHAIN_ID || '0') && this.state.networkId === networkId;

    return (
      <Router>
        <AppWrapper className="App">
          <AppHeader appState={this.state} resetApp={this.resetApp} onConnect={this.onConnect} />
          {this.state.initialLoad && <Spin tip="Loading..." />}
          <ContentWrapper>
            {this.state.connected && !onMainnet && (
              <Alert message={`You are on a different network. Please connect your wallet to the ${networkId === 1 ? 'mainnet' : 'network with id ' + networkId}`} type="warning" />
            )}
            <Switch>
              <Route path="/fund/:address" children={<FundDetailPage />} />
              <Route extec path="/" children={this.renderFundSummary()} />
            </Switch>
          </ContentWrapper>
        </AppWrapper>
      </Router>
    );
  }
}

const AppWrapper = styled(Flex)`
  flex-flow: column nowrap;
  min-height: 100vh;
  height: auto;
`

const ContentWrapper = styled.div`
  display: flex;
  flex-flow: column nowrap;
  justify-content: left;
  height: auto;
`
