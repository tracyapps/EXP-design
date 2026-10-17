import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { chromium, webkit } from 'playwright';
import AxeBuilder from '@axe-core/playwright';
import { startFixture } from './fixture.mjs';

const output = process.env.EXP_A11Y_OUTPUT;
if (!output?.includes('/output/a11y/')) throw Error('Use the accessibility runner');
await mkdir(output, { recursive: true });
const fixture = await startFixture(), results = [];
const tabKeys = new WeakMap();
const variants = [
  { name: 'chromium-dark', engine: chromium, colorScheme: 'dark', width: 1280 },
  { name: 'chromium-light-mobile', engine: chromium, colorScheme: 'light', width: 390, reducedMotion: 'reduce' },
  { name: 'webkit-dark', engine: webkit, colorScheme: 'dark', width: 1280 },
  { name: 'webkit-light-mobile', engine: webkit, colorScheme: 'light', width: 390, reducedMotion: 'reduce' }
];

async function check(name, page, fn) {
  const file = name.replace(/[^a-z0-9-]/gi, '-');
  try { await fn(); results.push({ name, status: 'passed' }); }
  catch (error) { results.push({ name, status: 'failed', detail: error.message }); }
  if (page && !page.isClosed()) {
    await page.screenshot({ path: path.join(output, `${file}.png`), fullPage: true }).catch(() => {});
    await writeFile(path.join(output, `${file}.aria.yml`), await page.locator('body').ariaSnapshot()).catch(() => {});
  }
}
async function scan(name, page) {
  const result = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa', 'wcag21a', 'wcag21aa']).analyze();
  await writeFile(path.join(output, `${name}.axe.json`), JSON.stringify(result, null, 2));
  results.push({ name: `${name}-axe`, status: result.violations.length ? 'failed' : 'passed',
    detail: result.violations.map(v => `${v.id}: ${v.nodes.map(n => n.target).join(', ')}`).join('\n') });
  if (result.incomplete.length) results.push({ name: `${name}-axe-incomplete`, status: 'needs-review', detail: result.incomplete.map(v => v.id).join(', '),
    reviewItems: result.incomplete.flatMap(v => v.nodes.map(node => ({ rule: v.id, target: node.target, reason: node.failureSummary }))) });
}
async function tabTo(page, locator, maximum = 35) {
  for (let i = 0; i < maximum; i++) {
    if (await locator.evaluate(el => el === document.activeElement)) return;
    await page.keyboard.press(tabKeys.get(page) || 'Tab');
  }
  // The last allowed Tab can itself reach the target. Check before declaring
  // failure (the additional account navigation exposed this boundary).
  if (await locator.evaluate(el => el === document.activeElement)) return;
  throw Error(`Keyboard could not reach ${await locator.getAttribute('id') || await locator.textContent()}`);
}
async function type(page, locator, value) {
  await tabTo(page, locator); await page.keyboard.press('Meta+A'); await page.keyboard.type(value);
}

try {
  for (const variant of variants) {
    // Each browser is an independent scenario sharing one loopback IP. Provider/
    // rate-limit correctness is covered by real-DB service tests, not this reset.
    await fixture.resetIPWindow();
    let browser;
    const executable = variant.engine.executablePath();
    if (!existsSync(executable)) {
      results.push({ name: variant.name, status: 'blocked', detail: `Browser binary missing. Run: npm --prefix website exec playwright install ${variant.engine === webkit ? 'webkit' : 'chromium'}` }); continue;
    }
    try {
      browser = await variant.engine.launch({ headless: true });
      const context = await browser.newContext({ colorScheme: variant.colorScheme, reducedMotion: variant.reducedMotion || 'no-preference', viewport: { width: variant.width, height: 1000 } });
      // Third-party icon CDN is intentionally isolated; no user/provider traffic.
      await context.route('**/*', route => new URL(route.request().url()).origin === fixture.origin ? route.continue() : route.fulfill({ status: 200, body: '', contentType: 'text/css' }));
      const page = await context.newPage();
      // Safari's documented Option-Tab reaches all controls even when its
      // ordinary Tab preference reaches text fields only. No OS setting changes.
      tabKeys.set(page, variant.engine === webkit ? 'Alt+Tab' : 'Tab');
      page.setDefaultTimeout(7000); page.setDefaultNavigationTimeout(15000);
      page.on('pageerror', error => results.push({ name: `${variant.name}-javascript`, status: 'failed', detail: error.message }));
      const email = `${variant.name}@example.test`;
      await check(`${variant.name}-account-registration-keyboard`, page, async () => {
        await page.goto(`${fixture.origin}/account`);
        const create = page.getByRole('radio', { name: 'Create account' });
        await create.waitFor();
        await tabTo(page, page.getByRole('radio', { name: 'Sign in', exact: true }));
        await page.keyboard.press('ArrowRight');
        assert.ok(await create.isChecked());
        await type(page, page.getByLabel('Email address'), email);
        await type(page, page.getByLabel('Display name'), 'Keyboard Designer');
        await tabTo(page, page.getByRole('checkbox')); await page.keyboard.press('Space');
        await tabTo(page, page.getByRole('button', { name: 'Email me a code' })); await page.keyboard.press('Enter');
        const code = page.getByLabel('Six-digit code'); await code.waitFor();
        assert.ok(await code.evaluate(el => document.activeElement === el), 'Code field must receive focus');
        const mail = fixture.mail.findLast(item => item.kind === 'account' && item.email === email); assert.ok(mail);
        await page.keyboard.type(mail.otp); await page.keyboard.press('Enter');
        await page.getByRole('heading', { name: 'Hello, Keyboard Designer.' }).waitFor();
        await page.waitForFunction(() => document.activeElement?.id === 'account-title');
        await scan(`${variant.name}-overview`, page);
      });
      await check(`${variant.name}-private-profile-keyboard`, page, async () => {
        await tabTo(page, page.getByRole('link', { name: 'Private profile', exact: true })); await page.keyboard.press('Enter');
        await page.getByLabel('Display name').waitFor();
        await type(page, page.getByLabel('Display name'), 'Updated Keyboard Designer');
        await type(page, page.getByLabel('Bio (optional, up to 500 characters)'), 'A private test profile.');
        await type(page, page.getByLabel('Website (optional HTTPS link)'), 'https://example.test/designer');
        await tabTo(page, page.getByRole('button', { name: 'Save private profile' })); await page.keyboard.press('Enter');
        await page.getByRole('status').filter({ hasText: 'Private profile saved.' }).waitFor();
        await page.reload(); await page.getByLabel('Display name').waitFor();
        assert.equal(await page.getByLabel('Display name').inputValue(), 'Updated Keyboard Designer');
        await scan(`${variant.name}-profile`, page);
      });
      await check(`${variant.name}-beta-feedback-keyboard`, page, async () => {
        await tabTo(page, page.getByRole('link', { name: 'Beta & feedback', exact: true })); await page.keyboard.press('Enter');
        const participation = page.getByRole('checkbox', { name: 'I’d like to participate in EXP beta testing.' });
        const invitations = page.getByRole('checkbox', { name: 'Email me beta invitations', exact: false });
        await participation.waitFor();
        assert.equal(await participation.isChecked(), false);
        assert.equal(await invitations.isChecked(), false);
        assert.equal(await invitations.isDisabled(), true);
        await scan(`${variant.name}-beta-empty`, page);
        await tabTo(page, participation); await page.keyboard.press('Space');
        await tabTo(page, page.getByRole('button', { name: 'Save beta choices' })); await page.keyboard.press('Enter');
        await page.getByRole('status').filter({ hasText: 'Beta choices saved.' }).waitFor();
        await page.reload(); await participation.waitFor();
        assert.equal(await participation.isChecked(), true); assert.equal(await invitations.isChecked(), false);
        await tabTo(page, invitations); await page.keyboard.press('Space');
        await tabTo(page, page.getByRole('button', { name: 'Save beta choices' })); await page.keyboard.press('Enter');
        await page.getByRole('status').filter({ hasText: 'Beta choices saved.' }).waitFor();
        const subject = page.getByLabel('Subject (up to 120 characters)');
        await type(page, subject, 'A private keyboard note');
        const literal = '<img src=x onerror=alert(1)> ' + 'long-feedback-'.repeat(45);
        await type(page, page.getByLabel('What happened, or what would help? (up to 1,500 characters)'), literal);
        let failedId, retryId;
        await page.route('**/api/account', async route => {
          const body = route.request().postDataJSON();
          if (body?.action !== 'submit-beta-feedback') return route.continue();
          if (!failedId) { failedId = body.id; return route.fulfill({ status: 503, contentType: 'application/json', body: JSON.stringify({ error: 'Temporary test failure. Please retry.' }) }); }
          retryId = body.id; return route.continue();
        });
        const send = page.getByRole('button', { name: 'Send feedback', exact: true });
        await tabTo(page, send); await page.keyboard.press('Enter');
        await page.getByRole('status').filter({ hasText: 'Temporary test failure.' }).waitFor();
        assert.equal(await subject.inputValue(), 'A private keyboard note');
        await tabTo(page, send); await page.keyboard.press('Enter');
        await page.getByRole('status').filter({ hasText: 'Your private feedback was received.' }).waitFor();
        await page.unroute('**/api/account'); assert.equal(retryId, failedId);
        await page.waitForFunction(() => document.activeElement?.id === 'beta-subject');
        await page.reload(); await page.getByRole('heading', { name: 'A private keyboard note' }).waitFor();
        assert.equal(await page.locator('.account-feedback-list li').count(), 1);
        assert.equal(await page.locator('.account-feedback-message').textContent(), literal);
        assert.equal(await page.locator('.account-feedback-list img').count(), 0);
        assert.equal(await invitations.isChecked(), true);
        assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
        await scan(`${variant.name}-beta-saved`, page);
        await page.screenshot({ path: path.join(output, `${variant.name}-beta-saved.png`), fullPage: true });
        await tabTo(page, participation); await page.keyboard.press('Space');
        assert.equal(await invitations.isChecked(), false);
        await tabTo(page, page.getByRole('button', { name: 'Save beta choices' })); await page.keyboard.press('Enter');
        await page.getByRole('status').filter({ hasText: 'Beta participation and beta invitations are off.' }).waitFor();
        assert.equal(await page.locator('.account-feedback-list li').count(), 1);
        const remove = page.locator('summary').filter({ hasText: 'Delete feedback' });
        await tabTo(page, remove); await page.keyboard.press('Enter');
        await scan(`${variant.name}-beta-delete-confirmation`, page);
        await tabTo(page, page.getByRole('button', { name: 'Confirm deletion' })); await page.keyboard.press('Enter');
        await page.getByRole('status').filter({ hasText: 'Feedback deleted from the live account store.' }).waitFor();
        assert.equal(await page.locator('.account-feedback-list li').count(), 0);
        assert.ok(await page.getByRole('heading', { name: 'Your saved feedback' }).evaluate(el => el === document.activeElement));
        await page.reload(); await participation.waitFor();
        assert.equal(await participation.isChecked(), false); assert.equal(await invitations.isChecked(), false);
      });
      await check(`${variant.name}-account-pro-link-keyboard`, page, async () => {
        await page.goto(`${fixture.origin}/account/pro`);
        await page.getByText('No Pro-interest record is connected', { exact: false }).waitFor();
        await scan(`${variant.name}-account-pro-unlinked`, page);
        await page.goto(`${fixture.origin}/pro`);
        await type(page, page.getByLabel('email (required)', { exact: true }), email);
        await tabTo(page, page.getByLabel('which payment model would you consider? (required)'));
        await page.keyboard.type('s'); await page.keyboard.press(tabKeys.get(page) || 'Tab');
        await tabTo(page, page.getByRole('checkbox')); await page.keyboard.press('Space');
        await tabTo(page, page.getByRole('button', { name: 'email me a confirmation' })); await page.keyboard.press('Enter');
        await page.getByRole('status').filter({ hasText: 'Check your inbox' }).waitFor();
        const mail = fixture.mail.findLast(item => item.kind === 'interest' && item.email === email); assert.ok(mail);
        await page.goto(mail.confirm);
        const confirm = page.getByRole('button', { name: 'confirm Pro interest' }); await confirm.waitFor();
        await tabTo(page, confirm); await page.keyboard.press('Enter');
        await page.getByRole('status').filter({ hasText: "You're on the Pro-interest list." }).waitFor();
        await page.goto(`${fixture.origin}/account/pro`);
        await page.getByText('No Pro-interest record is connected', { exact: false }).waitFor();
        await page.goto(mail.withdraw);
        const connectLink = page.getByRole('link', { name: 'Connect to my free account' }); await connectLink.waitFor();
        await tabTo(page, connectLink); await page.keyboard.press('Enter');
        const connect = page.getByRole('button', { name: 'Connect confirmed Pro interest' }); await connect.waitFor();
        await page.waitForFunction(() => location.hash === '');
        await tabTo(page, connect); await page.keyboard.press('Enter');
        await page.getByRole('status').filter({ hasText: 'Your confirmed Pro-interest record is connected.' }).waitFor();
        await page.reload();
        await page.getByText('Pro-interest emails are on for your connected record.', { exact: true }).waitFor();
        await scan(`${variant.name}-account-pro-confirmed`, page);
        await page.screenshot({ path: path.join(output, `${variant.name}-account-pro-confirmed.png`), fullPage: true });
        await tabTo(page, page.getByRole('button', { name: 'Withdraw Pro-interest emails', exact: true })); await page.keyboard.press('Enter');
        await page.getByRole('status').filter({ hasText: 'Pro interest withdrawn.' }).waitFor();
        await page.getByText('Pro-interest emails are off.', { exact: false }).waitFor();
        await scan(`${variant.name}-account-pro-withdrawn`, page);
        await tabTo(page, page.getByRole('button', { name: 'Disconnect account link' })); await page.keyboard.press('Enter');
        await page.getByRole('status').filter({ hasText: 'Account connection removed.' }).waitFor();
        assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
      });
      await check(`${variant.name}-preferences-and-delete-keyboard`, page, async () => {
        await page.goto(`${fixture.origin}/account/preferences`);
        const large = page.getByRole('checkbox', { name: 'Use larger text in this account area' }); await large.waitFor();
        await tabTo(page, large); await page.keyboard.press('Space');
        await tabTo(page, page.getByRole('button', { name: 'Save preferences' })); await page.keyboard.press('Enter');
        await page.getByRole('status').filter({ hasText: 'Account text preference saved.' }).waitFor();
        await page.reload(); await large.waitFor(); assert.ok(await large.isChecked());
        assert.equal(await page.locator('.account-page').evaluate(el => getComputedStyle(el).fontSize), '20px');
        assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
        await scan(`${variant.name}-preferences-large`, page);
        await page.goto(`${fixture.origin}/account/beta`);
        await page.getByLabel('Subject (up to 120 characters)').waitFor();
        assert.equal(await page.locator('.account-page').evaluate(el => getComputedStyle(el).fontSize), '20px');
        assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
        await scan(`${variant.name}-beta-large`, page);
        await page.screenshot({ path: path.join(output, `${variant.name}-beta-large.png`), fullPage: true });
        await page.goto(`${fixture.origin}/account/preferences`); await large.waitFor();
        const summary = page.locator('summary').filter({ hasText: 'Delete this free account' });
        await tabTo(page, summary); await page.keyboard.press('Enter');
        await type(page, page.getByLabel('Type DELETE to confirm'), 'DELETE');
        await tabTo(page, page.getByRole('button', { name: 'Delete my free account' })); await page.keyboard.press('Enter');
        await page.getByRole('status').filter({ hasText: 'Your live free account has been deleted.' }).waitFor();
        const session = await context.request.get(`${fixture.origin}/api/account`); assert.equal((await session.json()).user, null);
      });
      await check(`${variant.name}-errors-and-unavailable`, page, async () => {
        await page.goto(`${fixture.origin}/account`); await page.getByRole('button', { name: 'Email me a code' }).waitFor();
        await type(page, page.getByLabel('Email address'), 'invalid');
        await tabTo(page, page.getByRole('button', { name: 'Email me a code' })); await page.keyboard.press('Enter');
        assert.ok(await page.getByLabel('Email address').evaluate(el => !el.validity.valid));
        assert.ok(await page.getByLabel('Email address').evaluate(el => el === document.activeElement));
        await scan(`${variant.name}-invalid-email`, page);
        await page.route('**/api/account', route => route.fulfill({ status: 503, contentType: 'application/json', body: JSON.stringify({ error: 'Free accounts are not open yet.' }) }));
        await page.reload(); await page.getByRole('link', { name: 'Check again' }).waitFor();
        assert.equal(await page.getByRole('button', { name: 'Email me a code' }).count(), 0);
        await scan(`${variant.name}-unavailable`, page);
        await page.unroute('**/api/account');
      });
      await check(`${variant.name}-support-and-pro`, page, async () => {
        await page.goto(`${fixture.origin}/support.html`); await page.getByRole('heading', { level: 1 }).waitFor();
        await scan(`${variant.name}-support`, page);
        await page.goto(`${fixture.origin}/pro`); await page.getByRole('heading', { level: 1 }).waitFor();
        await scan(`${variant.name}-pro`, page);
        assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
      });
      await check(`${variant.name}-wrong-and-expired-code`, page, async () => {
        await page.goto(`${fixture.origin}/account`);
        const address = `errors-${email}`;
        await type(page, page.getByLabel('Email address'), address);
        await tabTo(page, page.getByRole('button', { name: 'Email me a code' })); await page.keyboard.press('Enter');
        const input = page.getByLabel('Six-digit code'); await input.waitFor();
        const code = fixture.mail.findLast(item => item.kind === 'account' && item.email === address).otp;
        await page.keyboard.type(code === '000000' ? '111111' : '000000'); await page.keyboard.press('Enter');
        await page.getByRole('status').filter({ hasText: 'Could not complete that action.' }).waitFor();
        await scan(`${variant.name}-wrong-code`, page);
        await fixture.expireCode(address);
        await type(page, input, code); await page.keyboard.press('Enter');
        await page.getByRole('status').filter({ hasText: 'Could not complete that action.' }).waitFor();
        assert.equal((await (await context.request.get(`${fixture.origin}/api/account`)).json()).user, null);
        await scan(`${variant.name}-expired-code`, page);
      });
      await check(`${variant.name}-pro-confirm-withdraw-keyboard`, page, async () => {
        await page.goto(`${fixture.origin}/pro`);
        await type(page, page.getByLabel('email (required)', { exact: true }), `pro-${email}`);
        const model = page.getByLabel('which payment model would you consider? (required)');
        await tabTo(page, model); await page.keyboard.type('s'); await page.keyboard.press(tabKeys.get(page) || 'Tab');
        assert.ok(await model.inputValue());
        const permission = page.getByRole('checkbox'); await tabTo(page, permission); await page.keyboard.press('Space');
        await tabTo(page, page.getByRole('button', { name: 'email me a confirmation' })); await page.keyboard.press('Enter');
        await page.getByRole('status').filter({ hasText: 'Check your inbox' }).waitFor();
        const mail = fixture.mail.findLast(item => item.kind === 'interest' && item.email === `pro-${email}`); assert.ok(mail);
        await page.goto(mail.confirm);
        const confirm = page.getByRole('button', { name: 'confirm Pro interest' }); await confirm.waitFor();
        await page.waitForFunction(() => location.hash === '');
        await tabTo(page, confirm); await page.keyboard.press('Enter');
        await page.getByRole('status').filter({ hasText: "You're on the Pro-interest list." }).waitFor();
        await scan(`${variant.name}-pro-confirmed`, page);
        await page.goto(mail.withdraw);
        const withdraw = page.getByRole('button', { name: 'withdraw Pro interest' }); await withdraw.waitFor();
        await tabTo(page, withdraw); await page.keyboard.press('Enter');
        await page.getByRole('status').filter({ hasText: 'Your Pro interest has been withdrawn.' }).waitFor();
        await scan(`${variant.name}-pro-withdrawn`, page);
      });
      await context.close();
    } catch (error) { results.push({ name: variant.name, status: 'failed', detail: error.message }); }
    finally { await browser?.close(); }
  }
  if (fixture.errors.length) results.push({ name: 'fixture-health', status: 'failed', detail: fixture.errors.join('; ') });
} finally {
  await fixture.close();
  await writeFile(path.join(output, 'web.json'), JSON.stringify({ results, scope: 'Real local account services and keyboard events; axe WCAG 2.1 A/AA detectable rules. WebKit is not Safari+VoiceOver proof.' }, null, 2));
}
process.exitCode = results.some(r => r.status === 'failed') ? 1 : results.some(r => r.status === 'blocked') ? 2 : 0;
