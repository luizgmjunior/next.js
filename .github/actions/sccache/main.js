// Node action entrypoint — delegates to start.sh.
// Using a node action (not composite) so we get automatic `post` cleanup.
const { execFileSync } = require('child_process')
const path = require('path')

execFileSync('bash', [path.join(__dirname, 'start.sh')], {
  stdio: 'inherit',
  env: process.env,
})
