// Node action post entrypoint — delegates to stop.sh.
// Runs automatically after the job completes (even on failure).
const { execFileSync } = require('child_process')
const path = require('path')

try {
  execFileSync('bash', [path.join(__dirname, 'stop.sh')], {
    stdio: 'inherit',
    env: process.env,
  })
} catch {
  // Don't fail the job if stats/cleanup fails
}
