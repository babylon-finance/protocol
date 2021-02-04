import React from "react";
import Highcharts from 'highcharts/highstock'
import HighchartsReact from "highcharts-react-official";
import styled from "styled-components";
import axios from "axios";

interface ChartData {
  data: {
    values: number[][]
  }
}

interface Props {
  height: number
}

interface State {
  chartData: ChartData,
  chartDataLoaded: boolean
}

export default class FundCardChart extends React.PureComponent<Props, State> {
  constructor(props: Props, state: State) {
    super(props, state);

    this.state = {
      chartDataLoaded: false,
      chartData: {
        data: {
          values: []
        }
      }
    };
  }

  async getChartData() {
    const resp = await axios.get(
      "https://data.messari.io/api/v1/assets/ETH/metrics/price/time-series?interval=1d&columns=close&after=2020-11-20",
    );
    return await resp;
  }

  componentDidMount() {
    this.getChartData().then((response) => {
      this.setState({ chartData: response.data, chartDataLoaded: true });
    })
  }

  render() {
    const chartOptions = {
      chart: {
        type: "spline",
        height: this.props.height,
        shadow: true,
        style: {
          fontFamily: 'cera-regular'
        }
      },
      plotOptions: {
        series: {
          color: 'var(--purple-aux)'
        }
      },
      credits: {
        enabled: false
      },
      title: {
        text: "NAT vs Benchmark (30d)"
      },
      yAxis: {
        title: {
          enabled: false
        }
      },
      legend: {
        enabled: false
      },
      tooltip: {
        valueDecimals: 2,
        valuePrefix: '$',
        valueSuffix: ' USD'
      },
      series: [
        {
          name: 'ETH',
          data: this.state.chartData.data.values.slice(1).slice(-30).map(x => x[1])
        }
      ]
    }

    return (
      <ChartWrapper>
        <HighchartsReact
          highcharts={Highcharts}
          options={chartOptions} />
      </ChartWrapper>
    )
  }
}

const ChartWrapper = styled.div`
`
