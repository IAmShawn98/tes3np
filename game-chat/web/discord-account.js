// Read the signed-in user's own account panel, never a message author.
(() => {
    for (const panel of document.querySelectorAll('section[aria-label="User area"], [class*="panels_"]')) {
        const account = panel.querySelector('[class*="avatarWrapper_"], [class*="accountPanel_"], [class*="accountProfile_"]');
        if (!account) continue;
        const title = account.querySelector('[class*="nameTag_"] [class*="title_"], [class*="displayName_"], [class*="title_"], [class*="username_"]')
            ?? account.querySelector('[class*="nameTag_"]')?.firstElementChild;
        const Name = title?.textContent.trim().slice(0, 128);
        if (!Name) continue;
        const picture = account.querySelector('img[src*="/avatars/"]');
        return { Name, Avatar: picture?.currentSrc || picture?.src || null };
    }
    return null;
})()
