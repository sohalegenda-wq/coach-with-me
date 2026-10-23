import { existsSync } from 'node:fs';
import { defineConfig } from '@playwright/test';
export default defineConfig({
 testDir:'tests/browser',fullyParallel:true,
 use:{baseURL:'http://127.0.0.1:4173',launchOptions:{executablePath:process.env.CWM_CHROMIUM_PATH||(existsSync('/usr/bin/chromium')?'/usr/bin/chromium':undefined),args:['--no-sandbox']},trace:'retain-on-failure'},
 webServer:{command:'npm run dev -- --port 4173',url:'http://127.0.0.1:4173',reuseExistingServer:!process.env.CI,env:{VITE_SUPABASE_URL:'',VITE_SUPABASE_ANON_KEY:''}},
 projects:[{name:'desktop',use:{viewport:{width:1440,height:1050}}},{name:'mobile',use:{viewport:{width:390,height:844},isMobile:true,hasTouch:true}}]
});
