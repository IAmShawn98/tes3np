// Read the signed-in user's own account panel, never a message author.
(() => {
    const panelSelector = '[aria-label="User area"], [data-testid="account-panel"], [class*="panels_"]';
    const accountSelector = '[class*="avatarWrapper_"], [class*="accountProfile_"], [class*="accountPanel_"]';
    const nameSelector = '[class*="displayName_"], [class*="title_"], [class*="username_"]';
    for (const panel of document.querySelectorAll(panelSelector)) {
        const account = panel.querySelector(accountSelector);
        if (!account) continue;
        // The compact account layout can place the name alongside the avatar wrapper.
        const tag = account.querySelector('[class*="nameTag_"]') ?? panel.querySelector('[class*="nameTag_"]');
        const Name = [
            tag?.querySelector(nameSelector),
            tag?.firstElementChild,
            account.querySelector(nameSelector)
        ].map(element => element?.textContent?.trim()).find(Boolean)?.slice(0, 128);
        if (!Name) continue;
        const pictureSelector = 'img[src*="/avatars/"], img[srcset*="/avatars/"]';
        const picture = account.querySelector(pictureSelector) ?? panel.querySelector(pictureSelector);
        const Avatar = [picture?.currentSrc, picture?.src, picture?.srcset?.trim().split(/\s+/)[0]]
            .find(url => url?.includes('/avatars/')) ?? null;
        return { Name, Avatar };
    }
    return null;
})()
