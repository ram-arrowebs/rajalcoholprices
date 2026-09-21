// Add to Home Screen
let deferredPrompt;
const addBtn = document.querySelector(".add-button");
addBtn.style.display = "none";

// Chrome only fires this once the manifest passes its installability checks
// (which include 192px and 512px icons). It can fire more than once per
// page, so only stash the event here; the click handler is registered once.
window.addEventListener("beforeinstallprompt", (e) => {
  // Prevent Chrome 67 and earlier from automatically showing the prompt
  e.preventDefault();
  deferredPrompt = e;
  addBtn.style.display = "block";
});

addBtn.addEventListener("click", () => {
  addBtn.style.display = "none";
  if (!deferredPrompt) return;
  const promptEvent = deferredPrompt;
  deferredPrompt = null;
  promptEvent.prompt();
  promptEvent.userChoice.then((choiceResult) => {
    console.log(
      choiceResult.outcome === "accepted"
        ? "User accepted the A2HS prompt"
        : "User dismissed the A2HS prompt"
    );
  });
});

window.addEventListener("appinstalled", () => {
  deferredPrompt = null;
  addBtn.style.display = "none";
});
