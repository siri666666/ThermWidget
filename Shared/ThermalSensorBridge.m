#import "ThermalSensorBridge.h"
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <notify.h>
#import <math.h>

typedef CFTypeRef (*IOHIDEventSystemClientCreate_fn)(CFAllocatorRef allocator);
typedef int (*IOHIDEventSystemClientSetMatching_fn)(CFTypeRef client, CFDictionaryRef match);
typedef CFArrayRef (*IOHIDEventSystemClientCopyServices_fn)(CFTypeRef client);
typedef CFTypeRef (*IOHIDServiceClientCopyProperty_fn)(CFTypeRef service, CFStringRef property);
typedef CFTypeRef (*IOHIDServiceClientCopyEvent_fn)(CFTypeRef service, int64_t type, int32_t options, int64_t unused);
typedef double (*IOHIDEventGetFloatValue_fn)(CFTypeRef event, int32_t field);

typedef CFMutableDictionaryRef (*IOServiceMatching_fn)(const char *name);
typedef mach_port_t (*IOServiceGetMatchingService_fn)(mach_port_t mainPort, CFDictionaryRef matching);
typedef int (*IORegistryEntryCreateCFProperties_fn)(mach_port_t entry, CFMutableDictionaryRef *properties, CFAllocatorRef allocator, uint32_t options);
typedef int (*IOObjectRelease_fn)(mach_port_t object);

static const int64_t kIOHIDTempEventType = 15;
static const int32_t kIOHIDTempEventField = (15 << 16);

@implementation ThermalSensorBridge

+ (nullable NSDictionary<NSString *, id> *)readBatteryDictionaryWithHandle:(void *)iokit {
    IOServiceMatching_fn fnMatching = (IOServiceMatching_fn)dlsym(iokit, "IOServiceMatching");
    IOServiceGetMatchingService_fn fnGetService = (IOServiceGetMatchingService_fn)dlsym(iokit, "IOServiceGetMatchingService");
    IORegistryEntryCreateCFProperties_fn fnCopyProps = (IORegistryEntryCreateCFProperties_fn)dlsym(iokit, "IORegistryEntryCreateCFProperties");
    IOObjectRelease_fn fnRelease = (IOObjectRelease_fn)dlsym(iokit, "IOObjectRelease");

    if (!fnMatching || !fnGetService || !fnCopyProps || !fnRelease) {
        return nil;
    }

    CFDictionaryRef match = fnMatching("AppleSmartBattery");
    if (!match) {
        return nil;
    }

    mach_port_t service = fnGetService(0, match);
    if (service == MACH_PORT_NULL) {
        return nil;
    }

    CFMutableDictionaryRef propsRef = NULL;
    int kr = fnCopyProps(service, &propsRef, kCFAllocatorDefault, 0);
    fnRelease(service);
    if (kr != 0 || !propsRef) {
        return nil;
    }

    NSDictionary *props = (__bridge_transfer NSDictionary *)propsRef;
    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    // Prefer VirtualTemperature (centi-Celsius) if available; fallback to Temperature (decikelvin / centikelvin).
    NSNumber *virtualTemp = props[@"VirtualTemperature"];
    NSNumber *rawTemp = props[@"Temperature"];
    double batteryCelsius = NAN;

    if ([virtualTemp isKindOfClass:[NSNumber class]]) {
        double v = virtualTemp.doubleValue / 100.0;
        if (v > -30.0 && v < 120.0) {
            batteryCelsius = v;
        }
    }

    if (isnan(batteryCelsius) && [rawTemp isKindOfClass:[NSNumber class]]) {
        double raw = rawTemp.doubleValue;
        double c = (raw > 10000.0) ? (raw / 100.0 - 273.15) : (raw / 10.0 - 273.15);
        if (c > -30.0 && c < 120.0) {
            batteryCelsius = c;
        }
    }

    if (!isnan(batteryCelsius)) {
        result[@"temperatureC"] = @(batteryCelsius);
    }

    if ([props[@"IsCharging"] isKindOfClass:[NSNumber class]]) {
        result[@"isCharging"] = props[@"IsCharging"];
    }
    if ([props[@"ExternalConnected"] isKindOfClass:[NSNumber class]]) {
        result[@"externalConnected"] = props[@"ExternalConnected"];
    }
    if ([props[@"CurrentCapacity"] isKindOfClass:[NSNumber class]]) {
        result[@"capacity"] = props[@"CurrentCapacity"];
    }
    if ([props[@"Voltage"] isKindOfClass:[NSNumber class]]) {
        result[@"voltageMV"] = props[@"Voltage"];
    }

    return result;
}

+ (NSArray<NSDictionary<NSString *, id> *> *)readHIDSensorsWithHandle:(void *)iokit {
    IOHIDEventSystemClientCreate_fn fnCreate = (IOHIDEventSystemClientCreate_fn)dlsym(iokit, "IOHIDEventSystemClientCreate");
    IOHIDEventSystemClientSetMatching_fn fnSetMatching = (IOHIDEventSystemClientSetMatching_fn)dlsym(iokit, "IOHIDEventSystemClientSetMatching");
    IOHIDEventSystemClientCopyServices_fn fnCopyServices = (IOHIDEventSystemClientCopyServices_fn)dlsym(iokit, "IOHIDEventSystemClientCopyServices");
    IOHIDServiceClientCopyProperty_fn fnCopyProp = (IOHIDServiceClientCopyProperty_fn)dlsym(iokit, "IOHIDServiceClientCopyProperty");
    IOHIDServiceClientCopyEvent_fn fnCopyEvent = (IOHIDServiceClientCopyEvent_fn)dlsym(iokit, "IOHIDServiceClientCopyEvent");
    IOHIDEventGetFloatValue_fn fnGetFloat = (IOHIDEventGetFloatValue_fn)dlsym(iokit, "IOHIDEventGetFloatValue");

    if (!fnCreate || !fnSetMatching || !fnCopyServices || !fnCopyProp || !fnCopyEvent || !fnGetFloat) {
        return @[];
    }

    CFTypeRef client = fnCreate(kCFAllocatorDefault);
    if (!client) {
        return @[];
    }

    NSDictionary *matching = @{
        @"PrimaryUsagePage": @(0xFF00),
        @"PrimaryUsage": @(5)
    };
    fnSetMatching(client, (__bridge CFDictionaryRef)matching);

    CFArrayRef servicesRef = fnCopyServices(client);
    if (!servicesRef) {
        CFRelease(client);
        return @[];
    }

    NSArray *services = (__bridge_transfer NSArray *)servicesRef;
    NSMutableArray<NSDictionary<NSString *, id> *> *readings = [NSMutableArray arrayWithCapacity:services.count];

    for (id serviceObj in services) {
        CFTypeRef service = (__bridge CFTypeRef)serviceObj;
        CFTypeRef nameRef = fnCopyProp(service, CFSTR("Product"));
        id nameObj = (__bridge_transfer id)nameRef;
        NSString *name = [nameObj isKindOfClass:[NSString class]] ? (NSString *)nameObj : nil;
        if (!name.length) {
            CFTypeRef locRef = fnCopyProp(service, CFSTR("LocationID"));
            id locObj = (__bridge_transfer id)locRef;
            name = [locObj isKindOfClass:[NSNumber class]]
                ? [NSString stringWithFormat:@"Sensor-0x%X", ((NSNumber *)locObj).unsignedIntValue]
                : @"Unknown Sensor";
        }

        CFTypeRef event = fnCopyEvent(service, kIOHIDTempEventType, 0, 0);
        if (!event) {
            continue;
        }
        double value = fnGetFloat(event, kIOHIDTempEventField);
        CFRelease(event);

        // Filter placeholder/fault values (0.0 or -127 / 999)
        if (isfinite(value) && value > -30.0 && value < 120.0 && fabs(value) > 0.001) {
            [readings addObject:@{
                @"name": name,
                @"celsius": @(value)
            }];
        }
    }

    CFRelease(client);
    return readings;
}

+ (NSInteger)readThermalPressureLevel {
    int token = 0;
    if (notify_register_check("com.apple.system.thermalpressurelevel", &token) != NOTIFY_STATUS_OK) {
        return -1;
    }
    uint64_t state = 0;
    uint32_t status = notify_get_state(token, &state);
    notify_cancel(token);
    return (status == NOTIFY_STATUS_OK) ? (NSInteger)state : -1;
}

+ (NSDictionary<NSString *, id> *)readSnapshotDictionary {
    NSMutableDictionary<NSString *, id> *snapshot = [NSMutableDictionary dictionary];
    void *iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY);

    if (iokit) {
        NSDictionary *battery = [self readBatteryDictionaryWithHandle:iokit];
        if (battery) {
            snapshot[@"battery"] = battery;
        }
        snapshot[@"sensors"] = [self readHIDSensorsWithHandle:iokit];
    } else {
        snapshot[@"sensors"] = @[];
    }

    snapshot[@"thermalState"] = @((NSInteger)[NSProcessInfo processInfo].thermalState);
    snapshot[@"thermalPressure"] = @([self readThermalPressureLevel]);
    snapshot[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
    return snapshot;
}

@end
