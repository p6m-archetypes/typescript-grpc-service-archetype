import { settings } from './settings';

// The platform log contract (S4): with LOGGING_STRUCTURED=true stdout is pino's native JSON
// lines (what the platform ships to the log pipeline); with it unset/false, a human-readable
// pretty stream for the dev inner loop. Fastify passes these options straight to pino.
export const loggerOptions = settings.loggingStructured
  ? { level: settings.logLevel }
  : { level: settings.logLevel, transport: { target: 'pino-pretty' } };
