#import "MMELocationManager.h"
#import "MMEUIApplicationWrapper.h"

static const NSTimeInterval MMELocationManagerHibernationTimeout = 300.0;
static const NSTimeInterval MMELocationManagerHibernationPollInterval = 5.0;

const CLLocationDistance MMELocationManagerHibernationRadius = 300.0;
const CLLocationDistance MMELocationManagerDistanceFilter = 5.0;

NSString * const MMELocationManagerRegionIdentifier = @"MMELocationManagerRegionIdentifier.fence.center";

@interface MMELocationManager ()

@property (nonatomic) id<MMEUIApplicationWrapper> application;
@property (nonatomic) id<MMECLLocationManagerWrapper> locationManager;
@property (nonatomic) BOOL hostAppHasBackgroundCapability;
@property (nonatomic, getter=isUpdatingLocation, readwrite) BOOL updatingLocation;
@property (nonatomic) NSDate *backgroundLocationServiceTimeoutAllowedDate;
@property (nonatomic) NSTimer *backgroundLocationServiceTimeoutTimer;

@end

@implementation MMELocationManager

- (instancetype)init {
    self = [super init];
    if (self) {
        NSArray *backgroundModes = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"UIBackgroundModes"];
        _hostAppHasBackgroundCapability = [backgroundModes containsObject:@"location"];
        _locationManager = [[MMECLLocationManagerWrapper alloc] init];
        _application = [[MMEUIApplicationWrapper alloc] init];
    }
    return self;
}

- (void)startUpdatingLocation {
    if ([self isUpdatingLocation]) {
        return;
    }

    [self configurePassiveLocationManager];
    [self startLocationServices];
}

- (void)stopUpdatingLocation {
    if ([self isUpdatingLocation]) {
        [self.locationManager stopUpdatingLocation];
        [self.locationManager stopMonitoringSignificantLocationChanges];
        self.updatingLocation = NO;
        if ([self.delegate respondsToSelector:@selector(locationManagerDidStopLocationUpdates:)]) {
            [self.delegate locationManagerDidStopLocationUpdates:self];
        }
        [self stopMonitoringRegions];
    }
}

- (void)stopMonitoringRegions {
    for(CLRegion *region in self.locationManager.monitoredRegions) {
        if([region.identifier isEqualToString:MMELocationManagerRegionIdentifier]) {
            [self.locationManager stopMonitoringForRegion:region];
        }
    }
}

#pragma mark - Utilities

- (void)configurePassiveLocationManager {
    self.locationManager.delegate = self;
    self.locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers;
    self.locationManager.distanceFilter = MMELocationManagerDistanceFilter;
}

- (void)startLocationServices {
    CLAuthorizationStatus authorizationStatus = [self.locationManager authorizationStatus];

    BOOL authorizedAlways = authorizationStatus == kCLAuthorizationStatusAuthorizedAlways;

    if (authorizedAlways || authorizationStatus == kCLAuthorizationStatusAuthorizedWhenInUse) {

        // If the host app can run in the background with `always` location permissions then allow background
        // updates and start the significant location change service and background timeout timer
        if (self.hostAppHasBackgroundCapability && authorizedAlways) {
            [self.locationManager startMonitoringSignificantLocationChanges];
            [self startBackgroundTimeoutTimer];
            self.locationManager.allowsBackgroundLocationUpdates = YES;
        }

        [self.locationManager startUpdatingLocation];
        self.updatingLocation = YES;

        if ([self.delegate respondsToSelector:@selector(locationManagerDidStartLocationUpdates:)]) {
            [self.delegate locationManagerDidStartLocationUpdates:self];
        }
    }
}

- (void)timeoutAllowedCheck {
    if (!self.isUpdatingLocation) {
        return;
    }

    if (self.application.applicationState == UIApplicationStateActive ||
        self.application.applicationState == UIApplicationStateInactive ) {
        [self startBackgroundTimeoutTimer];
        return;
    }

    NSTimeInterval timeIntervalSinceTimeoutAllowed = [[NSDate date] timeIntervalSinceDate:self.backgroundLocationServiceTimeoutAllowedDate];
    if (timeIntervalSinceTimeoutAllowed > 0) {
        [self.locationManager stopUpdatingLocation];
        self.backgroundLocationServiceTimeoutAllowedDate = nil;
        if ([self.delegate respondsToSelector:@selector(locationManagerBackgroundLocationUpdatesDidTimeout:)]) {
            [self.delegate locationManagerBackgroundLocationUpdatesDidTimeout:self];
        }
    }
}

- (void)startBackgroundTimeoutTimer {
    [self.backgroundLocationServiceTimeoutTimer invalidate];
    self.backgroundLocationServiceTimeoutAllowedDate = [[NSDate date] dateByAddingTimeInterval:MMELocationManagerHibernationTimeout];
    self.backgroundLocationServiceTimeoutTimer = [NSTimer scheduledTimerWithTimeInterval:MMELocationManagerHibernationPollInterval target:self selector:@selector(timeoutAllowedCheck) userInfo:nil repeats:YES];
}

- (void)establishRegionMonitoringForLocation:(CLLocation *)location {
    CLCircularRegion *region = [[CLCircularRegion alloc] initWithCenter:location.coordinate radius:MMELocationManagerHibernationRadius identifier:MMELocationManagerRegionIdentifier];
    region.notifyOnEntry = NO;
    region.notifyOnExit = YES;
    [self.locationManager startMonitoringForRegion:region];
}

#pragma mark - MMECLLocationManagerDelegate

- (void)locationManagerWrapper:(id<MMECLLocationManagerWrapper>)locationManagerWrapper didChangeAuthorizationStatus:(CLAuthorizationStatus)status; {
    if (status == kCLAuthorizationStatusAuthorizedAlways ||
        status == kCLAuthorizationStatusAuthorizedWhenInUse) {
        [self startUpdatingLocation];
    } else {
        [self stopUpdatingLocation];
    }
}

- (void)locationManagerWrapper:(id<MMECLLocationManagerWrapper>)locationManagerWrapper didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *location = locations.lastObject;
    if (location.speed > 0.0) {
        [self startBackgroundTimeoutTimer];
    }
    if ([self.locationManager.monitoredRegions anyObject] == nil || location.horizontalAccuracy < MMELocationManagerHibernationRadius) {
        [self establishRegionMonitoringForLocation:location];
    }
    if ([self.delegate respondsToSelector:@selector(locationManager:didUpdateLocations:)]) {
        [self.delegate locationManager:self didUpdateLocations:locations];
    }
}

- (void)locationManagerWrapper:(id<MMECLLocationManagerWrapper>)locationManagerWrapper didExitRegion:(CLRegion *)region {
    [self startBackgroundTimeoutTimer];
    [self.locationManager startUpdatingLocation];
}

- (void)locationManagerWrapperDidPauseLocationUpdates:(id<MMECLLocationManagerWrapper>)locationManagerWrapper {
    if ([self.delegate respondsToSelector:@selector(locationManagerBackgroundLocationUpdatesDidAutomaticallyPause:)]) {
        [self.delegate locationManagerBackgroundLocationUpdatesDidAutomaticallyPause:self];
    }
}

@end
