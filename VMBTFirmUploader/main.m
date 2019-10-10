//
//  main.m
//  VMBTFirmUploader
//
//  Created by MengChen on 2019-09-16.
//  Copyright © 2019 Menchen. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

bool haveFirmware();
void uploadFirmware(NSString *vmPath,NSString *snapshot);
bool lock = true;
void printHelp();
NSString *vmxFilePath;
NSString *snapshotName;
NSString *vmrunExec;

@protocol DaemonProtocol
- (void)performWork;
@end

@interface NSString (ShellExecution)
- (NSString*)runAsCommand;
@end

@implementation NSString (ShellExecution)

- (NSString*)runAsCommand {
    NSPipe* pipe = [NSPipe pipe];

    NSTask* task = [[NSTask alloc] init];
    [task setLaunchPath: @"/bin/sh"];
    [task setArguments:@[@"-c", [NSString stringWithFormat:@"%@", self]]];
    [task setStandardOutput:pipe];

    NSFileHandle* file = [pipe fileHandleForReading];
    [task launch];

    return [[NSString alloc] initWithData:[file readDataToEndOfFile] encoding:NSUTF8StringEncoding];
}

@end

bool haveFirmware(){
    NSString *output = [@"system_profiler SPBluetoothDataType | grep Firmware | tr -s ' '" runAsCommand];

    // system_profiler will print an info directly to stdout when bt is paired, so we need double command

    NSString *version = [[NSString stringWithFormat:@"echo \"%@\" | awk -F\"[()]\" '{print $2}' | tr -d \'\\n\'",output] runAsCommand];
    NSLog(@"Bluetooth firmware version: %@",version);
    if ([version isEqualToString:@"0.0"]){
        return false;
    }
    return true;
}

void uploadFirmware(NSString *vmPath, NSString *snapshot){
    if (lock || haveFirmware())
        return;
    lock = true;
    NSLog(@"Uploading firmware...");
    [[NSString stringWithFormat:@"%@ -T ws revertToSnapshot \"%@\" %@",vmrunExec,vmPath,snapshot] runAsCommand];
    [[NSString stringWithFormat:@"%@ -T ws start \"%@\" nogui",vmrunExec,vmPath] runAsCommand];
    sleep(25); // make sure that vm have enough time to run.
    

    // force shutdown, make sure that no vm is running at background wasting resource
    [[NSString stringWithFormat:@"%@ -T ws stop \"%@\" hard",vmrunExec,vmPath] runAsCommand];
    lock = false;
    NSLog(@"Upload finished");

}

void printHelp(){
    NSLog(@"Usage: VMBTFirmUploader <vmx path> <snapshot name> [vmrun path]");
}

# pragma mark VMBTFirmUploader Object Conforms to Protocol

@interface VMBTFirmUploader : NSObject <DaemonProtocol>
@end;
@implementation VMBTFirmUploader
- (id)init
{
    self = [super init];
    if (self) {
        // Do here what you needs to be done to start things

        // sleep wake
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                               selector: @selector(receiveWakeNote:)
                                                                   name: NSWorkspaceDidWakeNotification object: nil];
        // screen unlock
        [[NSDistributedNotificationCenter defaultCenter] addObserver: self
                                                            selector: @selector(receiveWakeNote:)
                                                                name: @"com.apple.screenIsUnlocked" object: nil];
        // screen saver end
        [[NSDistributedNotificationCenter defaultCenter] addObserver: self
                                                            selector: @selector(receiveWakeNote:)
                                                                name: @"com.apple.screensaver.didstop" object: nil];
        // Screen wake
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                               selector: @selector(receiveWakeNote:)
                                                                   name: NSWorkspaceScreensDidWakeNotification object: nil];
        // Switch to other user
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                               selector: @selector(receiveWakeNote:)
                                                                   name: NSWorkspaceSessionDidResignActiveNotification object: nil];
        // Switch back to current user
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
                                                               selector: @selector(receiveWakeNote:)
                                                                   name: NSWorkspaceSessionDidBecomeActiveNotification object: nil];

    }
    return self;
}


- (void)dealloc
{
    // Do here what needs to be done to shut things down
//    [super dealloc];



    // sleep wake
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver: self
                                                                  name: NSWorkspaceDidWakeNotification object: nil];
    // screen unlock
    [[NSDistributedNotificationCenter defaultCenter] removeObserver: self
                                                               name: @"com.apple.screenIsUnlocked" object: nil];
    // screen saver end
    [[NSDistributedNotificationCenter defaultCenter] removeObserver: self
                                                               name: @"com.apple.screensaver.didstop" object: nil];
    // Screen wake
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver: self
                                                                  name: NSWorkspaceScreensDidWakeNotification object: nil];
    // Switch to other user
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver: self
                                                                  name: NSWorkspaceSessionDidResignActiveNotification object: nil];
    // Switch back to current user
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver: self
                                                                  name: NSWorkspaceSessionDidBecomeActiveNotification object: nil];
}

- (void)performWork
{
    // This method is called periodically to perform some routine work
    NSLog(@"Performing some periodical checking...");
    uploadFirmware(vmxFilePath, snapshotName);

}
- (void) receiveWakeNote: (NSNotification*) note
{
    NSLog(@"receiveSleepNote: %@", [note name]);
    NSLog(@"Wake detected, trying to upload firmware");
    uploadFirmware(vmxFilePath, snapshotName);
}


@end

# pragma mark Setup the daemon

// Seconds runloop runs before performing work in second.
#define kRunLoopWaitTime 4*3600.0 // 4hour

BOOL keepRunning = TRUE;

void sigHandler(int signo)
{
    NSLog(@"sigHandler: Received signal %d", signo);

    switch (signo) {
        case SIGTERM:
        case SIGKILL:
        case SIGQUIT:
        case SIGHUP:
        case SIGINT:
            // Now handle more signal to quit
            NSLog(@"Exiting...");
            keepRunning = FALSE;
            CFRunLoopStop(CFRunLoopGetCurrent()); // Kill current thread so we don't need to wait until next runloop call
            break;
        default:
            break;
    }
}






int main(int argc, const char * argv[]) {
    @autoreleasepool {
        lock = true;

        if (argc <3){
            printHelp();
            return 128; // invalid arguments
        }



        NSLog(@"VMBTFirmUploader v1.3");
        vmrunExec = @"vmrun";

        if (argc >= 4){
            vmrunExec = [NSString stringWithCString:argv[3]];
        }

        if([[NSString stringWithFormat:@"hash %@",vmrunExec] runAsCommand].length!=0){
            NSLog(@"`vmrun` not found, please install vmware-funsion and make sure that it is in $PATH");
            printHelp();
            return 1;
        }

        vmxFilePath = [NSString stringWithCString:argv[1]];
        snapshotName = [NSString stringWithCString:argv[2]];
//        keepRunning = false;

        signal(SIGHUP, sigHandler);
        signal(SIGTERM, sigHandler);
        signal(SIGKILL, sigHandler);
        signal(SIGQUIT, sigHandler);
        signal(SIGINT, sigHandler);

        VMBTFirmUploader *task = [[VMBTFirmUploader alloc] init];

        NSFileManager *filemgr;
        filemgr = [[NSFileManager alloc] init];

        if ([filemgr fileExistsAtPath:vmxFilePath]){
            NSLog(@"Found vmx file");
        }else{
            NSLog(@"%@ is missing!",vmxFilePath);
            NSLog(@"vmx file not found");
            return 128; // invalid arguments
        }
        NSString *vmsdPath = [[vmxFilePath stringByDeletingPathExtension] stringByAppendingString:@".vmsd"];
        if ([filemgr fileExistsAtPath:vmsdPath]){
            NSLog(@"Reading snapshot name from: %@",vmsdPath);
            NSString *grepoutput = [[NSString stringWithFormat:@"cat \"%@\" | grep displayName | grep \\\"%@\\\"",vmsdPath,snapshotName] runAsCommand];
            NSLog(@"vmsd output: %@",grepoutput);
            if (grepoutput.length>0){
                NSLog(@"Found snapshot: <%@>",snapshotName);
            }else{
                NSLog(@"Snapshot <%@> is not found!",snapshotName);
                return 128; // invalid arguments
            }
        }else{
            return 128; // invalid arguments
        }


        sleep(2);
        lock = false;

        do{
            [task performWork];
            CFRunLoopRunInMode(kCFRunLoopDefaultMode, kRunLoopWaitTime, false);
        }while (keepRunning);

        NSLog(@"Daemon exited");
    }
    return 0;
}

