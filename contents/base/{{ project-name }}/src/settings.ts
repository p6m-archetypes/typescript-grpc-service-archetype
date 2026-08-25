import { config } from 'dotenv';
config();

export const settings = {
  host: process.env.HOST ?? '0.0.0.0',
  port: parseInt(process.env.GRPC_PORT ?? '{{ service_port }}', 10),
  managementPort: parseInt(process.env.MANAGEMENT_PORT ?? '{{ management_port }}', 10),
  logLevel: process.env.LOG_LEVEL ?? 'info',
  loggingStructured: (process.env.LOGGING_STRUCTURED ?? 'false') === 'true',
{% if persistence == 'PostgreSQL' %}
  dbHost: process.env.DB_HOST ?? 'localhost',
  dbPort: parseInt(process.env.DB_PORT ?? '5432', 10),
  dbUsername: process.env.DB_USERNAME ?? 'user',
  dbPassword: process.env.DB_PASSWORD ?? 'pass',
  dbName: process.env.DB_DBNAME ?? '{{ project-name }}',
{% endif %}
{% if persistence == 'MySQL' %}
  dbHost: process.env.DB_HOST ?? 'localhost',
  dbPort: parseInt(process.env.DB_PORT ?? '3306', 10),
  dbUsername: process.env.DB_USERNAME ?? 'user',
  dbPassword: process.env.DB_PASSWORD ?? 'pass',
  dbName: process.env.DB_DBNAME ?? '{{ project-name }}',
{% endif %}
{% if cache == 'Redis' %}
  cacheHost: process.env.CACHE_HOST ?? 'localhost',
  cachePort: parseInt(process.env.CACHE_PORT ?? '6379', 10),
  cacheUsername: process.env.CACHE_USERNAME ?? '',
  cachePassword: process.env.CACHE_PASSWORD ?? '',
{% endif %}
{% if messaging == 'Kafka' %}
  messagingBrokers: process.env.MESSAGING_BROKERS ?? 'localhost:9092',
  messagingTopic: process.env.MESSAGING_TOPIC ?? '{{ project-name }}',
  messagingUsername: process.env.MESSAGING_USERNAME ?? '',
  messagingPassword: process.env.MESSAGING_PASSWORD ?? '',
  messagingSaslMechanism: process.env.MESSAGING_SASL_MECHANISM ?? 'plain',
{% endif %}
{% if messaging == 'Pulsar' %}
  messagingBrokerUrl: process.env.MESSAGING_BROKER_URL ?? 'pulsar://localhost:6650',
  messagingTopic: process.env.MESSAGING_TOPIC ?? 'persistent://public/default/{{ project-name }}',
  messagingJwtToken: process.env.MESSAGING_JWT_TOKEN ?? '',
  messagingSubscriptionName: process.env.MESSAGING_SUBSCRIPTION_NAME ?? '{{ project-name }}-sub',
{% endif %}
{% if has_s3 %}
  s3Endpoint: process.env.S3_ENDPOINT ?? 'http://localhost:9000',
  s3Bucket: process.env.S3_BUCKET ?? '{{ project-name }}',
  s3Prefix: process.env.S3_PREFIX ?? '',
  s3AccessKey: process.env.S3_ACCESS_KEY ?? 'minioadmin',
  s3SecretKey: process.env.S3_SECRET_KEY ?? 'minioadmin',
{% endif %}
{% if has_azure_blob %}
  azureEndpoint: process.env.AZURE_ENDPOINT ?? 'http://localhost:10000/devstoreaccount1',
  azureContainer: process.env.AZURE_CONTAINER ?? '{{ project-name }}',
  azureAccountName: process.env.AZURE_ACCOUNT_NAME ?? 'devstoreaccount1',
  azureAccountKey: process.env.AZURE_ACCOUNT_KEY ?? 'Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KkZB2M0XK3Xg==',
{% endif %}
} as const;

export type Settings = typeof settings;
