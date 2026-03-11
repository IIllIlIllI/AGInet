#!/data/data/com.termux/files/usr/bin/bash

FILE=~/projects/truth-lens/apps/api/src/server.ts

echo "[removing broken import]"
sed -i "/packages\/news\/src\/index.js/d" $FILE

echo "[adding correct import at top]"
sed -i "1i import { buildAlerts, getAlertById } from '../../../packages/news/src/index.js';" $FILE

echo "[done]"
