#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ThermalSensorBridge : NSObject

/// Reads a read-only hardware temperature snapshot from IOHID thermal services,
/// AppleSmartBattery IORegistry properties, and system thermal pressure state.
+ (NSDictionary<NSString *, id> *)readSnapshotDictionary;

@end

NS_ASSUME_NONNULL_END
