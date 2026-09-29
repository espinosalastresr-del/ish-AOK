#import "ISHXNativeBridge.h"
#import "GuestFileBridge.h"
#import <AVFoundation/AVFoundation.h>
#import <Contacts/Contacts.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>
#import <EventKit/EventKit.h>
#import <Photos/Photos.h>
#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#include <dispatch/dispatch.h>
#include <stdio.h>
#include <string.h>

static void ishx_json(char *out, size_t cap, BOOL ok, NSString *payload) {
    NSDictionary *obj = ok ? @{@"ok": @YES, @"result": payload ?: @""}
                           : @{@"ok": @NO, @"error": payload ?: @"unknown"};
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil];
    if (!data || cap < 3) return;
    size_t n = MIN(cap - 2, data.length);
    memcpy(out, data.bytes, n); out[n] = '\n'; out[n + 1] = '\0';
}
static BOOL ishx_wait(dispatch_semaphore_t sem, NSTimeInterval seconds) {
    return dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW,
        (int64_t)(seconds * NSEC_PER_SEC))) == 0;
}
@interface ISHXLocationDelegate : NSObject <CLLocationManagerDelegate>
@property(nonatomic) dispatch_semaphore_t sem;
@property(nonatomic,strong) CLLocation *location;
@property(nonatomic,strong) NSError *error;
@end
@implementation ISHXLocationDelegate
- (void)locationManager:(CLLocationManager *)m didUpdateLocations:(NSArray *)locations {
    self.location = locations.lastObject; dispatch_semaphore_signal(self.sem);
}
- (void)locationManager:(CLLocationManager *)m didFailWithError:(NSError *)error {
    self.error = error; dispatch_semaphore_signal(self.sem);
}
@end
@interface ISHXPhotoDelegate : NSObject <AVCapturePhotoCaptureDelegate>
@property(nonatomic) dispatch_semaphore_t sem;
@property(nonatomic,strong) NSData *data;
@property(nonatomic,strong) NSError *error;
@end
@implementation ISHXPhotoDelegate
- (void)captureOutput:(AVCapturePhotoOutput *)o didFinishProcessingPhoto:(AVCapturePhoto *)p error:(NSError *)e {
    self.error=e; if(!e) self.data=[p fileDataRepresentation]; dispatch_semaphore_signal(self.sem);
}
@end
@interface ISHXBluetoothDelegate : NSObject <CBCentralManagerDelegate>
@property(nonatomic) dispatch_semaphore_t sem;
@property(nonatomic,strong) NSMutableArray *devices;
@property(nonatomic,strong) CBCentralManager *manager;
@end
@implementation ISHXBluetoothDelegate
- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
    if(central.state==CBManagerStatePoweredOn) [central scanForPeripheralsWithServices:nil options:nil];
    else if(central.state!=CBManagerStateUnknown && central.state!=CBManagerStateResetting)
        dispatch_semaphore_signal(self.sem);
}
- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)p
 advertisementData:(NSDictionary<NSString *,id> *)ad RSSI:(NSNumber *)rssi {
    [self.devices addObject:@{@"name":p.name ?: @"",@"id":p.identifier.UUIDString,@"rssi":rssi ?: @0}];
}
@end

static NSString *ishx_join(int argc,char *const argv[],int first) {
    NSMutableArray *a=[NSMutableArray array];
    for(int i=first;i<argc;i++) [a addObject:[NSString stringWithUTF8String:argv[i] ?: ""] ?: @""];
    return [a componentsJoinedByString:@" "];
}
static int ishx_location(char *out,size_t cap) {
    if(!CLLocationManager.locationServicesEnabled){ishx_json(out,cap,NO,@"location services disabled");return 1;}
    CLLocationManager *m=[CLLocationManager new]; ISHXLocationDelegate *d=[ISHXLocationDelegate new];
    d.sem=dispatch_semaphore_create(0); m.delegate=d; [m requestWhenInUseAuthorization]; [m startUpdatingLocation];
    BOOL got=ishx_wait(d.sem,15); [m stopUpdatingLocation];
    if(!got||!d.location){ishx_json(out,cap,NO,d.error.localizedDescription ?: @"location timeout");return 1;}
    CLLocation *l=d.location;
    NSString *r=[NSString stringWithFormat:@"{\"latitude\":%.8f,\"longitude\":%.8f,\"altitude\":%.2f,\"accuracy\":%.2f}",
                 l.coordinate.latitude,l.coordinate.longitude,l.altitude,l.horizontalAccuracy];
    ishx_json(out,cap,YES,r);return 0;
}
static int ishx_motion(char *out,size_t cap) {
    CMMotionManager *m=[CMMotionManager new]; if(!m.accelerometerAvailable){ishx_json(out,cap,NO,@"accelerometer unavailable");return 1;}
    dispatch_semaphore_t s=dispatch_semaphore_create(0); __block CMAccelerometerData *sample=nil;
    [m startAccelerometerUpdatesToQueue:[NSOperationQueue new] withHandler:^(CMAccelerometerData *d,NSError *e){if(d)sample=d;dispatch_semaphore_signal(s);}];
    BOOL got=ishx_wait(s,3);[m stopAccelerometerUpdates];
    if(!got||!sample){ishx_json(out,cap,NO,@"accelerometer timeout");return 1;}
    NSString *r=[NSString stringWithFormat:@"{\"x\":%.6f,\"y\":%.6f,\"z\":%.6f}",sample.acceleration.x,sample.acceleration.y,sample.acceleration.z];
    ishx_json(out,cap,YES,r);return 0;
}
static int ishx_clipboard(int argc,char *const argv[],char *out,size_t cap) {
    if(argc>2&&strcmp(argv[2],"set")==0){UIPasteboard.generalPasteboard.string=ishx_join(argc,argv,3);ishx_json(out,cap,YES,@"set");return 0;}
    ishx_json(out,cap,YES,UIPasteboard.generalPasteboard.string ?: @"");return 0;
}
static int ishx_battery(char *out,size_t cap) {
    UIDevice.currentDevice.batteryMonitoringEnabled=YES;
    ishx_json(out,cap,YES,[NSString stringWithFormat:@"{\"level\":%.3f,\"state\":%ld}",UIDevice.currentDevice.batteryLevel,(long)UIDevice.currentDevice.batteryState]);return 0;
}
static int ishx_notifications(char *out,size_t cap) {
    dispatch_semaphore_t s=dispatch_semaphore_create(0);__block UNAuthorizationStatus st=UNAuthorizationStatusNotDetermined;
    [UNUserNotificationCenter.currentNotificationCenter getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings *x){st=x.authorizationStatus;dispatch_semaphore_signal(s);}];
    if(!ishx_wait(s,3)){ishx_json(out,cap,NO,@"notification status timeout");return 1;}
    ishx_json(out,cap,YES,[NSString stringWithFormat:@"{\"authorization\":%ld}",(long)st]);return 0;
}
static int ishx_contacts(char *out,size_t cap) {
    CNContactStore *s=[CNContactStore new];dispatch_semaphore_t sem=dispatch_semaphore_create(0);__block BOOL ok=NO;__block NSError *err;
    [s requestAccessForEntityType:CNEntityTypeContacts completionHandler:^(BOOL g,NSError *e){ok=g;err=e;dispatch_semaphore_signal(sem);}];
    if(!ishx_wait(sem,10)||!ok){ishx_json(out,cap,NO,err.localizedDescription ?: @"contacts permission denied");return 1;}
    NSArray *keys=@[CNContactGivenNameKey,CNContactFamilyNameKey,CNContactPhoneNumbersKey,CNContactEmailAddressesKey];
    CNFetchRequest *q=[[CNFetchRequest alloc]initWithKeysToFetch:keys];NSMutableArray *a=[NSMutableArray array];NSError *e=nil;
    [s enumerateContactsWithFetchRequest:q error:&e usingBlock:^(CNContact *c,BOOL *stop){
        NSMutableDictionary *x=[@{@"given":c.givenName ?: @"",@"family":c.familyName ?: @""} mutableCopy];
        if(c.phoneNumbers.count)x[@"phone"]=c.phoneNumbers.firstObject.value.stringValue ?: @"";
        if(c.emailAddresses.count)x[@"email"]=c.emailAddresses.firstObject.value ?: @"";
        [a addObject:x];
    }];
    if(e){ishx_json(out,cap,NO,e.localizedDescription);return 1;}NSData *d=[NSJSONSerialization dataWithJSONObject:a options:0 error:nil];
    ishx_json(out,cap,YES,[[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding] ?: @"[]");return 0;
}
static int ishx_eventkit(char *out,size_t cap,BOOL reminders) {
    EKEventStore *s=[EKEventStore new];dispatch_semaphore_t sem=dispatch_semaphore_create(0);__block BOOL ok=NO;__block NSError *err;
    if (@available(iOS 17.0, *)) {
        [s requestFullAccessToEventsWithCompletion:^(BOOL g,NSError *e){ok=g;err=e;dispatch_semaphore_signal(sem);}];
    } else {
        [s requestAccessToEntityType:t completion:^(BOOL g,NSError *e){ok=g;err=e;dispatch_semaphore_signal(sem);}];
    }
    if(!ishx_wait(sem,10)||!ok){ishx_json(out,cap,NO,err.localizedDescription ?: @"calendar/reminders permission denied");return 1;}
    NSArray *cal=[s calendarsForEntityType:(reminders?EKEntityTypeReminder:EKEntityTypeEvent)];NSMutableArray *a=[NSMutableArray array];
    for(EKCalendar *c in cal)[a addObject:@{@"title":c.title ?: @"",@"type":@(c.type)}];
    NSData *d=[NSJSONSerialization dataWithJSONObject:a options:0 error:nil];ishx_json(out,cap,YES,[[NSString alloc]initWithData:d encoding:NSUTF8StringEncoding] ?: @"[]");return 0;
}
static int ishx_bluetooth(char *out,size_t cap) {
    ISHXBluetoothDelegate *d=[ISHXBluetoothDelegate new];d.sem=dispatch_semaphore_create(0);d.devices=[NSMutableArray array];
    d.manager=[[CBCentralManager alloc]initWithDelegate:d queue:dispatch_get_global_queue(QOS_CLASS_UTILITY,0)];
    if(!ishx_wait(d.sem,5)&&d.manager.state!=CBManagerStatePoweredOn){ishx_json(out,cap,NO,@"bluetooth unavailable or permission denied");return 1;}
    [NSThread sleepForTimeInterval:3];[d.manager stopScan];NSData *data=[NSJSONSerialization dataWithJSONObject:d.devices options:0 error:nil];
    ishx_json(out,cap,YES,[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding] ?: @"[]");return 0;
}
static int ishx_camera(int argc,char *const argv[],char *out,size_t cap) {
    if(argc<4){ishx_json(out,cap,NO,@"usage: iosctl camera photo guest-path");return 2;}
    if([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]==AVAuthorizationStatusNotDetermined){
        dispatch_semaphore_t s=dispatch_semaphore_create(0);[AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL g){dispatch_semaphore_signal(s);}];ishx_wait(s,10);
    }
    if([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo]!=AVAuthorizationStatusAuthorized){ishx_json(out,cap,NO,@"camera permission denied");return 1;}
    AVCaptureDevice *dev=[AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];NSError *e=nil;AVCaptureDeviceInput *in=[AVCaptureDeviceInput deviceInputWithDevice:dev error:&e];
    AVCapturePhotoOutput *photo=[AVCapturePhotoOutput new];AVCaptureSession *session=[AVCaptureSession new];
    if(!in||![session canAddInput:in]||![session canAddOutput:photo]){ishx_json(out,cap,NO,e.localizedDescription ?: @"camera setup failed");return 1;}
    [session addInput:in];[session addOutput:photo];ISHXPhotoDelegate *del=[ISHXPhotoDelegate new];del.sem=dispatch_semaphore_create(0);[session startRunning];
    [photo capturePhotoWithSettings:[AVCapturePhotoSettings photoSettings] delegate:del];BOOL got=ishx_wait(del.sem,20);[session stopRunning];
    if(!got||!del.data){ishx_json(out,cap,NO,del.error.localizedDescription ?: @"photo capture timeout");return 1;}
    dispatch_semaphore_t ws=dispatch_semaphore_create(0);__block NSError *we;
    [[ISHGuestFileBridge sharedBridge]writeData:del.data toGuestPath:[NSString stringWithUTF8String:argv[3]] completion:^(BOOL ok,NSError *x){we=x;dispatch_semaphore_signal(ws);}];
    if(!ishx_wait(ws,30)||we){ishx_json(out,cap,NO,we.localizedDescription ?: @"guest write failed");return 1;}ishx_json(out,cap,YES,@"photo saved");return 0;
}
static int ishx_microphone(int argc,char *const argv[],char *out,size_t cap) {
    if(argc<5){ishx_json(out,cap,NO,@"usage: iosctl microphone record guest-path seconds");return 2;}
    double seconds=atof(argv[4]);if(seconds<1)seconds=1;if(seconds>300)seconds=300;
    AVAudioSession *as=AVAudioSession.sharedInstance;[as setCategory:AVAudioSessionCategoryRecord error:nil];[as setActive:YES error:nil];
    if([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio]==AVAuthorizationStatusNotDetermined){
        dispatch_semaphore_t s=dispatch_semaphore_create(0);[AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL g){dispatch_semaphore_signal(s);}];ishx_wait(s,10);
    }
    if([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio]!=AVAuthorizationStatusAuthorized){ishx_json(out,cap,NO,@"microphone permission denied");return 1;}
    NSURL *tmp=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString]];
    AVAudioRecorder *r=[[AVAudioRecorder alloc]initWithURL:tmp settings:@{AVFormatIDKey:@(kAudioFormatMPEG4AAC),AVSampleRateKey:@44100,AVNumberOfChannelsKey:@1} error:nil];
    if(!r||![r record]){ishx_json(out,cap,NO,@"microphone setup failed");return 1;}[NSThread sleepForTimeInterval:seconds];[r stop];
    NSData *data=[NSData dataWithContentsOfURL:tmp];[[NSFileManager defaultManager]removeItemAtURL:tmp error:nil];if(!data){ishx_json(out,cap,NO,@"recording failed");return 1;}
    dispatch_semaphore_t ws=dispatch_semaphore_create(0);__block NSError *we;
    [[ISHGuestFileBridge sharedBridge]writeData:data toGuestPath:[NSString stringWithUTF8String:argv[3]] completion:^(BOOL ok,NSError *x){we=x;dispatch_semaphore_signal(ws);}];
    if(!ishx_wait(ws,30)||we){ishx_json(out,cap,NO,we.localizedDescription ?: @"guest write failed");return 1;}ishx_json(out,cap,YES,@"recording saved");return 0;
}
static int ishx_photos(int argc,char *const argv[],char *out,size_t cap) {
    if(argc<4){ishx_json(out,cap,NO,@"usage: iosctl photos save guest-path");return 2;}
    PHAuthorizationStatus st=[PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly];
    if(st==PHAuthorizationStatusNotDetermined){dispatch_semaphore_t s=dispatch_semaphore_create(0);[PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus x){st=x;dispatch_semaphore_signal(s);}];ishx_wait(s,10);}
    if(st!=PHAuthorizationStatusAuthorized&&st!=PHAuthorizationStatusLimited){ishx_json(out,cap,NO,@"photos permission denied");return 1;}
    dispatch_semaphore_t rs=dispatch_semaphore_create(0);__block NSURL *url;__block NSError *err;
    [[ISHGuestFileBridge sharedBridge]extractToTempFileAtGuestPath:[NSString stringWithUTF8String:argv[3]] progress:nil completion:^(NSURL *u,NSError *e){url=u;err=e;dispatch_semaphore_signal(rs);}];
    if(!ishx_wait(rs,60)||err||!url){ishx_json(out,cap,NO,err.localizedDescription ?: @"guest extraction failed");return 1;}
    dispatch_semaphore_t ps=dispatch_semaphore_create(0);__block BOOL ok=NO;
    [[PHPhotoLibrary sharedPhotoLibrary]performChanges:^{PHAssetChangeRequest *c=[PHAssetChangeRequest creationRequestForAssetFromImage:[UIImage imageWithContentsOfFile:url.path]];ok=(c!=nil);} completionHandler:^(BOOL x,NSError *e){ok=x;err=e;dispatch_semaphore_signal(ps);}];
    if(!ishx_wait(ps,30)||!ok){ishx_json(out,cap,NO,err.localizedDescription ?: @"photo save failed");return 1;}ishx_json(out,cap,YES,@"saved to Photos");return 0;
}
int ishx_native_bridge_run(int argc,char *const argv[],char *out,size_t cap) {
    if(argc<2){ishx_json(out,cap,NO,@"usage: iosctl command");return 2;}
    NSString *c=[NSString stringWithUTF8String:argv[1]] ?: @"";
    if([c isEqualToString:@"status"]){ishx_json(out,cap,YES,@"{\"nativeBridge\":true,\"jitFallback\":\"gadget\",\"stikDebug\":\"optional\"}");return 0;}
    if([c isEqualToString:@"location"]&&argc>2&&strcmp(argv[2],"get")==0)return ishx_location(out,cap);
    if([c isEqualToString:@"motion"]&&argc>2&&strcmp(argv[2],"accelerometer")==0)return ishx_motion(out,cap);
    if([c isEqualToString:@"clipboard"])return ishx_clipboard(argc,argv,out,cap);
    if([c isEqualToString:@"battery"]&&argc>2&&strcmp(argv[2],"get")==0)return ishx_battery(out,cap);
    if([c isEqualToString:@"notifications"]&&argc>2&&strcmp(argv[2],"status")==0)return ishx_notifications(out,cap);
    if([c isEqualToString:@"contacts"]&&argc>2&&strcmp(argv[2],"list")==0)return ishx_contacts(out,cap);
    if([c isEqualToString:@"calendar"]&&argc>2&&strcmp(argv[2],"list")==0)return ishx_eventkit(out,cap,NO);
    if([c isEqualToString:@"reminders"]&&argc>2&&strcmp(argv[2],"list")==0)return ishx_eventkit(out,cap,YES);
    if([c isEqualToString:@"bluetooth"]&&argc>2&&strcmp(argv[2],"scan")==0)return ishx_bluetooth(out,cap);
    if([c isEqualToString:@"camera"]&&argc>2&&strcmp(argv[2],"photo")==0)return ishx_camera(argc,argv,out,cap);
    if([c isEqualToString:@"microphone"]&&argc>2&&strcmp(argv[2],"record")==0)return ishx_microphone(argc,argv,out,cap);
    if([c isEqualToString:@"photos"]&&argc>2&&strcmp(argv[2],"save")==0)return ishx_photos(argc,argv,out,cap);
    ishx_json(out,cap,NO,@"unsupported iosctl command");return 127;
}
