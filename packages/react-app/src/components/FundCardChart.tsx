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

interface SeriesValues {

}


interface Props { }

interface State { chartData: ChartData }

export default class FundCardChart extends React.PureComponent<Props, State> {
  constructor(props: Props, state: State) {
    super(props, state);

    this.state = { chartData: { data: { values: [] } } };
  }

  async getChartData() {
    const resp = await axios.get(
      "https://data.messari.io/api/v1/assets/ETH/metrics/price/time-series?interval=1d&columns=close&after=2020-11-20",
    );
    return await resp;
  }

  componentDidMount() {
    this.getChartData().then((response) => {
      this.setState({ chartData: response.data });
    })
  }

  render() {
    const chartOptions = {
      chart: {
        type: "spline",
        height: 200
      },
      credits: {
        enabled: false
      },
      title: {
        text: "ETH Price (30d)"
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
          data: this.state.chartData.data.values.map(x => x[1])
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
