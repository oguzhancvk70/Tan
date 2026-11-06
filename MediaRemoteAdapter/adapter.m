// MediaRemote köprüsü: /usr/bin/perl içinde yüklenir, şu an çalanı JSON satırları olarak basar
#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

typedef void (*GetInfoFn)(dispatch_queue_t, void (^)(NSDictionary *));
typedef void (*RegisterFn)(dispatch_queue_t);
typedef void (*GetPlayingFn)(dispatch_queue_t, void (^)(BOOL));
typedef void (*GetPIDFn)(dispatch_queue_t, void (^)(int));
typedef Boolean (*SendFn)(int, NSDictionary *);

static void *mr(void) {
    static void *h;
    if (!h) h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    return h;
}

static void emit(void) {
    GetInfoFn getInfo = (GetInfoFn)dlsym(mr(), "MRMediaRemoteGetNowPlayingInfo");
    GetPIDFn getPID = (GetPIDFn)dlsym(mr(), "MRMediaRemoteGetNowPlayingApplicationPID");
    GetPlayingFn getPlaying = (GetPlayingFn)dlsym(mr(), "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    if (!getInfo || !getPID || !getPlaying) return;
    dispatch_queue_t q = dispatch_get_main_queue();
    getInfo(q, ^(NSDictionary *info) {
        getPID(q, ^(int pid) {
            getPlaying(q, ^(BOOL playing) {
                NSMutableDictionary *o = [NSMutableDictionary dictionary];
                o[@"pid"] = @(pid);
                o[@"playing"] = @(playing);
                NSDictionary *keys = @{
                    @"title": @"kMRMediaRemoteNowPlayingInfoTitle",
                    @"artist": @"kMRMediaRemoteNowPlayingInfoArtist",
                    @"album": @"kMRMediaRemoteNowPlayingInfoAlbum",
                    @"duration": @"kMRMediaRemoteNowPlayingInfoDuration",
                    @"elapsed": @"kMRMediaRemoteNowPlayingInfoElapsedTime",
                    @"rate": @"kMRMediaRemoteNowPlayingInfoPlaybackRate",
                };
                for (NSString *k in keys) {
                    id v = info[keys[k]];
                    if ([v isKindOfClass:NSString.class] || [v isKindOfClass:NSNumber.class]) o[k] = v;
                }
                NSDate *ts = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
                if ([ts isKindOfClass:NSDate.class]) o[@"timestamp"] = @([ts timeIntervalSince1970]);
                NSData *art = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
                if ([art isKindOfClass:NSData.class]) o[@"artwork"] = [art base64EncodedStringWithOptions:0];
                NSData *json = [NSJSONSerialization dataWithJSONObject:o options:0 error:nil];
                if (!json) return;
                fwrite(json.bytes, 1, json.length, stdout);
                fputc('\n', stdout);
                fflush(stdout);
            });
        });
    });
}

void tan_stream(void) {
    RegisterFn reg = (RegisterFn)dlsym(mr(), "MRMediaRemoteRegisterForNowPlayingNotifications");
    if (!reg) exit(2);
    reg(dispatch_get_main_queue());
    for (NSString *n in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                          @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                          @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification"]) {
        [NSNotificationCenter.defaultCenter addObserverForName:n object:nil queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(NSNotification *note) { emit(); }];
    }
    // stdin: her satır bir komut; EOF = ana uygulama kapandı
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        char line[64];
        while (fgets(line, sizeof line, stdin)) {
            int cmd = atoi(line);
            dispatch_async(dispatch_get_main_queue(), ^{
                SendFn send = (SendFn)dlsym(mr(), "MRMediaRemoteSendCommand");
                if (send) send(cmd, nil);
            });
        }
        exit(0);
    });
    emit();
    CFRunLoopRun();
}

void tan_send(void) {
    const char *c = getenv("TAN_CMD");
    SendFn send = (SendFn)dlsym(mr(), "MRMediaRemoteSendCommand");
    if (c && send) send(atoi(c), nil);
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.5, false);
}
