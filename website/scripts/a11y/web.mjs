import assert from 'node:assert/strict';
import { mkdir, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import path from 'node:path';
import { chromium, webkit } from 'playwright';
import AxeBuilder from '@axe-core/playwright';
import { startFixture } from './fixture.mjs';
import sharp from 'sharp';

const output = process.env.EXP_A11Y_OUTPUT;
if (!output?.includes('/output/a11y/')) throw Error('Use the accessibility runner');
await mkdir(output, { recursive: true });
const fixture = await startFixture(), results = [];
const avatarFixture=await sharp({create:{width:160,height:120,channels:3,background:'#8ccb48'}}).png().toBuffer();
const tabKeys = new WeakMap();
const variants = [
  { name: 'chromium-dark', engine: chromium, colorScheme: 'dark', width: 1280 },
  { name: 'chromium-light-mobile', engine: chromium, colorScheme: 'light', width: 390, reducedMotion: 'reduce' },
  { name: 'webkit-dark', engine: webkit, colorScheme: 'dark', width: 1280 },
  { name: 'webkit-light-mobile', engine: webkit, colorScheme: 'light', width: 390, reducedMotion: 'reduce' }
];

async function check(name, page, fn) {
  const file = name.replace(/[^a-z0-9-]/gi, '-');
  // Separate journeys share one loopback IP. Service tests independently prove
  // shared rate enforcement; do not accumulate unrelated scenario traffic here.
  try { await fixture.resetIPWindow(); await fn(); results.push({ name, status: 'passed' }); }
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
async function tabTo(page, locator, maximum) {
  // Bound a full page traversal as the account navigation grows. Hidden/disabled
  // controls only make this ceiling conservative; actual keyboard focus is tested.
  const budget = maximum ?? Math.max(35, await page.locator('a[href], button, input, select, textarea, summary, [tabindex]').count() + 2);
  for (let i = 0; i < budget; i++) {
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
      await check(`${variant.name}-news-public`,page,async()=>{
        const accountCalls=[];const observe=r=>{if(new URL(r.url()).pathname==='/api/account')accountCalls.push(r.method());};page.on('request',observe);
        try{await page.goto(`${fixture.origin}/news`);await page.getByRole('heading',{name:'News and updates.',exact:true}).waitFor();
          await page.getByRole('heading',{name:'EXP 2.6: a smoother canvas, and tools for everyday work.'}).waitFor();
          assert.ok(accountCalls.length<=1);assert.ok(accountCalls.every(method=>method==='GET'),'Only optional header session lookup is allowed');assert.equal((await context.cookies()).length,0);
          assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await scan(`${variant.name}-news`,page);
        }finally{page.off('request',observe);}
      });
      await check(`${variant.name}-account-registration-keyboard`, page, async () => {
        await page.goto(`${fixture.origin}/account`);
        const create = page.getByRole('radio', { name: 'Create account' });
        await create.waitFor();
        await tabTo(page, page.getByRole('radio', { name: 'Sign in', exact: true }));
        await page.keyboard.press('ArrowRight');
        assert.ok(await create.isChecked());
        await type(page, page.getByLabel('Email address'), email);
        await type(page, page.getByLabel('Display name'), 'Keyboard Designer');
        await tabTo(page, page.getByRole('checkbox', { name: /Create my optional EXP account/ })); await page.keyboard.press('Space');
        await tabTo(page, page.getByRole('button', { name: 'Email me a code' })); await page.keyboard.press('Enter');
        const code = page.getByLabel('Six-digit code'); await code.waitFor();
        assert.ok(await code.evaluate(el => document.activeElement === el), 'Code field must receive focus');
        const mail = fixture.mail.findLast(item => item.kind === 'account' && item.email === email); assert.ok(mail);
        await page.keyboard.type(mail.otp); await page.keyboard.press('Enter');
        await page.getByRole('heading', { name: 'Hello, Keyboard Designer.' }).waitFor();
        await page.waitForFunction(() => document.activeElement?.id === 'account-title');
        await scan(`${variant.name}-overview`, page);
      });
      await check(`${variant.name}-account-menu-keyboard`,page,async()=>{
        const trigger=page.getByRole('button',{name:/Account menu for Keyboard Designer/});
        await trigger.waitFor();assert.equal(await trigger.getAttribute('aria-expanded'),'false');
        await tabTo(page,trigger);await page.keyboard.press('Enter');
        assert.equal(await trigger.getAttribute('aria-expanded'),'true');await scan(`${variant.name}-account-menu`,page);
        await page.screenshot({path:path.join(output,`${variant.name}-avatar-menu-open.png`),fullPage:false});
        await page.keyboard.press(tabKeys.get(page)||'Tab');assert.equal(await page.locator('.account-popover a').first().evaluate(el=>el===document.activeElement),true);
        await page.keyboard.press('Escape');assert.equal(await trigger.getAttribute('aria-expanded'),'false');
        assert.equal(await trigger.evaluate(el=>el===document.activeElement),true);
        await page.keyboard.press('Enter');await page.locator('main').click({position:{x:2,y:2}});assert.equal(await trigger.getAttribute('aria-expanded'),'false');
        const box=await trigger.boundingBox();assert.ok(box.width>=44 && box.height>=44);
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
      await check(`${variant.name}-private-photo-upload-retry-remove`,page,async()=>{
        const upload=page.getByLabel('Choose a profile photo (PNG, JPEG or WebP, up to 5 MB)');
        await type(page,page.getByLabel('Bio (optional, up to 500 characters)'),'Unsaved private draft stays while saving a photo.');
        await upload.setInputFiles({name:'fixture-photo.png',mimeType:'image/png',buffer:avatarFixture});
        const save=page.getByRole('button',{name:'Save profile photo',exact:true});await save.waitFor();
        let firstImage,retryImage;
        const lost=async route=>{
          const payload=route.request().postDataJSON();if(payload?.action!=='save-avatar')return route.continue();
          if(!firstImage){firstImage=payload.image;assert.equal((await route.fetch()).status(),200);return route.fulfill({status:503,contentType:'application/json',body:JSON.stringify({error:'Photo response interrupted. Retry your preview.'})});}
          retryImage=payload.image;return route.continue();
        };
        await page.route('**/api/account',lost);await tabTo(page,save);await page.keyboard.press('Enter');
        await page.getByRole('status').filter({hasText:'Photo response interrupted.'}).waitFor();
        await page.waitForFunction(()=>document.activeElement?.textContent==='Save profile photo');await page.keyboard.press('Enter');
        await page.getByRole('status').filter({hasText:'Profile photo saved.'}).waitFor();await page.unroute('**/api/account',lost);
        assert.equal(firstImage,retryImage);assert.equal(await page.getByLabel('Bio (optional, up to 500 characters)').inputValue(),'Unsaved private draft stays while saving a photo.');
        assert.match(await page.locator('.account-avatar-button img').getAttribute('src'),/^data:image\/webp;base64,/);
        await page.reload();await page.getByRole('button',{name:'Remove profile photo'}).waitFor();
        assert.match(await page.locator('.account-avatar-button img').getAttribute('src'),/^data:image\/webp;base64,/);
        await scan(`${variant.name}-profile-photo`,page);await page.screenshot({path:path.join(output,`${variant.name}-profile-photo.png`),fullPage:true});
        const photoMenu=page.getByRole('button',{name:/Account menu for Updated Keyboard Designer/});
        await tabTo(page,photoMenu);await page.keyboard.press('Enter');
        await page.screenshot({path:path.join(output,`${variant.name}-profile-photo-menu.png`),fullPage:false});await page.keyboard.press('Escape');
        await tabTo(page,page.getByRole('button',{name:'Remove profile photo'}));await page.keyboard.press('Enter');
        await page.getByRole('status').filter({hasText:'Profile photo removed.'}).waitFor();await page.waitForFunction(()=>document.activeElement?.id==='profile-photo');
        assert.equal(await page.locator('.account-avatar-button img').count(),0);
        await upload.setInputFiles({name:'script.svg',mimeType:'image/svg+xml',buffer:Buffer.from('<svg/>')});
        await page.getByRole('status').filter({hasText:'Choose a PNG, JPEG or WebP photo up to 5 MB.'}).waitFor();
        assert.equal(await page.getByRole('button',{name:'Save profile photo'}).count(),0);
      });
      await check(`${variant.name}-news-permission-keyboard`,page,async()=>{
        await page.goto(`${fixture.origin}/account/preferences`);
        const choice=page.getByRole('checkbox',{name:'Email me occasional EXP development news',exact:false});await choice.waitFor();assert.equal(await choice.isChecked(),false);
        await tabTo(page,choice);await page.keyboard.press('Space');
        await tabTo(page,page.getByRole('button',{name:'Save news permission'}));await page.keyboard.press('Enter');
        await page.getByRole('status').filter({hasText:'Development-news permission saved.'}).waitFor();
        await page.reload();await choice.waitFor();assert.equal(await choice.isChecked(),true);await scan(`${variant.name}-news-permission`,page);
        await tabTo(page,choice);await page.keyboard.press('Space');await tabTo(page,page.getByRole('button',{name:'Save news permission'}));await page.keyboard.press('Enter');
        await page.getByRole('status').filter({hasText:'Development-news email permission is off.'}).waitFor();
      });
      await check(`${variant.name}-tickets-author-support-keyboard`,page,async()=>{
        await page.goto(`${fixture.origin}/account/tickets`);
        const subject=page.getByLabel('Subject (up to 120 characters)');await subject.waitFor();
        const alerts=page.getByRole('checkbox',{name:'Email me about ticket replies',exact:false});
        assert.equal(await alerts.isChecked(),true);
        let releaseChoice;const choiceGate=new Promise(resolve=>{releaseChoice=resolve;});let choiceRequests=0;
        const holdChoice=async route=>{if(route.request().postDataJSON()?.action!=='save-ticket-preferences')return route.continue();choiceRequests++;await choiceGate;return route.continue();};
        await page.route('**/api/account',holdChoice);
        try{
          await tabTo(page,alerts);await page.keyboard.press('Space');await page.getByRole('status').filter({hasText:'Saving ticket email choice…'}).waitFor();
          assert.equal(await alerts.getAttribute('aria-disabled'),'true');assert.equal(await alerts.evaluate(element=>element===document.activeElement),true);
          await page.keyboard.press('Space');assert.equal(choiceRequests,1,'Repeat activation while saving must be suppressed');
        }finally{releaseChoice();}
        await page.getByRole('status').filter({hasText:'Ticket email choice saved.'}).waitFor();assert.equal(await alerts.isChecked(),false);
        assert.equal(await alerts.evaluate(element=>element===document.activeElement),true,'Saving the checkbox must retain keyboard focus');
        await page.unroute('**/api/account',holdChoice);
        await page.reload();await subject.waitFor();assert.equal(await alerts.isChecked(),false);
        await tabTo(page,alerts);await page.keyboard.press('Space');await page.getByRole('status').filter({hasText:'Ticket email choice saved.'}).waitFor();
        await scan(`${variant.name}-tickets-empty`,page);
        await type(page,subject,'Private pattern question');
        const literal='<img src=x onerror=alert(1)> '+ 'private-ticket-'.repeat(25);
        await type(page,page.getByLabel('What can we help with? (up to 1,500 characters)'),literal);
        let firstId,retryId;
        await page.route('**/api/account',async route=>{
          const body=route.request().postDataJSON();if(body?.action!=='create-ticket')return route.continue();
          if(!firstId){firstId=body.id;const committed=await route.fetch();assert.equal(committed.status(),200);return route.fulfill({status:503,contentType:'application/json',body:JSON.stringify({error:'Response interrupted after local commit. Retry the same draft.'})});}
          retryId=body.id;return route.continue();
        });
        const send=page.getByRole('button',{name:'Open ticket',exact:true});await tabTo(page,send);await page.keyboard.press('Enter');
        await page.getByRole('status').filter({hasText:'Response interrupted'}).waitFor();assert.equal(await subject.inputValue(),'Private pattern question');
        await tabTo(page,send);await page.keyboard.press('Enter');
        await page.getByRole('status').filter({hasText:'Ticket received.'}).waitFor();await page.unroute('**/api/account');assert.equal(retryId,firstId);
        await page.waitForFunction(()=>document.activeElement?.id==='ticket-thread-title');
        assert.equal(await page.locator('.ticket-events li').count(),1);assert.equal(await page.locator('.ticket-events .account-feedback-message').textContent(),literal);assert.equal(await page.locator('.ticket-events img').count(),0);
        await type(page,page.getByLabel('Your reply (up to 1,500 characters)'),'Extra detail from the author.');
        await tabTo(page,page.getByRole('button',{name:'Send reply',exact:true}));await page.keyboard.press('Enter');await page.getByRole('status').filter({hasText:'Reply saved.'}).waitFor();
        await scan(`${variant.name}-ticket-author`,page);
        const staffContext=await browser.newContext({colorScheme:variant.colorScheme,viewport:{width:variant.width,height:1000}});
        try{
          await staffContext.route('**/*',route=>new URL(route.request().url()).origin===fixture.origin?route.continue():route.fulfill({status:200,body:'',contentType:'text/css'}));
          const staffEmail=`support-${email}`;
          assert.equal((await staffContext.request.post(`${fixture.origin}/api/account`,{headers:{origin:fixture.origin},data:{action:'send-code',email:staffEmail}})).status(),200);
          const otp=fixture.mail.findLast(item=>item.kind==='account' && item.email===staffEmail).otp;
          assert.equal((await staffContext.request.post(`${fixture.origin}/api/account`,{headers:{origin:fixture.origin},data:{action:'verify-code',email:staffEmail,otp,intent:'register',name:'Support Tester',accountConsent:true,consentVersion:'free-account-v1'}})).status(),200);
          const denied=await staffContext.request.post(`${fixture.origin}/api/account`,{headers:{origin:fixture.origin},data:{action:'ticket',id:firstId}});assert.equal(denied.status(),404);
          await fixture.supportGrant(staffEmail);await fixture.resetIPWindow();
          const staffPage=await staffContext.newPage();tabKeys.set(staffPage,variant.engine===webkit?'Alt+Tab':'Tab');
          await staffPage.goto(`${fixture.origin}/account/support?ticket=${firstId}`);await staffPage.getByLabel('Your reply (up to 1,500 characters)').waitFor();
          assert.equal(await staffPage.locator('summary').filter({hasText:'Delete this ticket'}).count(),0);
          await type(staffPage,staffPage.getByLabel('Your reply (up to 1,500 characters)'),'Resize the pattern bounds in its editor.');await tabTo(staffPage,staffPage.getByRole('button',{name:'Send reply',exact:true}));await staffPage.keyboard.press('Enter');
          await staffPage.getByRole('status').filter({hasText:'Reply saved.'}).waitFor();await scan(`${variant.name}-ticket-support`,staffPage);
          const noticesBefore=fixture.mail.filter(item=>item.kind==='ticket' && item.to===email).length;
          await fixture.processTicketMail();
          const notices=fixture.mail.filter(item=>item.kind==='ticket' && item.to===email);
          assert.equal(notices.length,noticesBefore+1);assert.ok(notices.at(-1).text.includes(`/account/tickets?ticket=${firstId}`));
          assert.doesNotMatch(JSON.stringify(notices.at(-1)),/Private pattern question|Resize the pattern bounds/);
          await staffPage.screenshot({path:path.join(output,`${variant.name}-ticket-support.png`),fullPage:true});
          await fixture.supportGrant(staffEmail,false);
          await tabTo(staffPage,staffPage.getByRole('button',{name:'Refresh tickets'}));await staffPage.keyboard.press('Enter');
          await staffPage.getByRole('status').filter({hasText:/Support access is not available|Ticket not found/}).waitFor();assert.equal(await staffPage.locator('.ticket-events').count(),0);
        }finally{await staffContext.close();}
        await tabTo(page,page.getByRole('button',{name:'Refresh tickets'}));await page.keyboard.press('Enter');await page.getByText('Resize the pattern bounds in its editor.',{exact:true}).waitFor();
        await tabTo(page,page.getByRole('button',{name:'Close ticket',exact:true}));await page.keyboard.press('Enter');await page.getByRole('status').filter({hasText:'Ticket closed.'}).waitFor();assert.equal(await page.getByLabel('Your reply (up to 1,500 characters)').count(),0);
        await tabTo(page,page.getByRole('button',{name:'Reopen ticket',exact:true}));await page.keyboard.press('Enter');await page.getByRole('status').filter({hasText:'Ticket reopened.'}).waitFor();
        assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await scan(`${variant.name}-ticket-reopened`,page);
        await page.screenshot({path:path.join(output,`${variant.name}-ticket-author.png`),fullPage:true});
        await tabTo(page,page.locator('summary').filter({hasText:'Delete this ticket'}));await page.keyboard.press('Enter');await type(page,page.getByLabel('Type DELETE to remove this ticket'),'DELETE');
        await tabTo(page,page.getByRole('button',{name:'Delete ticket permanently'}));await page.keyboard.press('Enter');await page.getByRole('status').filter({hasText:'Ticket and its replies deleted.'}).waitFor();
        await page.waitForFunction(()=>document.activeElement?.textContent==='Your tickets');assert.equal(await page.locator('.ticket-events').count(),0);
      });
      await check(`${variant.name}-community-profile-keyboard`, page, async () => {
        await page.goto(`${fixture.origin}/account/community`);
        const handle=page.getByLabel('Handle (3–30 letters, numbers or hyphens)');await handle.waitFor();
        const name=page.getByLabel('Public display name (up to 80 characters)');
        assert.equal(await name.inputValue(),'','Private identity must not be copied automatically');
        const slug=`public-${variant.name}`;
        await type(page,handle,slug);await type(page,name,'Public Keyboard Designer');
        await type(page,page.getByLabel('Public bio (optional, up to 500 characters)'),'<img src=x onerror=alert(1)> Public text only.');
        await type(page,page.getByLabel('Public website (optional HTTPS link)'),'https://example.test/public-work');
        await tabTo(page,page.getByRole('button',{name:'Save and preview'}));await page.keyboard.press('Enter');
        const preview=page.getByRole('heading',{name:'Public preview',exact:true});await preview.waitFor();
        await page.waitForFunction(()=>document.activeElement?.textContent==='Public preview');
        const publish=page.getByRole('button',{name:'Publish community profile',exact:true});
        assert.ok(await publish.isDisabled());
        assert.equal((await context.request.get(`${fixture.origin}/api/people?handle=${slug}`)).status(),404);
        await scan(`${variant.name}-community-preview`,page);
        await tabTo(page,page.getByRole('checkbox',{name:'Publish these previewed details publicly.'}));await page.keyboard.press('Space');
        await tabTo(page,publish);await page.keyboard.press('Enter');
        await page.getByRole('status').filter({hasText:'Your community profile is published.'}).waitFor();
        await page.waitForFunction(()=>document.activeElement?.textContent==='Publication status');
        await page.reload();await page.getByRole('button',{name:'Unpublish community profile'}).waitFor();
        await scan(`${variant.name}-community-published-editor`,page);
        await page.screenshot({path:path.join(output,`${variant.name}-community-editor.png`),fullPage:true});

        // A second verified member reports through actual HTTP cookies and UI.
        // Captured mail replaces only delivery, never the account/database code.
        const reporterContext=await browser.newContext({colorScheme:variant.colorScheme,viewport:{width:variant.width,height:1000}});
        try{
          await reporterContext.route('**/*',route=>new URL(route.request().url()).origin===fixture.origin?route.continue():route.fulfill({status:200,body:'',contentType:'text/css'}));
          const reporterEmail=`report-${email}`;
          assert.equal((await reporterContext.request.post(`${fixture.origin}/api/account`,{headers:{origin:fixture.origin},data:{action:'send-code',email:reporterEmail}})).status(),200);
          const otp=fixture.mail.findLast(item=>item.kind==='account' && item.email===reporterEmail).otp;
          assert.equal((await reporterContext.request.post(`${fixture.origin}/api/account`,{headers:{origin:fixture.origin},data:{action:'verify-code',email:reporterEmail,otp,intent:'register',name:'Private Reporter',accountConsent:true,consentVersion:'free-account-v1'}})).status(),200);
          const reader=await reporterContext.newPage();tabKeys.set(reader,variant.engine===webkit?'Alt+Tab':'Tab');
          const publicRequest=reader.waitForRequest(r=>new URL(r.url()).pathname==='/api/people');
          await reader.goto(`${fixture.origin}/people/${slug}`);
          assert.equal((await publicRequest).headers().cookie,undefined,'Public read must omit account cookie');
          await reader.getByText('Public Keyboard Designer',{exact:true}).waitFor();
          assert.equal(await reader.locator('.community-public-card img').count(),0);
          assert.equal(await reader.locator('.community-public-card').getByText('Private Reporter',{exact:true}).count(),0);
          await scan(`${variant.name}-community-public`,reader);
          await reader.screenshot({path:path.join(output,`${variant.name}-community-public.png`),fullPage:true});
          await tabTo(reader,reader.locator('summary').filter({hasText:'Report this profile'}));await reader.keyboard.press('Enter');
          const category=reader.getByLabel('Reason category');await tabTo(reader,category);await reader.keyboard.type('p');await reader.keyboard.press(tabKeys.get(reader)||'Tab');
          await type(reader,reader.getByLabel('What should we review? (up to 500 characters)'),'Please review this public detail.');
          await tabTo(reader,reader.getByRole('button',{name:'Send private report'}));await reader.keyboard.press('Enter');
          await reader.getByRole('status').filter({hasText:'Report received privately'}).waitFor();
          await scan(`${variant.name}-community-report-received`,reader);
          assert.ok(await reader.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
          await tabTo(page,page.getByRole('button',{name:'Unpublish community profile'}));await page.keyboard.press('Enter');
          await page.getByRole('status').filter({hasText:'Your community profile is unpublished.'}).waitFor();
          await page.waitForFunction(()=>document.activeElement?.textContent==='Publication status');
          await reader.reload();await reader.getByRole('status').filter({hasText:'Profile not found.'}).waitFor();
          assert.equal(await reader.locator('.community-public-card').count(),0);
        }finally{await reporterContext.close();}
        assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
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
        await tabTo(page, page.getByRole('checkbox', { name: /Email me about the proposed EXP Pro offer/ })); await page.keyboard.press('Space');
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
        await page.goto(`${fixture.origin}/account/community`);
        await page.getByLabel('Public display name (up to 80 characters)').waitFor();
        assert.equal(await page.locator('.account-page').evaluate(el=>getComputedStyle(el).fontSize),'20px');
        assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
        await scan(`${variant.name}-community-large`,page);
        await page.goto(`${fixture.origin}/account/tickets`);await page.getByLabel('Subject (up to 120 characters)').waitFor();
        assert.equal(await page.locator('.account-page').evaluate(el=>getComputedStyle(el).fontSize),'20px');
        assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));await scan(`${variant.name}-tickets-large`,page);
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
        const permission = page.getByRole('checkbox', { name: /Email me about the proposed EXP Pro offer/ }); await tabTo(page, permission); await page.keyboard.press('Space');
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
      await check(`${variant.name}-account-explanation-and-guest-menu`,page,async()=>{
        await page.route('**/api/account',route=>route.fulfill({status:503,contentType:'application/json',body:JSON.stringify({error:'Accounts temporarily unavailable.'})}));
        await page.goto(`${fixture.origin}/accounts`);await page.getByRole('heading',{name:'Your corner of EXP.',level:1}).waitFor();
        await page.getByText('Settings sync is not available today.',{exact:false}).waitFor();
        const guest=page.getByRole('button',{name:'Sign in or create an EXP account',exact:true});
        await tabTo(page,guest);await page.keyboard.press('Enter');await page.getByText('Account service is unavailable right now.',{exact:false}).waitFor();
        assert.equal(await page.locator('.account-popover').getByRole('link',{name:'Download EXP',exact:true}).isVisible(),true);
        await scan(`${variant.name}-account-about-menu`,page);assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
        await page.keyboard.press('Escape');await page.unroute('**/api/account');
        await page.goto(`${fixture.origin}/account?intent=register`);await page.getByRole('radio',{name:'Create account'}).waitFor();
        assert.equal(await page.getByRole('radio',{name:'Create account'}).isChecked(),true);
      });
      await check(`${variant.name}-header-signout-clears-other-tab`,page,async()=>{
        const address=`header-${email}`;
        assert.equal((await context.request.post(`${fixture.origin}/api/account`,{headers:{origin:fixture.origin},data:{action:'send-code',email:address}})).status(),200);
        const otp=fixture.mail.findLast(item=>item.kind==='account' && item.email===address).otp;
        assert.equal((await context.request.post(`${fixture.origin}/api/account`,{headers:{origin:fixture.origin},data:{action:'verify-code',email:address,otp,intent:'register',name:'Header Tester',accountConsent:true,consentVersion:'free-account-v1'}})).status(),200);
        await page.goto(`${fixture.origin}/news`);const trigger=page.getByRole('button',{name:/Account menu for Header Tester/});await trigger.waitFor();
        const second=await context.newPage();
        try{
          await second.goto(`${fixture.origin}/news`);await second.getByRole('button',{name:/Account menu for Header Tester/}).waitFor();
          await tabTo(page,trigger);await page.keyboard.press('Enter');await tabTo(page,page.locator('.account-popover').getByRole('button',{name:'Sign out',exact:true}));await page.keyboard.press('Enter');
          await page.getByRole('button',{name:'Sign in or create an EXP account',exact:true}).waitFor();
          await second.getByRole('button',{name:'Sign in or create an EXP account',exact:true}).waitFor();
          assert.equal((await (await context.request.get(`${fixture.origin}/api/account`)).json()).user,null);
        }finally{await second.close();}
      });
      await check(`${variant.name}-account-first-download`,page,async()=>{
        await page.goto(`${fixture.origin}/download`);
        await page.getByRole('heading',{name:'Make something with EXP [design].',level:1}).waitFor();
        assert.equal(await page.getByRole('textbox',{name:'email',exact:true}).count(),0);
        const account=page.locator('.member-callout-account'),pro=page.locator('.member-callout-pro');
        const alsoPro=account.getByRole('checkbox');assert.equal(await alsoPro.isChecked(),false);
        await tabTo(page,alsoPro);await page.keyboard.press('Space');
        assert.match(await account.getByRole('link',{name:/create a free account/}).getAttribute('href'),/next=pro/);
        const alsoAccount=pro.getByRole('checkbox');assert.equal(await alsoAccount.isChecked(),false);
        await tabTo(page,alsoAccount);await page.keyboard.press('Space');
        assert.match(await pro.getByRole('link',{name:/interested in Pro/}).getAttribute('href'),/next=account/);
        assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
        await scan(`${variant.name}-account-first-panels`,page);
      });
      await check(`${variant.name}-member-feedback-permission`,page,async()=>{
        const address=`growth-${email}`;
        assert.equal((await context.request.post(`${fixture.origin}/api/account`,{headers:{origin:fixture.origin},data:{action:'send-code',email:address}})).status(),200);
        const otp=fixture.mail.findLast(item=>item.kind==='account'&&item.email===address).otp;
        assert.equal((await context.request.post(`${fixture.origin}/api/account`,{headers:{origin:fixture.origin},data:{action:'verify-code',email:address,otp,intent:'register',name:'Growth Tester',accountConsent:true,consentVersion:'free-account-v1'}})).status(),200);
        await page.goto(`${fixture.origin}/account/feedback`);
        const subject=page.getByLabel('Subject (up to 120 characters)');await subject.waitFor();
        await page.getByLabel('What are you sending?').selectOption('feature');
        await type(page,subject,'Reusable handoff preset');await type(page,page.getByLabel('What would you like me to know? (up to 1,500 characters)'),'Please make a useful preset.');
        const permission=page.getByRole('checkbox',{name:/Optional: EXP may quote/});assert.equal(await permission.isChecked(),false);
        await tabTo(page,permission);await page.keyboard.press('Space');
        await type(page,page.getByLabel('First name',{exact:true}),'Alex');await type(page,page.getByLabel('Last initial',{exact:true}),'R');
        await page.getByText('Attribution preview:',{exact:false}).waitFor();
        await tabTo(page,page.getByRole('button',{name:'Send feature request',exact:true}));await page.keyboard.press('Enter');
        await page.getByRole('status').filter({hasText:'Your private note was saved.'}).waitFor();
        await page.getByText('Testimonial permission granted as Alex R.',{exact:true}).waitFor();
        await scan(`${variant.name}-member-feedback-consent`,page);
        await tabTo(page,page.getByRole('button',{name:'Withdraw testimonial permission',exact:true}));await page.keyboard.press('Enter');
        await page.getByRole('status').filter({hasText:'Testimonial permission withdrawn.'}).waitFor();
        await page.reload();await page.getByText('Private feedback. No current testimonial permission.',{exact:true}).waitFor();
        await scan(`${variant.name}-member-feedback-withdrawn`,page);
      });
      await check(`${variant.name}-member-copy-action`,page,async()=>{
        const read=async()=>{const response=await context.request.post(`${fixture.origin}/api/account`,{headers:{origin:fixture.origin},data:{action:'engagement'}});assert.equal(response.status(),200);return response.json();};
        await page.goto(`${fixture.origin}/account/share`);const copy=page.getByRole('button',{name:'copy link',exact:true});await copy.waitFor();
        const before=(await read()).shareActions;
        await tabTo(page,copy);await page.keyboard.press('Enter');
        const status=page.locator('.share-tools [role=status]');await status.filter({hasText:/Link copied|Select and copy/}).waitFor();
        if((await status.textContent()).includes('Link copied')){
          await page.waitForFunction(async expected=>(await (await fetch('/api/account',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action:'engagement'})})).json()).shareActions===expected,before+1);
        }else{assert.equal((await read()).shareActions,before);await page.getByLabel('Link to copy',{exact:true}).waitFor();}
      });
      await check(`${variant.name}-optional-referral-credit`,page,async()=>{
        const summary=await context.request.post(`${fixture.origin}/api/account`,{headers:{origin:fixture.origin},data:{action:'engagement'}});assert.equal(summary.status(),200);
        const code=(await summary.json()).shareCode;
        const recipient=await browser.newContext({viewport:{width:variant.width,height:1000}}),receiver=await recipient.newPage();
        try{
          tabKeys.set(receiver,variant.engine === webkit ? 'Alt+Tab' : 'Tab');
          await recipient.route('**/*',route=>new URL(route.request().url()).origin===fixture.origin?route.continue():route.fulfill({status:200,body:'',contentType:'text/css'}));
          await receiver.goto(`${fixture.origin}/?ref=${code}`);
          const create=receiver.locator('.hero-actions').getByRole('link',{name:'create a free account',exact:true});await create.waitFor();
          assert.ok((await create.getAttribute('href')).includes(`ref=${code}`));await create.click();
          await receiver.getByLabel('Email address').waitFor();const address=`credited-${email}`;
          await type(receiver,receiver.getByLabel('Email address'),address);await type(receiver,receiver.getByLabel('Display name'),'New Member');
          const credit=receiver.getByRole('checkbox',{name:/Optional: credit the EXP member/});assert.equal(await credit.isChecked(),false);
          await tabTo(receiver,receiver.getByRole('checkbox',{name:/Create my optional EXP account/}));await receiver.keyboard.press('Space');
          await tabTo(receiver,credit);await receiver.keyboard.press('Space');
          await tabTo(receiver,receiver.getByRole('checkbox',{name:/Also show me the Pro-interest/}));await receiver.keyboard.press('Space');
          await tabTo(receiver,receiver.getByRole('button',{name:'Email me a code',exact:true}));await receiver.keyboard.press('Enter');
          const input=receiver.getByLabel('Six-digit code');await input.waitFor();
          const otp=fixture.mail.findLast(item=>item.kind==='account'&&item.email===address).otp;await type(receiver,input,otp);
          await tabTo(receiver,receiver.getByRole('button',{name:'Create my account',exact:true}));await receiver.keyboard.press('Enter');
          await receiver.getByRole('status').filter({hasText:'Your optional signup credit was saved.'}).waitFor();
          await receiver.getByRole('link',{name:'Continue to Pro interest',exact:true}).waitFor();
          const count=await context.request.post(`${fixture.origin}/api/account`,{headers:{origin:fixture.origin},data:{action:'engagement'}});assert.equal((await count.json()).creditedSignups,1);
          await receiver.goto(`${fixture.origin}/account/share`);await receiver.getByRole('button',{name:'Withdraw my signup credit',exact:true}).waitFor();
          await scan(`${variant.name}-member-share`,receiver);
          await tabTo(receiver,receiver.getByRole('button',{name:'Withdraw my signup credit',exact:true}));await receiver.keyboard.press('Enter');
          await receiver.getByRole('status').filter({hasText:'Your optional signup credit has been withdrawn.'}).waitFor();
          const cleared=await context.request.post(`${fixture.origin}/api/account`,{headers:{origin:fixture.origin},data:{action:'engagement'}});assert.equal((await cleared.json()).creditedSignups,0);
        }finally{await recipient.close();}
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
