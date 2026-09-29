// SPDX-License-Identifier: Apache-2.0
#import "Runtime.h"
#import <dlfcn.h>

__attribute__((constructor)) static void WCInstall(void) {
    @autoreleasepool {
        WCHookMessage hook = (WCHookMessage)dlsym(RTLD_DEFAULT, "MSHookMessageEx");
        if (!hook) return;
        WCInstallMoments(hook);
        WCInstallNativePicker(hook);
    }
}
