import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(process.env.HOME || '.', 'projects', 'truth-lens');
const DATA_DIR = path.join(ROOT, 'data');
const POSTS_DIR = path.join(DATA_DIR, 'posts');
const ANALYSIS_DIR = path.join(DATA_DIR, 'analysis');

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function writeJson(file, value) {
  fs.writeFileSync(file, JSON.stringify(value, null, 2));
}

export function savePost(post) {
  ensureDir(POSTS_DIR);
  const file = path.join(POSTS_DIR, `${post.id}.json`);
  writeJson(file, post);
}

export function getPost(id) {
  const file = path.join(POSTS_DIR, `${id}.json`);
  if (!fs.existsSync(file)) return null;
  return readJson(file);
}

export function listPosts() {
  ensureDir(POSTS_DIR);
  return fs.readdirSync(POSTS_DIR)
    .filter((f) => f.endsWith('.json'))
    .sort()
    .map((f) => readJson(path.join(POSTS_DIR, f)));
}

export function saveAnalysis(result) {
  ensureDir(ANALYSIS_DIR);
  const file = path.join(ANALYSIS_DIR, `${result.id}.json`);
  writeJson(file, result);
}

export function getAnalysis(id) {
  const file = path.join(ANALYSIS_DIR, `${id}.json`);
  if (!fs.existsSync(file)) return null;
  return readJson(file);
}

export function listAnalysis() {
  ensureDir(ANALYSIS_DIR);
  return fs.readdirSync(ANALYSIS_DIR)
    .filter((f) => f.endsWith('.json'))
    .sort()
    .map((f) => readJson(path.join(ANALYSIS_DIR, f)));
}
