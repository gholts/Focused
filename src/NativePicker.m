// SPDX-License-Identifier: Apache-2.0
#import "Runtime.h"
#import <Photos/Photos.h>
#import <PhotosUI/PhotosUI.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <ImageIO/ImageIO.h>

static void (*originalShow)(id, SEL, id, UIViewController *, id);
static char sessionKey;

static NSString *WCCacheDirectory(void) {
    return [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"WeChatFocusedPicker"];
}

static void WCCleanStaleMedia(void) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *directory = WCCacheDirectory();
    NSDate *cutoff = [NSDate dateWithTimeIntervalSinceNow:-24 * 60 * 60];
    for (NSString *name in [files contentsOfDirectoryAtPath:directory error:nil]) {
        NSString *path = [directory stringByAppendingPathComponent:name];
        NSDate *modified = [files attributesOfItemAtPath:path error:nil][NSFileModificationDate];
        if (modified && [modified compare:cutoff] == NSOrderedAscending)
            [files removeItemAtPath:path error:nil];
    }
}

@interface WCNativePickerSession : NSObject <PHPickerViewControllerDelegate>
@property (nonatomic, strong) id officialPicker;
@property (nonatomic, strong) id imageDelegate;
@property (nonatomic, strong) id manager;
@end

@implementation WCNativePickerSession
- (void)deliverChat:(NSDictionary *)media finish:(BOOL)finish picker:(PHPickerViewController *)picker {
    if ([media[@"video"] boolValue]) {
        SEL video = sel_registerName("handleVideo:ImagePicker:");
        if ([self.imageDelegate respondsToSelector:video]) {
            ((void (*)(id, SEL, id, id))objc_msgSend)(self.imageDelegate, video, media[@"url"], picker);
        }
        return;
    }
    SEL image = sel_registerName("didSelectImage:Data:Finish:ImageInfo:fromImagePicker:");
    if ([self.imageDelegate respondsToSelector:image])
        ((void (*)(id, SEL, id, id, BOOL, id, id))objc_msgSend)(self.imageDelegate, image, media[@"image"], media[@"data"], finish, nil, nil);
}

- (void)deliverGeneric:(NSArray *)media {
    NSMutableArray *images = [NSMutableArray array];
    NSMutableArray *videos = [NSMutableArray array];
    for (id entry in media) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        if ([entry[@"video"] boolValue]) {
            [videos addObject:@{UIImagePickerControllerMediaURL: entry[@"url"], UIImagePickerControllerMediaType: UTTypeMovie.identifier}];
        } else {
            // WeChat expects an array of UIKit-style picker dictionaries.
            NSMutableDictionary *info = [@{
                UIImagePickerControllerOriginalImage: entry[@"image"],
                UIImagePickerControllerMediaType: UTTypeImage.identifier,
                UIImagePickerControllerMediaMetadata: @{}
            } mutableCopy];
            if (entry[@"url"]) info[UIImagePickerControllerImageURL] = entry[@"url"];
            [images addObject:info];
        }
    }
    SEL image = sel_registerName("MMImagePickerManager:didFinishPickingImageWithInfo:");
    SEL video = sel_registerName("MMImagePickerManager:didFinishPickingVideoWithInfo:");
    if (images.count && [self.imageDelegate respondsToSelector:image])
        ((void (*)(id, SEL, id, id))objc_msgSend)(self.imageDelegate, image, self.manager, images);
    if (videos.count && [self.imageDelegate respondsToSelector:video])
        ((void (*)(id, SEL, id, id))objc_msgSend)(self.imageDelegate, video, self.manager, videos);
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    if (!results.count) {
        if ([self.officialPicker respondsToSelector:sel_registerName("cancelImagePicker")]) WCMessage0(self.officialPicker, "cancelImagePicker");
        [picker dismissViewControllerAnimated:YES completion:nil];
        picker.delegate = nil;
        objc_setAssociatedObject(picker, &sessionKey, nil, OBJC_ASSOCIATION_ASSIGN);
        return;
    }

    BOOL chat = [self.imageDelegate isKindOfClass:objc_getClass("ImageController")];
    NSString *cache = WCCacheDirectory();
    [NSFileManager.defaultManager createDirectoryAtPath:cache withIntermediateDirectories:YES attributes:nil error:nil];
    NSMutableArray *slots = [NSMutableArray arrayWithCapacity:results.count];
    for (NSUInteger i = 0; i < results.count; i++) [slots addObject:NSNull.null];
    __block NSUInteger next = 0;
    __block NSUInteger completed = 0;
    void (^accept)(NSUInteger, id) = ^(NSUInteger index, id media) {
        dispatch_async(dispatch_get_main_queue(), ^{
            slots[index] = media ?: @NO;
            completed++;
            if (chat) {
                while (next < slots.count && slots[next] != NSNull.null) {
                    id ready = slots[next];
                    if ([ready isKindOfClass:NSDictionary.class]) [self deliverChat:ready finish:next == slots.count - 1 picker:picker];
                    slots[next] = @NO;
                    next++;
                }
            }
            if (completed == slots.count) {
                if (!chat) [self deliverGeneric:slots];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    if (picker.presentingViewController) [picker dismissViewControllerAnimated:YES completion:nil];
                    picker.delegate = nil;
                    objc_setAssociatedObject(picker, &sessionKey, nil, OBJC_ASSOCIATION_ASSIGN);
                });
            }
        });
    };

    [results enumerateObjectsUsingBlock:^(PHPickerResult *result, NSUInteger index, BOOL *stop) {
        (void)stop;
        NSItemProvider *provider = result.itemProvider;
        BOOL video = [provider hasItemConformingToTypeIdentifier:UTTypeMovie.identifier];
        NSString *type = nil;
        for (NSString *identifier in provider.registeredTypeIdentifiers) {
            UTType *registered = [UTType typeWithIdentifier:identifier];
            if ([registered conformsToType:video ? UTTypeMovie : UTTypeImage]) {
                type = identifier;
                break;
            }
        }
        if (!type) {
            accept(index, nil);
            return;
        }
        [provider loadFileRepresentationForTypeIdentifier:type
                                        completionHandler:^(NSURL *url, NSError *error) {
                                            if (!url || error) {
                                                accept(index, nil);
                                                return;
                                            }
                                            @autoreleasepool {
                                                if (video) {
                                                    NSString *name = [NSUUID.UUID.UUIDString stringByAppendingPathExtension:url.pathExtension.length ? url.pathExtension : @"mov"];
                                                    NSURL *copy = [[NSURL fileURLWithPath:cache] URLByAppendingPathComponent:name];
                                                    BOOL copied = [NSFileManager.defaultManager copyItemAtURL:url toURL:copy error:nil];
                                                    accept(index, copied ? @{@"video": @YES,
                                                                             @"url": copy}
                                                                         : nil);
                                                    return;
                                                }
                                                NSData *source = [NSData dataWithContentsOfURL:url];
                                                UTType *representation = [UTType typeWithIdentifier:type];
                                                CGImageSourceRef imageSource = source ? CGImageSourceCreateWithData((__bridge CFDataRef)source, NULL) : NULL;
                                                NSDictionary *properties = imageSource ? (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL) : nil;
                                                NSUInteger width = [properties[(__bridge NSString *)kCGImagePropertyPixelWidth] unsignedIntegerValue];
                                                NSUInteger height = [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] unsignedIntegerValue];
                                                BOOL keepOriginal = [representation conformsToType:UTTypeJPEG] && source.length <= 4 * 1024 * 1024 && MAX(width, height) <= 2560;
                                                UIImage *image = keepOriginal ? [UIImage imageWithData:source] : nil;
                                                if (!keepOriginal && imageSource) {
                                                    NSDictionary *options = @{(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
                                                                              (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
                                                                              (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @2560};
                                                    CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, (__bridge CFDictionaryRef)options);
                                                    if (thumbnail) {
                                                        image = [UIImage imageWithCGImage:thumbnail];
                                                        CGImageRelease(thumbnail);
                                                    }
                                                }
                                                if (imageSource) CFRelease(imageSource);
                                                NSData *data = keepOriginal ? source : (image ? UIImageJPEGRepresentation(image, 0.82) : nil);
                                                if (!image || !data.length) {
                                                    accept(index, nil);
                                                    return;
                                                }
                                                NSMutableDictionary *media = [@{@"video": @NO,
                                                                                @"image": image,
                                                                                @"data": data} mutableCopy];
                                                if (!chat) {
                                                    NSURL *copy = [[NSURL fileURLWithPath:cache] URLByAppendingPathComponent:[NSUUID.UUID.UUIDString stringByAppendingPathExtension:@"jpg"]];
                                                    if ([data writeToURL:copy atomically:YES]) media[@"url"] = copy;
                                                }
                                                accept(index, media);
                                            }
                                        }];
    }];
}
@end

static void WCShow(id manager, SEL command, id option, UIViewController *controller, id delegate) {
    BOOL camera = [option respondsToSelector:sel_registerName("isCamera")] && WCBool0(option, "isCamera");
    BOOL sightCamera = [option respondsToSelector:sel_registerName("isSightCamera")] && WCBool0(option, "isSightCamera");
    BOOL chat = [delegate isKindOfClass:objc_getClass("ImageController")];
    SEL genericImage = sel_registerName("MMImagePickerManager:didFinishPickingImageWithInfo:");
    SEL genericVideo = sel_registerName("MMImagePickerManager:didFinishPickingVideoWithInfo:");
    if ((chat && (camera || sightCamera)) || ![PHPickerViewController class] || controller.presentedViewController ||
        (!chat && ![delegate respondsToSelector:genericImage] && ![delegate respondsToSelector:genericVideo])) {
        originalShow(manager, command, option, controller, delegate);
        return;
    }
    SEL getPicker = sel_registerName("getImagePickerControllerWithOptionObj:delegate:");
    id official = [manager respondsToSelector:getPicker] ? ((id(*)(id, SEL, id, id))objc_msgSend)(manager, getPicker, option, delegate) : nil;

    PHPickerConfiguration *config = [[PHPickerConfiguration alloc] initWithPhotoLibrary:PHPhotoLibrary.sharedPhotoLibrary];
    NSInteger limit = 0;
    if ([official respondsToSelector:sel_registerName("maxImageCount")]) limit = WCInteger0(official, "maxImageCount");
    else if ([option respondsToSelector:sel_registerName("maxImageCount")]) limit = WCInteger0(option, "maxImageCount");
    BOOL timeline = [delegate isKindOfClass:objc_getClass("WCTimeLineViewController")];
    if (!chat && !timeline) limit = 1;
    config.selectionLimit = limit > 0 ? limit : ((chat || timeline) ? 9 : 1);
    BOOL allowVideo = [delegate respondsToSelector:genericVideo];
    if (chat) {
        if ([official respondsToSelector:sel_registerName("canSendVideoMessage")]) allowVideo = WCBool0(official, "canSendVideoMessage");
        else allowVideo = [option respondsToSelector:sel_registerName("canSendVideoMessage")] && WCBool0(option, "canSendVideoMessage");
    }
    config.filter = allowVideo ? [PHPickerFilter anyFilterMatchingSubfilters:@[PHPickerFilter.imagesFilter, PHPickerFilter.videosFilter]] : PHPickerFilter.imagesFilter;
    config.preferredAssetRepresentationMode = PHPickerConfigurationAssetRepresentationModeCurrent;
    if (@available(iOS 15, *)) config.selection = PHPickerConfigurationSelectionOrdered;
    PHPickerViewController *native = [[PHPickerViewController alloc] initWithConfiguration:config];
    WCNativePickerSession *session = [WCNativePickerSession new];
    session.officialPicker = official;
    session.imageDelegate = delegate;
    session.manager = manager;
    native.delegate = session;
    objc_setAssociatedObject(native, &sessionKey, session, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [controller presentViewController:native animated:YES completion:nil];
}

void WCInstallNativePicker(WCHookMessage hook) {
    Class picker = objc_getClass("MMImagePickerManager");
    if (picker) hook(picker, sel_registerName("showWithOptionObj:inViewController:delegate:"), (IMP)WCShow, (IMP *)&originalShow);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        WCCleanStaleMedia();
    });
}
