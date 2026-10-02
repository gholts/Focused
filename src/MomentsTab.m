// SPDX-License-Identifier: Apache-2.0
#import "Runtime.h"

static void (*originalItems)(id, SEL);
static void (*originalItemsNew)(id, SEL);
static void (*originalCreateFind)(id, SEL);
static void (*originalCreateFindNew)(id, SEL);
static void (*originalDidSelect)(id, SEL, id, UIViewController *);
static void (*originalDidSelectNew)(id, SEL, id, UIViewController *);
static void (*originalTimelineAppear)(id, SEL, BOOL);
static __weak UIViewController *embeddedMoments;

static void WCUpdateMomentItem(id tab) {
    Ivar itemIvar = class_getInstanceVariable([tab class], "m_findFrientTabItem");
    id item = itemIvar ? object_getIvar(tab, itemIvar) : nil;
    if (!item) return;

    Class contextClass = objc_getClass("MMContext");
    id context = [contextClass respondsToSelector:sel_registerName("currentContext")] ? WCMessage0(contextClass, "currentContext") : nil;
    id language = WCMessage1(context, "getService:", objc_getClass("MMLanguageMgr"));
    NSString *title = [language respondsToSelector:sel_registerName("getStringForCurLanguage:")]
                          ? WCMessage1(language, "getStringForCurLanguage:", @"FF_Entry_Album")
                          : nil;
    if (!title.length || [title isEqualToString:@"FF_Entry_Album"])
        title = [NSBundle.mainBundle.preferredLocalizations.firstObject hasPrefix:@"zh"] ? @"朋友圈" : @"Moments";
    if ([item respondsToSelector:sel_registerName("setNormalTitle:")]) WCMessage1(item, "setNormalTitle:", title);
    id theme = WCMessage1(context, "getService:", objc_getClass("MMThemeManager"));
    SEL svg = sel_registerName("svgImageNamed:size:color:");
    if (![theme respondsToSelector:svg]) return;

    Class colors = objc_getClass("WCColor");
    UIColor *normalColor = [colors respondsToSelector:sel_registerName("labelColor")] ? WCMessage0(colors, "labelColor") : UIColor.labelColor;
    UIColor *selectedColor = [colors respondsToSelector:sel_registerName("Brand_100")] ? WCMessage0(colors, "Brand_100") : UIColor.systemGreenColor;
    CGSize size = CGSizeMake(28, 28);
    UIImage *normal = ((id(*)(id, SEL, id, CGSize, id))objc_msgSend)(theme, svg, @"icons_outlined_colorful_moment", size, normalColor);
    UIImage *selected = ((id(*)(id, SEL, id, CGSize, id))objc_msgSend)(theme, svg, @"icons_filled_moment", size, selectedColor);
    if (normal && [item respondsToSelector:sel_registerName("setNormalImage:")]) WCMessage1(item, "setNormalImage:", normal);
    if (selected && [item respondsToSelector:sel_registerName("setHighlightImage:")]) WCMessage1(item, "setHighlightImage:", selected);
}

static void WCReplaceDiscover(UIViewController *selected) {
    if (![selected isKindOfClass:UINavigationController.class]) return;
    UINavigationController *navigation = (UINavigationController *)selected;
    id entry = navigation.viewControllers.firstObject;
    if (![entry isKindOfClass:objc_getClass("FindFriendEntryViewController")] ||
        ![entry respondsToSelector:sel_registerName("preOpenAlbumView")]) return;

    id prepared = WCMessage0(entry, "preOpenAlbumView");
    if (![prepared isKindOfClass:UIViewController.class]) return;
    UIViewController *moments = prepared;
    embeddedMoments = moments;
    moments.hidesBottomBarWhenPushed = NO;
    [navigation setViewControllers:@[moments] animated:NO];
    moments.navigationItem.leftBarButtonItems = nil;
    moments.navigationItem.leftBarButtonItem = nil;
    [moments.navigationItem setHidesBackButton:YES animated:NO];
}

static void WCCreatedItems(id tab, void (*original)(id, SEL), SEL command) {
    original(tab, command);
    WCUpdateMomentItem(tab);
}

static void WCItems(id self, SEL command) { WCCreatedItems(self, originalItems, command); }
static void WCItemsNew(id self, SEL command) { WCCreatedItems(self, originalItemsNew, command); }

static void WCCreatedFind(id tab, void (*original)(id, SEL), SEL command) {
    original(tab, command);
    Ivar entryIvar = class_getInstanceVariable([tab class], "m_findFriendEntryViewController");
    id entry = entryIvar ? object_getIvar(tab, entryIvar) : nil;
    WCReplaceDiscover([entry navigationController]);
}

static void WCCreateFind(id self, SEL command) { WCCreatedFind(self, originalCreateFind, command); }
static void WCCreateFindNew(id self, SEL command) { WCCreatedFind(self, originalCreateFindNew, command); }

static void WCDidSelect(id self, SEL command, id controller, UIViewController *selected) {
    originalDidSelect(self, command, controller, selected);
    WCReplaceDiscover(selected);
}

static void WCDidSelectNew(id self, SEL command, id controller, UIViewController *selected) {
    originalDidSelectNew(self, command, controller, selected);
    WCReplaceDiscover(selected);
}

static void WCTimelineAppear(id self, SEL command, BOOL animated) {
    originalTimelineAppear(self, command, animated);
    if (self != embeddedMoments) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self navigationItem].leftBarButtonItems = nil;
        [self navigationItem].leftBarButtonItem = nil;
        [[self navigationItem] setHidesBackButton:YES animated:NO];
    });
}

void WCInstallMoments(WCHookMessage hook) {
    Class mainTab = objc_getClass("MainTabBarViewController");
    Class newTab = objc_getClass("NewMainTabBarViewController");
    Class timeline = objc_getClass("WCTimeLineViewController");
    if (mainTab) {
        hook(mainTab, sel_registerName("p_createTabBarItems"), (IMP)WCItems, (IMP *)&originalItems);
        hook(mainTab, sel_registerName("p_createFindFriendViewController"), (IMP)WCCreateFind, (IMP *)&originalCreateFind);
        hook(mainTab, sel_registerName("tabBarController:didSelectViewController:"), (IMP)WCDidSelect, (IMP *)&originalDidSelect);
    }
    if (newTab) {
        hook(newTab, sel_registerName("p_createTabBarItems"), (IMP)WCItemsNew, (IMP *)&originalItemsNew);
        hook(newTab, sel_registerName("p_createFindFriendViewController"), (IMP)WCCreateFindNew, (IMP *)&originalCreateFindNew);
        hook(newTab, sel_registerName("tabBarController:didSelectViewController:"), (IMP)WCDidSelectNew, (IMP *)&originalDidSelectNew);
    }
    if (timeline) hook(timeline, @selector(viewDidAppear:), (IMP)WCTimelineAppear, (IMP *)&originalTimelineAppear);
}
