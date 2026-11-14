function show(platform, enabled, useSettingsInsteadOfPreferences) {
    document.body.classList.add(`platform-${platform}`);

    if (useSettingsInsteadOfPreferences) {
        document.getElementsByClassName('platform-mac state-on')[0].innerText = "OpenTranslate’s extension is currently on. You can turn it off in the Extensions section of your browser’s settings.";
        document.getElementsByClassName('platform-mac state-off')[0].innerText = "OpenTranslate’s extension is currently off. You can turn it on in the Extensions section of your browser’s settings.";
        document.getElementsByClassName('platform-mac state-unknown')[0].innerText = "You can turn on OpenTranslate’s extension in the Extensions section of your browser’s settings.";
        document.getElementsByClassName('platform-mac open-preferences')[0].innerText = "Quit and Open Extension Settings…";
    }

    if (typeof enabled === "boolean") {
        document.body.classList.toggle(`state-on`, enabled);
        document.body.classList.toggle(`state-off`, !enabled);
    } else {
        document.body.classList.remove(`state-on`);
        document.body.classList.remove(`state-off`);
    }
}

function openPreferences() {
    webkit.messageHandlers.controller.postMessage("open-preferences");
}

document.querySelector("button.open-preferences").addEventListener("click", openPreferences);

function formatTime(ms) {
    if (!ms) return "—";
    try {
        return new Date(ms).toLocaleString();
    } catch (e) {
        return String(ms);
    }
}

window.__onSharedSettings = function (payload) {
    const statusEl = document.getElementById("shared-status");
    const input = document.getElementById("target-language");
    if (!statusEl) return;

    if (payload.type === "status") {
        if (!payload.appGroupAvailable) {
            statusEl.textContent = "App Group unavailable. Enable group.net.timhuang.opentranslate in Apple Developer (pending approval) and rebuild with entitlements.";
            return;
        }
        const parts = [
            payload.hasConfig ? "Shared config present" : "No shared config yet",
            "source=" + (payload.source || "—"),
            "schema=" + (payload.schemaVersion != null ? payload.schemaVersion : "—"),
            "updated=" + formatTime(payload.lastModifiedAt),
            "migrated=" + String(!!payload.migrated),
        ];
        if (payload.targetCode) {
            parts.push("target=" + payload.targetCode);
            if (input && !input.matches(":focus")) {
                input.value = payload.targetCode;
            }
        }
        statusEl.textContent = parts.join(" · ");
    }

    if (payload.type === "setTargetLanguageResult") {
        statusEl.textContent = payload.ok
            ? ("Saved target language " + payload.targetCode + " at " + formatTime(payload.lastModifiedAt))
            : ("Save failed: " + (payload.error || "unknown"));
    }
};

document.getElementById("refresh-shared").addEventListener("click", function () {
    webkit.messageHandlers.sharedSettings.postMessage({ type: "status" });
    webkit.messageHandlers.sharedSettings.postMessage({ type: "get" });
});

document.getElementById("save-target").addEventListener("click", function () {
    const code = (document.getElementById("target-language").value || "").trim();
    if (!code) {
        document.getElementById("shared-status").textContent = "Enter a language code first.";
        return;
    }
    webkit.messageHandlers.sharedSettings.postMessage({ type: "setTargetLanguage", targetCode: code });
});

// Initial request once the native side is ready (also re-requested from didFinish).
webkit.messageHandlers.sharedSettings.postMessage({ type: "status" });
