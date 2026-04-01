import { nextTestSetup } from 'e2e-utils'
import { retry } from 'next-test-utils'

describe('server-hmr with react-compiler', () => {
  const { next, isTurbopack, isNextDev } = nextTestSetup({
    files: __dirname,
    dependencies: {
      'babel-plugin-react-compiler': '0.0.0-experimental-3fde738-20250918',
    },
  })

  // Server HMR is a Turbopack-only feature, only available in dev mode
  const itTurbopackDev = isTurbopack && isNextDev ? it : it.skip

  it('renders the page correctly when babel-plugin-react-compiler is present', async () => {
    const initial = await next.fetch('/').then((res) => res.text())
    expect(initial).toContain('hello from version 0')
  })

  itTurbopackDev(
    'reflects server component changes on fetch when babel-plugin-react-compiler is present',
    async () => {
      const initial = await next.fetch('/').then((res) => res.text())
      expect(initial).toContain('hello from version 0')

      await next.patchFile('app/page.tsx', (content) =>
        content.replace('hello from version 0', 'hello from version 1')
      )

      await retry(async () => {
        const updated = await next.fetch('/').then((res) => res.text())
        expect(updated).toContain('hello from version 1')
      })
    }
  )
})
