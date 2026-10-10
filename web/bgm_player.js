// Long BGM streams through browser HTMLAudioElement, independent of Godot's render loop.
(() => {
 "use strict";
 if (window.__kanaBgm) return;
 const audio = new Audio();
 audio.preload = "none";
 let tracks = [], index = -1, mode = 1, pending = false;
 function start() {
   if (index < 0 || !audio.src) return;
   pending = true;
   const attempt = audio.play();
   if (attempt && typeof attempt.then === "function") {
     attempt.then(() => { pending = false; }).catch(error => {
       // Autoplay may be blocked until the next pointer/keyboard gesture.
       if (error.name !== "NotAllowedError" && error.name !== "AbortError") {
         console.warn("[kana-bgm] playback failed:", error);
       }
     });
   }
 }
 const bgm = {
   get index() { return index; },
   setTracks(paths) {
     tracks = paths.slice();
     if (index >= tracks.length) {
       audio.pause(); audio.removeAttribute("src"); audio.load(); index = -1;
     }
     audio.loop = mode === 0 || tracks.length <= 1;
   },
   playIndex(value) {
     if (!tracks.length) return;
     index = ((value % tracks.length) + tracks.length) % tracks.length;
     audio.pause();
     audio.src = new URL(tracks[index], document.baseURI).href;
     audio.loop = mode === 0 || tracks.length <= 1;
     audio.load();
     start();
   },
   next() { this.playIndex(index + 1); },
   replay() {
     if (index < 0) return;
     audio.currentTime = 0;
     start();
   },
   setMode(value) {
     mode = value === 0 ? 0 : 1;
     audio.loop = mode === 0 || tracks.length <= 1;
   },
   setVolume(value) {
     audio.volume = Math.max(0, Math.min(1, Number(value) || 0));
   },
   status() {
     return JSON.stringify({index, mode, playing: !audio.paused, readyState: audio.readyState, error: audio.error?.code || 0});
   }
 };
 audio.addEventListener("ended", () => {
   if (mode === 1 && tracks.length > 1) bgm.next();
 });
 audio.addEventListener("error", () => {
   if (audio.error) console.warn("[kana-bgm] media error:", audio.error.code, audio.currentSrc);
 });
 const unlock = () => {
   if (pending || (index >= 0 && audio.paused)) start();
 };
 for (const event of ["pointerdown", "touchstart", "keydown", "click"])
   window.addEventListener(event, unlock, {passive: true, capture: true});
 window.__kanaBgm = bgm;
})();
