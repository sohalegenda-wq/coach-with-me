import { readFileSync, writeFileSync } from 'node:fs';
const root = new URL('../', import.meta.url);
const schema = readFileSync(new URL('supabase/migrations/202610230001_academy.sql', root), 'utf8');
const content = readFileSync(new URL('supabase/migrations/202610230002_content.sql', root), 'utf8');
const sql = `-- CWM: one-time installation through the Supabase Dashboard SQL Editor.
-- Use a project without existing CWM tables. Do not run after applying either migration.
-- Generated from the two canonical migrations by: npm run db:bundle
-- Includes schema, RLS, server functions and starter curriculum. No credentials.
-- All setup changes are atomic: an error rolls back the installation.
BEGIN;

${schema}

${content}

COMMIT;

-- Expected: courses = 5, lessons = 19, exam_questions = 115.
SELECT
  (SELECT count(*) FROM public.courses) AS courses,
  (SELECT count(*) FROM public.lessons) AS lessons,
  (SELECT count(*) FROM public.exam_questions) AS exam_questions;
`;
const target = new URL('supabase/setup-sql-editor.sql', root);
if (process.argv.includes('--check')) {
  if (readFileSync(target, 'utf8') !== sql) throw new Error('SQL Editor bundle is stale: run npm run db:bundle');
  console.log('SQL Editor bundle matches both migrations.');
} else {
  writeFileSync(target, sql);
  console.log('Created supabase/setup-sql-editor.sql');
}
