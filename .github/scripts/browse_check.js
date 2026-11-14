// CI: a script as Claude would write it to try a page, run with browse (setup/claude/bin/browse).
//   browse browse_check.js <page.html> <picture> [the address of a page on the internet]
// Fills in the form of browse_shop.html, sends it, prints what the page says then (BROWSE-SAID), makes a picture,
// and with an address also prints the title of that page (BROWSE-TITLE).
const { chromium } = require('playwright-core');
const path = require('path');
const [form, picture, internet] = process.argv.slice(2);
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto('file://' + path.resolve(form));
  await page.fill('#name', 'Mina');
  await page.selectOption('#product', 'Coffee');
  await page.click('#go');
  console.log('BROWSE-SAID ' + await page.textContent('#out'));
  await page.screenshot({ path: picture });
  if (internet) {
    await page.goto(internet, { timeout: 60000 });
    console.log('BROWSE-TITLE ' + await page.title());
  }
  await browser.close();
})().catch(e => { console.log('BROWSE-ERROR ' + String(e && e.message).split('\n')[0]); process.exit(1); });
