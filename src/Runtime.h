// SPDX-License-Identifier: Apache-2.0
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

typedef void (*WCHookMessage)(Class, SEL, IMP, IMP *);

void WCInstallMoments(WCHookMessage hook);
void WCInstallNativePicker(WCHookMessage hook);

static inline id WCMessage0(id object, const char *name) {
    return ((id(*)(id, SEL))objc_msgSend)(object, sel_registerName(name));
}

static inline id WCMessage1(id object, const char *name, id argument) {
    return ((id(*)(id, SEL, id))objc_msgSend)(object, sel_registerName(name), argument);
}

static inline BOOL WCBool0(id object, const char *name) {
    return ((BOOL(*)(id, SEL))objc_msgSend)(object, sel_registerName(name));
}

static inline NSInteger WCInteger0(id object, const char *name) {
    return ((NSInteger(*)(id, SEL))objc_msgSend)(object, sel_registerName(name));
}
