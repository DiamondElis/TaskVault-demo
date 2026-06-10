/**
 * vuln-8: lodash@4.17.15 is pinned in package.json for scanner/CVE correlation.
 * This module is never imported by runtime paths — detection only, not exploitation.
 */
export const VULN_8_LODASH_PIN = '4.17.15';
