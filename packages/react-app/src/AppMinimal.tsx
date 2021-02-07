import AppHeaderMinimal from "./components/AppHeaderMinimal";
import LanderMinimal from "./components/LanderMinimal";

import React from 'react';
import {
  BrowserRouter as Router,
  Switch,
  Route
} from "react-router-dom";
import styled from "styled-components";
import { Flex } from 'rimble-ui';
import './App.css';

interface AppProps { }

interface AppState {
}

export default class AppMinimal extends React.Component<AppProps, AppState> {
  renderHeader = (index?: boolean) => {
    return (
      <AppHeaderMinimal key={"header"} />
    );
  }
  render() {
    return (
      <Router>
        <AppWrapper className="App">
          <ContentWrapper>
            <Switch>
              <Route path="/" children={[this.renderHeader(true), <LanderMinimal key={"lander"} />]} />
            </Switch>
          </ContentWrapper>
        </AppWrapper>
      </Router>
    );
  }
}

const AppWrapper = styled(Flex)`
  flex-direction: column;
  min-height: 100vh;
  height: auto;
`

const ContentWrapper = styled.div`
  display: flex;
  flex-grow: 1;
  flex-flow: column;
  justify-content: left;
`
