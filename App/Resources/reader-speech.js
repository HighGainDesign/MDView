// App-owned isolated-world bridge. Document scripts stay disabled.
const main = document.getElementById('document');
if (!main) return null;
if (operation === 'highlight') {
    for (const old of main.querySelectorAll('.mdview-speaking')) old.classList.remove('mdview-speaking');
    if (!elementID) return true;
    const target = Array.from(main.querySelectorAll('[data-mdview-speech]')).find(node => node.dataset.mdviewSpeech === elementID);
    if (!target) return false;
    target.classList.add('mdview-speaking');
    if (follow) target.scrollIntoView({block:'nearest',behavior:matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth'});
    return true;
}
if (operation !== 'locate') return null;
if (mode === 'visible') {
    const nodes = Array.from(main.querySelectorAll('[data-mdview-speech]'));
    const target = nodes.find(node => node.getBoundingClientRect().bottom > 0) ?? nodes.at(-1);
    return target ? {elementID:target.dataset.mdviewSpeech,offset:0} : null;
}
const selection = getSelection();
if (!selection?.rangeCount) return null;
const range = selection.getRangeAt(0);
let start = range.startContainer.nodeType === Node.ELEMENT_NODE ? range.startContainer : range.startContainer.parentElement;
let target = start?.closest?.('[data-mdview-speech]');
if (!target && start && main.contains(start)) {
    const child = start.childNodes[range.startOffset];
    if (child?.nodeType === Node.ELEMENT_NODE) target = child.matches('[data-mdview-speech]') ? child : child.querySelector('[data-mdview-speech]');
    if (!target) target = Array.from(main.querySelectorAll('[data-mdview-speech]')).find(node => range.intersectsNode(node));
}
if (!target || !main.contains(target)) return null;
let offset = 0;
if (target.contains(range.startContainer)) {
    const prefix = document.createRange(); prefix.selectNodeContents(target);
    prefix.setEnd(range.startContainer,range.startOffset);
    offset = prefix.toString().length;
}
return {elementID:target.dataset.mdviewSpeech,offset};
