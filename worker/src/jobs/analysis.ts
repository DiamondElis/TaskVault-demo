export interface FakeAnalysisResult {
  byteSize: number;
  rowCount: number;
  classificationConfidence: number;
  syntheticLabel: string;
  analyzedAt: string;
}

export function buildFakeAnalysis(content: Buffer, filename: string): FakeAnalysisResult {
  const text = content.toString('utf8');
  const lines = text.split(/\r?\n/).filter((line) => line.trim().length > 0);
  const rowCount = Math.max(lines.length - (filename.endsWith('.csv') ? 1 : 0), 0);

  return {
    byteSize: content.byteLength,
    rowCount,
    classificationConfidence: 0.87,
    syntheticLabel: filename.includes('sensitive') ? 'sensitive-demo' : 'benign-demo',
    analyzedAt: new Date().toISOString(),
  };
}
