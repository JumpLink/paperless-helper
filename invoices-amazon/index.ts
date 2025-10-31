#!/usr/bin/env bun
import 'dotenv/config';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// --- SDK (offiziell)
import {
  createRestClient,
  createAwsAuthInterceptor,
  createLwaAuthInterceptor,
} from '@selling-partner-api/sdk';

// ---------- Config ----------
const REGION         = process.env.SPAPI_REGION       ?? 'eu-west-1';
const ENDPOINT       = process.env.SPAPI_ENDPOINT     ?? 'https://sellingpartnerapi-eu.amazon.com';
const MARKETPLACE_ID = process.env.MARKETPLACE_ID     ?? 'A1PA6795UKMFR9';
const FROM           = process.env.FROM               ?? new Date(Date.now() - 90*24*3600e3).toISOString();
const TO             = process.env.TO                 ?? new Date().toISOString();
const OUT_DIR        = process.env.OUT_DIR            ?? './invoices';
const STATE_FILE     = process.env.STATE_FILE         ?? './state.json';

// Credentials
const LWA_CLIENT_ID     = process.env.LWA_CLIENT_ID!;
const LWA_CLIENT_SECRET = process.env.LWA_CLIENT_SECRET!;
const LWA_REFRESH_TOKEN = process.env.LWA_REFRESH_TOKEN!;

const AWS_ACCESS_KEY_ID     = process.env.AWS_ACCESS_KEY_ID!;
const AWS_SECRET_ACCESS_KEY = process.env.AWS_SECRET_ACCESS_KEY!;
const AWS_ROLE_ARN          = process.env.AWS_ROLE_ARN!;

for (const [k, v] of Object.entries({
  LWA_CLIENT_ID, LWA_CLIENT_SECRET, LWA_REFRESH_TOKEN,
  AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_ROLE_ARN
})) {
  if (!v) throw new Error(`Missing env: ${k}`);
}

// ---------- Helpers ----------
async function ensureDir(p: string) {
  await fs.mkdir(p, { recursive: true });
}

async function loadState(): Promise<Record<string, true>> {
  try {
    const raw = await fs.readFile(STATE_FILE, 'utf8');
    return JSON.parse(raw);
  } catch {
    return {};
  }
}

async function saveState(state: Record<string, true>) {
  await fs.writeFile(STATE_FILE, JSON.stringify(state, null, 2), 'utf8');
}

function sleep(ms: number) {
  return new Promise((r) => setTimeout(r, ms));
}

// ---------- SP-API Client ----------
/**
 * Wir erstellen einen generischen REST-Client aus dem offiziellen SDK und hängen
 * sowohl LWA- als auch AWS-SigV4-Interceptor an. Damit können wir beliebige
 * SP-API-Pfade aufrufen (Reports, Reconciliation/Business Orders etc.).
 */
const client = createRestClient({
  baseURL: ENDPOINT,
  userAgent: 'amazon-invoice-downloader/1.0',
  interceptors: [
    createLwaAuthInterceptor({
      clientId: LWA_CLIENT_ID,
      clientSecret: LWA_CLIENT_SECRET,
      refreshToken: LWA_REFRESH_TOKEN,
    }),
    createAwsAuthInterceptor({
      region: REGION,
      service: 'execute-api',
      awsAccessKeyId: AWS_ACCESS_KEY_ID,
      awsSecretAccessKey: AWS_SECRET_ACCESS_KEY,
      roleArn: AWS_ROLE_ARN,
    }),
  ],
});

// ---------- Business: Bestell-/Transaktions-IDs holen ----------
/**
 * Holt orderIds aus dem Business-/Reconciliation-Bereich für ein Zeitfenster.
 * (Die genaue API-Version kann je nach Konto variieren; Pfad ist bewusst generisch
 * gehalten und funktioniert in EU-Accounts mit den Rollen "Abgleichen" + "Bestellung".)
 */
async function fetchOrderIds(fromIso: string, toIso: string): Promise<string[]> {
  const orderIds = new Set<string>();
  let cursor: string | undefined = undefined;

  do {
    const { data } = await client.get('/reconciliations/v1/transactions', {
      params: {
        marketplaceIds: MARKETPLACE_ID,
        postedAfter: fromIso,
        postedBefore: toIso,
        nextToken: cursor,
      },
    });

    const tx = data?.transactions ?? [];
    for (const t of tx) {
      if (t?.orderId) orderIds.add(t.orderId);
    }
    cursor = data?.nextToken ?? undefined;
  } while (cursor);

  return [...orderIds];
}

// ---------- Reports: Rechnungen erzeugen & laden ----------
async function createInvoiceReport(orderId: string): Promise<string> {
  const { data } = await client.post('/reports/2021-09-30/reports', {
    reportType: 'GET_AB_INVOICE_PDF',
    marketplaceIds: [MARKETPLACE_ID],
    reportOptions: { orderId, documentType: 'Invoice' }
  });
  return data.reportId as string;
}

async function waitForReport(reportId: string): Promise<string> {
  let status = 'IN_QUEUE';
  let docId: string | null = null;

  while (!['DONE', 'FATAL', 'CANCELLED'].includes(status)) {
    await sleep(3000);
    const { data } = await client.get(`/reports/2021-09-30/reports/${reportId}`);
    status = data.processingStatus;
    docId = data.reportDocumentId ?? null;
  }
  if (status !== 'DONE' || !docId) throw new Error(`Report failed: ${status}`);
  return docId!;
}

async function getReportDownloadUrl(reportDocumentId: string): Promise<{ url: string; compressionAlgorithm?: string }> {
  const { data } = await client.get(`/reports/2021-09-30/documents/${reportDocumentId}`);
  return { url: data.url, compressionAlgorithm: data.compressionAlgorithm };
}

async function downloadToFile(url: string, targetFile: string) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Download failed ${res.status}`);
  const buf = Buffer.from(await res.arrayBuffer());
  await fs.writeFile(targetFile, buf);
}

// ---------- Main ----------
async function main() {
  await ensureDir(OUT_DIR);

  const state = await loadState();

  console.log(`→ Zeitraum: ${FROM} … ${TO}`);
  const orderIds = await fetchOrderIds(FROM, TO);
  console.log(`→ Gefundene Bestellungen: ${orderIds.length}`);

  let downloaded = 0;
  for (const orderId of orderIds) {
    if (state[orderId]) {
      continue; // schon geladen
    }
    try {
      console.log(`⏳ Erzeuge Rechnungs-Report für orderId=${orderId}`);
      const reportId = await createInvoiceReport(orderId);
      const docId = await waitForReport(reportId);
      const { url } = await getReportDownloadUrl(docId);

      const target = path.join(OUT_DIR, `amazon-invoice-${orderId}.zip`);
      await downloadToFile(url, target);
      state[orderId] = true;
      downloaded++;
      console.log(`✅ Gespeichert: ${target}`);
    } catch (e) {
      console.error(`❌ Fehler bei orderId=${orderId}:`, (e as Error).message);
    }
  }

  await saveState(state);
  console.log(`Fertig. Neu heruntergeladen: ${downloaded}, Gesamtmarkierungen: ${Object.keys(state).length}`);
}

main().catch((e) => {
  console.error('Fatal:', e);
  process.exit(1);
});
