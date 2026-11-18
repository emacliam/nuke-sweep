const views = {
  cleanup: {
    title: 'Check what’s taking up space',
    copy: 'Check application caches, developer build output, Trash, and personal files. See which items can be rebuilt and what needs a closer look.',
    note: 'Scans leave files in place. Automatic cleanup is off by default.',
    alt: 'Nuke Sweep 0.9.3 Cleanup screen showing the Check This Mac action'
  },
  developer: {
    title: 'Review developer storage',
    copy: 'Find large project dependencies and build folders, inspect Docker usage, and switch directly to simulator devices and runtimes.',
    note: 'Review individual items before moving them to Trash.',
    alt: 'Nuke Sweep 0.9.3 Developer screen with dedicated tabs and cache sizes'
  },
  files: {
    title: 'See what each folder contains',
    copy: 'Expand folders in the file tree, inspect individual files, and add eligible items to your cleanup basket.',
    note: 'Use Quick Look to preview supported files before review.',
    alt: 'Nuke Sweep 0.9.3 Files screen with folder shortcuts, volume selection, and scan controls'
  }
};
const tabs = [...document.querySelectorAll('[data-view]')];
function selectView(tab) {
  const view = views[tab.dataset.view];
  tabs.forEach(item => { const selected = item === tab; item.setAttribute('aria-selected', String(selected)); item.tabIndex = selected ? 0 : -1; });
  document.querySelector('#product-panel').setAttribute('aria-labelledby',tab.id);
  document.querySelector('#view-title').textContent = view.title;
  document.querySelector('#view-copy').textContent = view.copy;
  document.querySelector('#view-note').textContent = view.note;
  const image = document.querySelector('#view-image'); image.src = `/assets/${tab.dataset.view}.png`; image.alt = view.alt;
}
tabs.forEach((tab,index) => {
  tab.addEventListener('click', () => selectView(tab));
  tab.addEventListener('keydown', event => {
    let next;
    if(event.key === 'ArrowRight') next = (index+1)%tabs.length;
    else if(event.key === 'ArrowLeft') next = (index+tabs.length-1)%tabs.length;
    else if(event.key === 'Home') next = 0;
    else if(event.key === 'End') next = tabs.length-1;
    if(next !== undefined){event.preventDefault();tabs[next].focus();selectView(tabs[next]);}
  });
});
const menu = document.querySelector('.menu-toggle');
const navigation = document.querySelector('#navigation');
menu?.addEventListener('click', () => { const expanded = menu.getAttribute('aria-expanded') !== 'true'; menu.setAttribute('aria-expanded',String(expanded)); navigation.classList.toggle('open',expanded); });
navigation?.querySelectorAll('a').forEach(link => link.addEventListener('click', () => {menu?.setAttribute('aria-expanded','false');navigation.classList.remove('open');}));
document.addEventListener('keydown', event => {if(event.key==='Escape' && menu?.getAttribute('aria-expanded')==='true'){menu.setAttribute('aria-expanded','false');navigation.classList.remove('open');menu.focus();}});
