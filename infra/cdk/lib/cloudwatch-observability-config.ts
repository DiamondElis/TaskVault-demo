import * as fs from 'fs';
import * as path from 'path';

/** Fluent Bit override for amazon-cloudwatch-observability (T156). */
export function cloudWatchObservabilityConfigurationValues(): string {
  const applicationLogConf = fs.readFileSync(
    path.join(__dirname, 'cloudwatch-application-log.conf'),
    'utf8',
  );

  return JSON.stringify({
    containerLogs: {
      enabled: true,
      fluentBit: {
        config: {
          extraFiles: {
            'application-log.conf': applicationLogConf,
          },
        },
      },
    },
  });
}
