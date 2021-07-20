const [selector, timeout, mustBeVisible] = arguments;

let node;
let resolve;
let observer;
const res = new Promise(r => resolve = function(res) {
  observer && observer.disconnect();
  return r(res);
});

window.setTimeout(function() {
  return resolve(false);
}, timeout);

bootstrap();
return res;

function bootstrap() {
  if (node = findNode()) {
    return resolve(node);
  }

  observer = new MutationObserver(() => {
    if (node = findNode()) {
      return resolve(node);
    }
  });

  observer.observe(document.body, {
    subtree: true,
    childList: true,
    attributes: true,
  });

  return res;
}

function isVisible(node) {
  const { visibility } = window.getComputedStyle(node) || {};
  const { top, bottom, width, height } = node.getBoundingClientRect();
  return visibility !== "hidden" && top && bottom && width && height;
}

function findNode() {
  const node = document.querySelector(selector);
  if (node && (mustBeVisible && isVisible(node) || !mustBeVisible)) {
    return node;
  }

  return null;
}
