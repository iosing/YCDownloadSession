//
//  YCDownloader.m
//  YCDownloadSession
//
//  Created by wz on 2018/8/27.
//  Copyright © 2018 onezen.cc. All rights reserved.
//  Contact me: http://www.onezen.cc/about/
//  Github:     https://github.com/onezens/YCDownloadSession
//

#import "YCDownloader.h"
#import "YCDownloadUtils.h"
#import "YCDownloadTask.h"

typedef void(^BGRecreateSessionBlock)(void);
static NSString * const kIsAllowCellar = @"kIsAllowCellar";

@interface YCDownloadTask(Downloader)
@property (nonatomic, assign) NSInteger pid;
@property (nonatomic, assign) NSInteger stid;
@property (nonatomic, copy) NSString *tmpName;
/**重新创建下载session，恢复下载状态的session的标识*/
@property (nonatomic, assign) BOOL needToRestart;
@property (nonatomic, strong) NSURLRequest *request;
@property (nonatomic, assign, readonly) BOOL isFinished;
@property (nonatomic, assign, readonly) BOOL isSupportRange;
@property (nonatomic, strong) NSURLSessionDownloadTask *downloadTask;
@end

@interface YCDownloader()<NSURLSessionDelegate>
{
    BGRecreateSessionBlock _bgRCSBlock;
    dispatch_source_t _timerSource;
}
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, assign) BOOL isNeedCreateSession;
@property (nonatomic, strong) NSMutableDictionary *memCache;
@property (nonatomic, copy) BGCompletedHandler completedHandler;
@property (nonatomic, strong) NSMutableArray <YCDownloadTask *> *bgRCSTasks;
@end

@implementation YCDownloader

#pragma mark - init

+ (instancetype)downloader {
    static dispatch_once_t onceToken;
    static YCDownloader *_downloader;
    dispatch_once(&onceToken, ^{
        _downloader = [[self alloc] initWithPrivate];
    });
    return _downloader;
}

- (instancetype)initWithPrivate {
    if (self = [super init]) {
        NSLog(@"[YCDownloader init]");
        _session = [self backgroundUrlSession];
        _memCache = [NSMutableDictionary dictionary];
        _bgRCSTasks = [NSMutableArray array];
        [self recoveryExceptionTasks];
        [self addNotification];
    }
    return self;
}


- (instancetype)init {
    NSAssert(false, @"use +[YCDownloader downloader] instead!");
    return nil;
}
- (NSString *)backgroundSessionIdentifier {
    NSString *bundleId = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
    NSString *identifier = [NSString stringWithFormat:@"%@.BGS.YCDownloader", bundleId];
    return identifier;
}

- (NSURLSession *)backgroundUrlSession {
    NSURLSession *session = nil;
    NSString *identifier = [self backgroundSessionIdentifier];
    NSURLSessionConfiguration* sessionConfig = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:identifier];
    sessionConfig.allowsCellularAccess = [[NSUserDefaults standardUserDefaults] boolForKey:kIsAllowCellar];
    session = [NSURLSession sessionWithConfiguration:sessionConfig delegate:self delegateQueue:[NSOperationQueue mainQueue]];
    return session;
}

- (NSInteger)sessionTaskIdWithDownloadTask:(NSURLSessionDownloadTask *)downloadTask {
    return downloadTask.taskIdentifier;
}

- (void)recoveryExceptionTasks {
    NSMutableDictionary *dictM = [self.session valueForKey:@"tasks"];
    [dictM enumerateKeysAndObjectsUsingBlock:^(NSNumber *_Nonnull key, NSURLSessionDownloadTask *obj, BOOL * _Nonnull stop) {
        YCDownloadTask *task = [YCDownloadDB taskWithStid:key.integerValue].firstObject;
        task ? [self memCacheDownloadTask:obj task:task] : [obj cancel];
    }];
}
- (void)addNotification {
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillBecomActive) name:UIApplicationDidBecomeActiveNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appWillResignActive) name:UIApplicationWillResignActiveNotification object:nil];
}

#pragma mark - event

- (void)appWillBecomActive {
    [self endTimer];
    self.completedHandler = nil;
    _bgRCSBlock = nil;
}

- (void)appWillResignActive {
    [YCDownloadDB saveAllData];
}

#pragma mark - download handler
- (NSURLRequest *)requestWithUrlStr:(NSString *)urlStr {
    NSURL *url = [NSURL URLWithString:urlStr];
    return [NSMutableURLRequest requestWithURL:url];;
}

- (YCDownloadTask *)downloadWithUrl:(NSString *)url progress:(YCProgressHanlder)progress completion:(YCCompletionHanlder)completion {
    NSURLRequest *request = [self requestWithUrlStr:url];
    return [self downloadWithRequest:request progress:progress completion:completion];
}

- (YCDownloadTask *)downloadWithRequest:(NSURLRequest *)request progress:(YCProgressHanlder)progress completion:(YCCompletionHanlder)completion{
    return [self downloadWithRequest:request progress:progress completion:completion priority:0];
}

- (YCDownloadTask *)downloadWithRequest:(NSURLRequest *)request progress:(YCProgressHanlder)progress completion:(YCCompletionHanlder)completion priority:(float)priority{
    YCDownloadTask *task = [YCDownloadTask taskWithRequest:request progress:progress completion:completion];
    [self saveDownloadTask:task];
    return task;
}

- (YCDownloadTask *)resumeDownloadTaskWithTid:(NSString *)tid progress:(YCProgressHanlder)progress completion:(YCCompletionHanlder)completion {
    YCDownloadTask *task = [YCDownloadDB taskWithTid:tid];
    task.completionHanlder = completion;
    task.progressHandler = progress;
    [self resumeDownloadTask:task];
    return task;
}

- (BOOL)resumeDownloadTask:(YCDownloadTask *)task {
    if(!task) return false;
    if (self.isNeedCreateSession) {
        //fix crash: #25 #35 Attempted to create a task in a session that has been invalidated
        [self.bgRCSTasks addObject:task];
        return true;
    }
    if (!task.resumeData && task.downloadTask.state == NSURLSessionTaskStateSuspended){
        [task.downloadTask resume];
        return true;
    }else if (task.downloadTask && self.memCache[task.downloadTask] && task.downloadTask.state == NSURLSessionTaskStateRunning) {
        return true;
    }else if (!task.resumeData && task.downloadTask){
        NSError *error = [NSError errorWithDomain:@"resume NSURLSessionDownloadTask error state" code:10004 userInfo:nil];
        [self completionDownloadTask:task localPath:nil error:error];
        return false;
    }else if (!task.resumeData && task.request){
        NSURLSessionDownloadTask *downloadTask = [self.session downloadTaskWithRequest:task.request];
        [self memCacheDownloadTask:downloadTask task:task];
        task.downloadTask = downloadTask;
        [task.downloadTask resume];
        return true;
    }else if (!task.resumeData){
        NSError *error = [NSError errorWithDomain:@"resume data nil!" code:10005 userInfo:nil];
        [self completionDownloadTask:task localPath:nil error:error];
        return false;
    }
    NSURLSessionDownloadTask *downloadTask = nil;
    @try {
        downloadTask = [YCResumeData downloadTaskWithCorrectResumeData:task.resumeData urlSession:self.session];
    } @catch (NSException *exception) {
        NSError *error = [NSError errorWithDomain:exception.description code:10002 userInfo:exception.userInfo];
        [self completionDownloadTask:task localPath:nil error:error];
        return false;
    }
    if (!downloadTask) {
        NSError *error = [NSError errorWithDomain:@"resume NSURLSessionDownloadTask nil!" code:10003 userInfo:nil];
        [self completionDownloadTask:task localPath:nil error:error];
        return false;
    }
    [self memCacheDownloadTask:downloadTask task:task];
    [downloadTask resume];
    task.resumeData = nil;
    return true;
    
}

- (void)pauseDownloadTask:(YCDownloadTask *)task{
    [task.downloadTask cancelByProducingResumeData:^(NSData * _Nullable resumeData) { }];
}

- (void)cancelDownloadTask:(YCDownloadTask *)task{
    [task.downloadTask cancel];
}

#pragma mark - recreate session

- (void)prepareRecreateSession {
    if (self.isNeedCreateSession) return;
    self.isNeedCreateSession = true;
    [[YCDownloadDB fetchAllDownloadTasks] enumerateObjectsUsingBlock:^(YCDownloadTask * _Nonnull task, NSUInteger idx, BOOL * _Nonnull stop) {
        if (task.downloadTask && task.downloadTask.state == NSURLSessionTaskStateRunning) {
            task.needToRestart = true;
            [self pauseDownloadTask:task];
        }
    }];
    [_session invalidateAndCancel];
}
- (void)recreateSession {
    
    _session = [self backgroundUrlSession];
    //恢复正在下载的task状态
    [[YCDownloadDB fetchAllDownloadTasks] enumerateObjectsUsingBlock:^(YCDownloadTask * _Nonnull task, NSUInteger idx, BOOL * _Nonnull stop) {
        task.downloadTask = nil;
        if (task.needToRestart) {
            task.needToRestart = false;
            [self resumeDownloadTask:task];
        }
    }];
    NSLog(@"recreate Session success");
}

#pragma mark - setter & getter

- (void)setAllowsCellularAccess:(BOOL)allowsCellularAccess {
    if ([self allowsCellularAccess] != allowsCellularAccess) {
        [[NSUserDefaults standardUserDefaults] setBool:allowsCellularAccess forKey:kIsAllowCellar];
        [self prepareRecreateSession];
    }
}

- (BOOL)allowsCellularAccess {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kIsAllowCellar];
}


#pragma mark - cache

- (void)memCacheDownloadTask:(NSURLSessionDownloadTask *)downloadTask  task:(YCDownloadTask *)task{
    task.downloadTask = downloadTask;
    //record taskId for coldLaunch recovery download
    task.stid = [self sessionTaskIdWithDownloadTask:downloadTask];
    [self.memCache setObject:task forKey:downloadTask];
    [self saveDownloadTask:task];
    NSLog(@"[memCache] add : %@ ",task);
}

- (void)removeMembCacheTask:(NSURLSessionDownloadTask *)downloadTask task:(YCDownloadTask *)task {
    task.stid = -1;
    [self.memCache removeObjectForKey:downloadTask];
    NSLog(@"[memCache] remove : %@ ",task);
}

- (void)completionDownloadTask:(YCDownloadTask *)task localPath:(NSString *)localPath error:(NSError *)error {
    if(task.downloadTask) [self removeMembCacheTask:task.downloadTask task:task];
    task.completionHanlder ? task.completionHanlder(localPath, error) : false;
    if (self.taskCachekMode == YCDownloadTaskCacheModeDefault && task.completionHanlder) {
        [self removeDownloadTask:task];
    }else{
        task.stid = -1;
        [self saveDownloadTask:task];
    }
    task.downloadTask = nil;
}

- (void)removeDownloadTask:(YCDownloadTask *)task {
    [YCDownloadDB removeTask:task];
}

- (void)saveDownloadTask:(YCDownloadTask *)task {
    [YCDownloadDB saveTask:task];
}

- (YCDownloadTask *)taskWithSessionTask:(NSURLSessionDownloadTask *)downloadTask {
    NSAssert(downloadTask, @"taskWithSessionTask downloadTask can not nil!");
    __block YCDownloadTask *task = [self.memCache objectForKey:downloadTask];
    NSString *url = [YCDownloadUtils urlStrWithDownloadTask:downloadTask];
    if (!task) {
        NSArray <YCDownloadTask *>* tasks = [YCDownloadDB taskWithStid:[self sessionTaskIdWithDownloadTask:downloadTask]];
        [tasks enumerateObjectsUsingBlock:^(YCDownloadTask * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if ([obj.downloadURL isEqualToString:url]) {
                task = obj;
                *stop = true;
            }
        }];
    }
    if (!task) {
        NSArray *tasks = [YCDownloadDB taskWithUrl:url];
        //fixme: optimize logic for multible tasks for same url
        [tasks enumerateObjectsUsingBlock:^(YCDownloadTask * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if (obj.downloadTask == nil && downloadTask.taskIdentifier == obj.stid) {
                task = obj;
                *stop = true;
            }
        }];
        if (!task) task = tasks.firstObject;
    }
    NSAssert(task, @"taskWithSessionTask task can not nil!");
    return task;
}

#pragma mark - hanlder

- (void)startTimer {
    [self endTimer];
    dispatch_source_t timerSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    _timerSource = timerSource;
    double interval = 1 * NSEC_PER_SEC;
    dispatch_source_set_timer(timerSource, dispatch_time(DISPATCH_TIME_NOW, interval), interval, 0);
    __weak typeof(self) weakself = self;
    dispatch_source_set_event_handler(timerSource, ^{
        [weakself callTimer];
    });
    dispatch_resume(_timerSource);
}

- (void)endTimer {
    if(_timerSource) dispatch_source_cancel(_timerSource);
    _timerSource = nil;
}

- (void)callTimer {
    NSLog(@"background time remain: %f", [UIApplication sharedApplication].backgroundTimeRemaining);
    //TODO: optimeze the logic for background session
    if ([UIApplication sharedApplication].backgroundTimeRemaining < 15 && !_bgRCSBlock) {
        NSLog(@"background time will up, need to call completed hander!");
        __weak typeof(self) weakSelf = self;
        _bgRCSBlock = ^{
            [weakSelf.bgRCSTasks.copy enumerateObjectsUsingBlock:^(YCDownloadTask *obj, NSUInteger idx, BOOL * _Nonnull stop) {
                [weakSelf resumeDownloadTask:obj];
                NSLog(@"[session invalidated] fix pass!");
            }];
            [weakSelf.bgRCSTasks removeAllObjects];
            [weakSelf endTimer];
            [weakSelf callBgCompletedHandler];
        };
        [self prepareRecreateSession];
    }
}

- (void)callBgCompletedHandler {
    if (self.completedHandler) {
        self.completedHandler();
        self.completedHandler = nil;
    }
}

-(void)addCompletionHandler:(BGCompletedHandler)handler identifier:(NSString *)identifier{
    if ([[self backgroundSessionIdentifier] isEqualToString:identifier]) {
        self.completedHandler = handler;
        //fix a crash in backgroud. for:  reason: backgroundDownload owner pid:252 preventSuspend  preventThrottleDownUI  preventIdleSleep  preventSuspendOnSleep
        [self startTimer];
    }
}

#pragma mark - NSURLSession delegate

- (void)URLSession:(NSURLSession *)session taskIsWaitingForConnectivity:(NSURLSessionTask *)task{
    
}

- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(nullable NSError *)error {
    if (self.isNeedCreateSession) {
        self.isNeedCreateSession = false;
        [self recreateSession];
        if (_bgRCSBlock) {
            _bgRCSBlock();
            _bgRCSBlock = nil;
        }
    }
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)location {
    
    NSString *localPath = [location path];
    YCDownloadTask *task = [self taskWithSessionTask:downloadTask];
    if (task.fileSize==0) [task updateTask];
    NSUInteger fileSize = [YCDownloadUtils fileSizeWithPath:localPath];
    NSError *error = nil;
    if (fileSize>0 && fileSize != task.fileSize) {
        NSString *errStr = [NSString stringWithFormat:@"[YCDownloader didFinishDownloadingToURL] fileSize Error, task fileSize: %zd tmp fileSize: %zd", task.fileSize, fileSize];
        NSLog(@"%@",errStr);
        error = [NSError errorWithDomain:errStr code:10001 userInfo:nil];
        localPath = nil;
    }else{
        task.downloadedSize = fileSize;
    }
    [self completionDownloadTask:task localPath:localPath error:error];
}

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite {
    YCDownloadTask *task = [self taskWithSessionTask:downloadTask];
    if (!task) {
        [downloadTask cancel];
        NSAssert(false,@"didWriteData task nil!");
    }
    task.downloadedSize = (NSUInteger)totalBytesWritten;
    if(task.fileSize==0) [task updateTask];
    task.progress.totalUnitCount = totalBytesExpectedToWrite;
    task.progress.completedUnitCount = totalBytesWritten;
    if(task.progressHandler) task.progressHandler(task.progress, task);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionDownloadTask *)downloadTask didCompleteWithError:(NSError *)error {
    if (!error) return;
    YCDownloadTask *task = [self taskWithSessionTask:downloadTask];
    // check whether resume data are available
    NSData *resumeData = [error.userInfo objectForKey:NSURLSessionDownloadTaskResumeData];
    if (resumeData) {
        //can resume
        if (YC_DEVICE_VERSION >= 11.0f && YC_DEVICE_VERSION < 11.2f) {
            //修正iOS11 多次暂停继续 文件大小不对的问题
            resumeData = [YCResumeData cleanResumeData:resumeData];
        }
        //通过之前保存的resumeData，获取断点的NSURLSessionTask，调用resume恢复下载
        task.resumeData = resumeData;
        id resumeDataObj = [NSPropertyListSerialization propertyListWithData:resumeData options:0 format:0 error:nil];
        if ([resumeDataObj isKindOfClass:[NSDictionary class]]) {
            NSDictionary *resumeDict = resumeDataObj;
            task.tmpName = [resumeDict valueForKey:@"NSURLSessionResumeInfoTempFileName"];
        }
        task.resumeData = resumeData;
        [self saveDownloadTask:task];
        [self removeMembCacheTask:downloadTask task:task];
        task.downloadTask = nil;
    }else{
        //cannot resume
        NSLog(@"[didCompleteWithError] : %@",error);
        [self completionDownloadTask:task localPath:nil error:error];
    }
    
}

@end