// Read only Discord's own account panel. A channel message or member profile
// can contain an avatar and name too, but is not the signed-in user's identity.
(() => {
    const panelSelector = '[aria-label="User area"], [data-testid="account-panel"], [class*="panels_"]';
    const accountSelector = '[class*="avatarWrapper"], [class*="accountProfile_"], [class*="accountPanel_"]';
    const nameSelector = '[class*="displayName_"], [class*="title_"], [class*="username_"], [class*="name_"]';
    const pictureSelector = 'img[src*="/avatars/"], img[srcset*="/avatars/"], image[href*="/avatars/"]';
    const text = element => element?.textContent?.trim();
    for (const panel of document.querySelectorAll(panelSelector)) {
        const account = panel.querySelector(accountSelector) ?? panel;
        const tag = account.querySelector('[class*="nameTag"]') ?? panel.querySelector('[class*="nameTag"]');
        const picture = account.querySelector(pictureSelector) ?? panel.querySelector(pictureSelector);
        // In compact layouts Discord can omit the visible name while keeping
        // the avatar's accessible "name, status" label.
        const avatarLabel = picture?.closest('[role="img"][aria-label]')?.getAttribute('aria-label')
            ?? account.querySelector('[role="img"][aria-label]')?.getAttribute('aria-label');
        const accessibleName = avatarLabel?.match(/^(.+),\s*(?:online|idle|do not disturb|dnd|offline|invisible|streaming)$/i)?.[1];
        const Name = [
            text(tag?.querySelector(nameSelector)),
            text(tag?.firstElementChild),
            text(account.querySelector(nameSelector)),
            text(tag),
            accessibleName
        ].find(Boolean)?.trim().slice(0, 128);
        if (!Name) continue;
        const Avatar = [picture?.currentSrc, picture?.getAttribute('src'), picture?.getAttribute('href'),
            picture?.getAttribute('srcset')?.trim().split(/\s+/)[0]]
            .find(url => url?.includes('/avatars/')) ?? null;
        return { Name, Avatar };
    }
    return null;
})()
