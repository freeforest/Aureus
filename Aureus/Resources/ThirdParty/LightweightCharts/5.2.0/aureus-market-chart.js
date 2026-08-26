(() => {
  'use strict';
  const VERSION = 1;
  const container = document.getElementById('chart');
  const tooltip = document.getElementById('tooltip');
  let chart = null;
  let resizeObserver = null;
  let currentPayload = null;
  let candlesByTime = new Map();
  let indicatorsByTime = new Map();

  function post(type, fields = {}) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.aureusChart) {
      window.webkit.messageHandlers.aureusChart.postMessage({ version: VERSION, type, ...fields });
    }
  }

  function fail(category) {
    post('rendererError', { category });
    return false;
  }

  function destroyChart() {
    if (resizeObserver) {
      resizeObserver.disconnect();
      resizeObserver = null;
    }
    if (chart) {
      chart.remove();
      chart = null;
    }
    tooltip.style.display = 'none';
  }

  function finite(value) {
    return typeof value === 'number' && Number.isFinite(value);
  }

  function validDate(value) {
    return typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value);
  }

  function validColor(value) {
    return typeof value === 'string' && /^#[0-9A-Fa-f]{6}$/.test(value);
  }

  function validPayload(payload) {
    if (!payload || !payload.configuration || payload.configuration.schemaVersion !== VERSION) return false;
    if (!Array.isArray(payload.candles) || payload.candles.length > 10000 || !Array.isArray(payload.lines) || payload.lines.length > 16) return false;
    const configuration = payload.configuration;
    if (typeof configuration.provider !== 'string' || configuration.provider.length > 96 ||
        typeof configuration.symbol !== 'string' || configuration.symbol.length > 64 ||
        typeof configuration.rawMIC !== 'string' || !/^[A-Za-z0-9]{4}$/.test(configuration.rawMIC) ||
        typeof configuration.freshness !== 'string' || configuration.freshness.length > 32 ||
        typeof configuration.selectedRange !== 'string' || configuration.selectedRange.length > 8) return false;
    return payload.candles.every(item =>
      validDate(item.time) && finite(item.open) && finite(item.high) && finite(item.low) && finite(item.close) &&
      (item.volume === null || item.volume === undefined || finite(item.volume))
    ) && payload.lines.every(line =>
      typeof line.identifier === 'string' && line.identifier.length > 0 && line.identifier.length <= 64 &&
      typeof line.title === 'string' && line.title.length <= 80 && Number.isInteger(line.pane) && [0, 2, 3].includes(line.pane) &&
      ['line', 'histogram'].includes(line.type) && validColor(line.color) &&
      Array.isArray(line.points) && line.points.length <= 10000 && line.points.every(point => validDate(point.time) && finite(point.value))
    );
  }

  function applyPayload(payload, reduceMotion) {
    try {
      if (!validPayload(payload)) return fail(payload && payload.configuration && payload.configuration.schemaVersion !== VERSION ? 'unsupportedVersion' : 'invalidPayload');
      destroyChart();
      currentPayload = payload;
      candlesByTime = new Map(payload.candles.map(item => [item.time, item]));
      indicatorsByTime = new Map();
      const dark = payload.configuration.darkAppearance === true;
      chart = LightweightCharts.createChart(container, {
        autoSize: true,
        layout: { background: { type: 'solid', color: dark ? '#111827' : '#FFFFFF' }, textColor: dark ? '#E5E7EB' : '#1F2937' },
        grid: { vertLines: { color: dark ? '#374151' : '#E5E7EB' }, horzLines: { color: dark ? '#374151' : '#E5E7EB' } },
        crosshair: { mode: LightweightCharts.CrosshairMode.Normal },
        handleScroll: { mouseWheel: true, pressedMouseMove: true, horzTouchDrag: true, vertTouchDrag: false },
        handleScale: { axisPressedMouseMove: true, mouseWheel: true, pinch: true },
        timeScale: { timeVisible: false, secondsVisible: false, borderVisible: true },
        kineticScroll: { mouse: !reduceMotion, touch: !reduceMotion }
      });
      const candleSeries = chart.addSeries(LightweightCharts.CandlestickSeries, {
        upColor: '#0F766E', downColor: '#C2410C', wickUpColor: '#0F766E', wickDownColor: '#C2410C', borderVisible: false
      }, 0);
      candleSeries.setData(payload.candles.map(({ time, open, high, low, close }) => ({ time, open, high, low, close })));
      const volumeSeries = chart.addSeries(LightweightCharts.HistogramSeries, {
        priceFormat: { type: 'volume' }, priceScaleId: '', color: '#64748B', title: 'Volume'
      }, 1);
      volumeSeries.setData(payload.candles.filter(item => item.volume !== null && item.volume !== undefined).map(item => ({
        time: item.time, value: item.volume, color: item.close >= item.open ? '#0F766E88' : '#C2410C88'
      })));

      const renderSeries = [
        { identifier: 'candlestick', seriesType: 'candlestick', pane: 0, pointCount: payload.candles.length },
        { identifier: 'volume', seriesType: 'histogram', pane: 1, pointCount: payload.candles.filter(item => item.volume !== null && item.volume !== undefined).length }
      ];

      for (const line of payload.lines) {
        for (const point of line.points) {
          const current = indicatorsByTime.get(point.time) || [];
          current.push(`${line.title}: ${point.value}`);
          indicatorsByTime.set(point.time, current);
        }
        const pane = line.pane;
        const type = line.type === 'histogram' ? LightweightCharts.HistogramSeries : LightweightCharts.LineSeries;
        const series = chart.addSeries(type, {
          title: line.title, color: line.color, lineWidth: 2, priceLineVisible: false, lastValueVisible: true
        }, pane);
        series.setData(line.points.map(point => ({ time: point.time, value: point.value, color: line.color })));
        renderSeries.push({ identifier: line.identifier, seriesType: line.type, pane, pointCount: line.points.length });
      }

      post('renderSummary', { series: renderSeries });

      chart.subscribeCrosshairMove(param => {
        const date = typeof param.time === 'string' ? param.time : null;
        post('crosshair', { date });
        if (!date || !candlesByTime.has(date) || !param.point) {
          tooltip.style.display = 'none';
          return;
        }
        const candle = candlesByTime.get(date);
        const indicatorLines = indicatorsByTime.get(date) || [];
        tooltip.textContent = [
          date,
          `O ${candle.open}  H ${candle.high}  L ${candle.low}  C ${candle.close}`,
          `Volume ${candle.volume === null || candle.volume === undefined ? 'Unavailable' : candle.volume}`,
          ...indicatorLines,
          `Provider ${payload.configuration.provider}`,
          `Raw MIC ${payload.configuration.rawMIC}`,
          `Freshness ${payload.configuration.freshness}`
        ].join('\n');
        tooltip.style.display = 'block';
        tooltip.style.left = `${Math.max(4, Math.min(param.point.x + 14, container.clientWidth - 290))}px`;
        tooltip.style.top = `${Math.max(4, Math.min(param.point.y + 14, container.clientHeight - 150))}px`;
      });

      chart.timeScale().subscribeVisibleLogicalRangeChange(range => {
        if (!range || payload.candles.length === 0) return;
        const first = Math.max(0, Math.min(payload.candles.length - 1, Math.floor(range.from)));
        const last = Math.max(0, Math.min(payload.candles.length - 1, Math.ceil(range.to)));
        post('visibleRange', { start: payload.candles[first].time, end: payload.candles[last].time });
      });
      chart.timeScale().fitContent();
      if (payload.candles.length > 0) {
        post('visibleRange', {
          start: payload.candles[0].time,
          end: payload.candles[payload.candles.length - 1].time
        });
      }
      resizeObserver = new ResizeObserver(() => chart && chart.resize(container.clientWidth, container.clientHeight));
      resizeObserver.observe(container);
      return true;
    } catch (_) {
      return fail('rendererFailure');
    }
  }

  window.AureusChart = Object.freeze({ applyPayload });
  post('ready');
})();
