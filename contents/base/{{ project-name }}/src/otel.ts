import { NodeSDK } from '@opentelemetry/sdk-node';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-grpc';

// Only configure OTLP exporter when endpoint is provided (fail-open: no traces if unconfigured)
const exporterConfig = process.env.OTEL_EXPORTER_OTLP_ENDPOINT
  ? { url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT }
  : undefined;

const sdk = new NodeSDK({
  traceExporter: exporterConfig ? new OTLPTraceExporter(exporterConfig) : undefined,
  serviceName: process.env.OTEL_SERVICE_NAME ?? '{{ project-name }}',
});

sdk.start();
