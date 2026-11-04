const views = {
  cleanup: {title:'A thoughtful place <br>to start.',copy:'Measure common application caches and Trash, then review your next move. You choose what gets selected and what stays.',note:'Nothing selected. Nothing cleaned automatically.',alt:'Actual Nuke Sweep Cleanup screen with common caches and Trash'},
  developer: {title:'Build things. <br>Leave less behind.',copy:'Inspect familiar tool caches, review generated project storage, and remember frequently used folders with your own exclusions.',note:'Source-looking project roots are refused at review.',alt:'Actual Nuke Sweep Developer screen with Xcode, npm, Python and Gradle caches'},
  widgets: {title:'The useful things. <br>At a glance.',copy:'Add a Storage widget to your desktop, or use the menu-bar monitor for current storage, CPU, and memory readings.',note:'Widgets are snapshots. macOS controls refresh timing.',alt:'Nuke Sweep desktop storage widget preview and setup instructions'}
};
const tabs = [...document.querySelectorAll('[data-view]')];
function selectView(tab) {
  const view = views[tab.dataset.view];
  tabs.forEach(item => { const selected = item === tab; item.setAttribute('aria-selected', String(selected)); item.tabIndex = selected ? 0 : -1; });
  document.querySelector('#product-panel').setAttribute('aria-labelledby',tab.id);
  document.querySelector('#view-title').innerHTML = view.title;
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
