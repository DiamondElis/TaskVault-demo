import { describe, expect, it } from 'vitest';
import { buildObjectKey, classificationToPrefix } from './s3.js';

describe('classificationToPrefix', () => {
  it('maps public/private/sensitive to S3 prefixes', () => {
    expect(classificationToPrefix('public')).toBe('uploads/public/');
    expect(classificationToPrefix('private')).toBe('uploads/private/');
    expect(classificationToPrefix('sensitive')).toBe('uploads/sensitive/');
  });
});

describe('buildObjectKey', () => {
  it('places files under the classification prefix and owner folder', () => {
    const key = buildObjectKey('sensitive', 'user-1', 'payroll.csv');
    expect(key.startsWith('uploads/sensitive/user-1/')).toBe(true);
    expect(key.endsWith('payroll.csv')).toBe(true);
  });
});
