const { NodeSDK } = require('@opentelemetry/sdk-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const {
  getNodeAutoInstrumentations,
} = require('@opentelemetry/auto-instrumentations-node');

const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter(),
  instrumentations: [
    getNodeAutoInstrumentations({
//      '@opentelemetry/instrumentation-net': {
//        enabled: false,
//      },
//      '@opentelemetry/instrumentation-dns': {
//        enabled: false,
//      }
    })
  ],
});

sdk.start();
