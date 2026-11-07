// Runtime ABI bridge for macOS 26 WallpaperExtensionKit. Protocol/layout
// research: Aerial, MIT (see Aerial-LICENSE). Guard shapes before using them.
#import "WallpaperProtocols.h"
#import <objc/message.h>
#import <xpc/xpc.h>

@interface NSCoder (OceanSurfaceCoding)
- (void)encodeXPCObject:(xpc_object_t)object forKey:(NSString *)key;
@end
static IMP originalSnapshotEncode;
static ptrdiff_t snapshotOffset;

static id makeBox(NSString *name, const char *field, size_t bytes, ptrdiff_t *offset) {
    Class cls=NSClassFromString(name);
    Ivar ivar=cls ? class_getInstanceVariable(cls,field) : NULL;
    if (!cls || !ivar) return nil;
    *offset=ivar_getOffset(ivar);
    if (*offset<sizeof(void *) || class_getInstanceSize(cls)<*offset+bytes) return nil;
    return class_createInstance(cls,0);
}
id OceanCreateRemoteContext(CALayer *layer, CGFloat scale, uint32_t displayID) {
    @try {
        Class cls=NSClassFromString(@"CAContext");
        if (![cls respondsToSelector:@selector(remoteContextWithOptions:)]) return nil;
        id context=[cls remoteContextWithOptions:@{@"contentsScale":@(scale),@"displayId":@(displayID)}];
        [context setLayer:layer];
        return context;
    } @catch (NSException *exception) { NSLog(@"Ocean remote context: %@",exception.reason);return nil; }
}
uint32_t OceanRemoteContextID(id context) { return [context contextId]; }
id OceanWrapContext(uint32_t contextID) {
    ptrdiff_t offset=0;
    id box=makeBox(@"WallpaperRemoteContextXPC","box",sizeof(uint32_t),&offset);
    if (box) memcpy((uint8_t *)(__bridge void *)box+offset,&contextID,sizeof(contextID));
    return box;
}
id OceanWrapSnapshot(IOSurfaceRef surface) {
    ptrdiff_t offset=0;
    id box=makeBox(@"WallpaperSnapshotXPC","rawValue",sizeof(void *),&offset);
    if (!box) return nil;
    void *retained=(void *)CFRetain(surface);
    memcpy((uint8_t *)(__bridge void *)box+offset,&retained,sizeof(retained));
    return box;
}
BOOL OceanInstallSnapshotEncoder(void) {
    Class cls=NSClassFromString(@"WallpaperSnapshotXPC");
    Ivar ivar=cls ? class_getInstanceVariable(cls,"rawValue") : NULL;
    Method method=cls ? class_getInstanceMethod(cls,@selector(encodeWithCoder:)) : NULL;
    if (!method || !ivar || class_getInstanceSize(cls)<ivar_getOffset(ivar)+sizeof(void *)) return NO;
    snapshotOffset=ivar_getOffset(ivar);
    originalSnapshotEncode=method_getImplementation(method);
    IMP replacement=imp_implementationWithBlock(^(id object,NSCoder *coder) {
        IOSurfaceRef surface=NULL;
        memcpy(&surface,(uint8_t *)(__bridge void *)object+snapshotOffset,sizeof(surface));
        if (surface && [coder respondsToSelector:@selector(encodeXPCObject:forKey:)]) {
            xpc_object_t payload=IOSurfaceCreateXPCObject(surface);
            [coder encodeXPCObject:payload forKey:@"surface"];
        } else {
            ((void(*)(id,SEL,NSCoder *))originalSnapshotEncode)(object,@selector(encodeWithCoder:),coder);
        }
    });
    method_setImplementation(method,replacement);
    return YES;
}
