#!/data/data/com.termux/files/usr/bin/bash

ROOT=~/projects/truth-lens
SERVER=$ROOT/apps/api/src/server.ts
DASH=$ROOT/packages/dashboard/src/index.js

echo "[patching server.ts]"

sed -i "/renderNarrativeDetail/a import { buildAlerts, getAlertById } from '../../../packages/news/src/index.js';" $SERVER

sed -i "/url.pathname === '\/dashboard'/i\
  if (url.pathname === '/alerts') {\
    return json(res, 200, buildAlerts(listPosts(), listAnalysis()));\
  }\
\
  if (parts[0] === 'alerts' && parts[1]) {\
    const item = getAlertById(parts[1], listPosts(), listAnalysis());\
    return item ? json(res, 200, item) : notFound(res);\
  }\
" $SERVER

echo "[patching dashboard]"

sed -i "/const ingestState/a const alerts = data.alerts || [];" $DASH

echo "[patch complete]"
