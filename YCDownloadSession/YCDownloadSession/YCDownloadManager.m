//
//  YCDownloadManager.m
//  YCDownloadSession
//
//  Created by wangzhen on 17/3/24.
//  Copyright © 2017年 onezen.cc. All rights reserved.
//

#import "YCDownloadManager.h"
#import "YCDownloadSession.h"

@interface YCDownloadManager ()

@end

@implementation YCDownloadManager

/**
 开始一个后台下载任务
 
 @param downloadURLString 下载url
 @param savePath 保存路径
 */
+ (void)startDownloadWithUrl:(NSString *)downloadURLString savePath:(NSString *)savePath {
    [[YCDownloadSession downloadSession] startDownloadWithUrl:downloadURLString savePath:savePath];
}

/**
 暂停一个后台下载任务
 
 @param downloadURLString 下载url
 */
+ (void)pauseDownloadWithUrl:(NSString *)downloadURLString {
    [[YCDownloadSession downloadSession] pauseDownloadWithUrl:downloadURLString];
}

/**
 继续开始一个后台下载任务
 
 @param downloadURLString 下载url
 */
+ (void)resumeDownloadWithUrl:(NSString *)downloadURLString {
    [[YCDownloadSession downloadSession] resumeDownloadWithUrl:downloadURLString];
}

/**
 删除一个后台下载任务，同时会删除当前任务下载的缓存数据
 
 @param downloadURLString 下载url
 */
+ (void)stopDownloadWithUrl:(NSString *)downloadURLString {
    [[YCDownloadSession downloadSession] stopDownloadWithUrl:downloadURLString];
}


/**
 保存下载进度
 */
+ (void)saveDownloadStatus {
    [[YCDownloadSession downloadSession] saveDownloadStatus];
}

/**
 暂停所有的下载
 */
+ (void)pauseAllDownloadTask {
    [[YCDownloadSession downloadSession] pauseAllDownloadTask];
}

+ (NSArray *)downloadList {
    NSMutableArray *arrM = [NSMutableArray array];
    NSDictionary *downloadListDict = [[YCDownloadSession downloadSession] downloadItems];
    for (YCDownloadItem *item in downloadListDict) {
        [arrM addObject:item];
    }
    return arrM;
}
+ (NSArray *)finishList {
    NSMutableArray *arrM = [NSMutableArray array];
    NSDictionary *downloadListDict = [[YCDownloadSession downloadSession] downloadedItems];
    for (YCDownloadItem *item in downloadListDict) {
        [arrM addObject:item];
    }
    return arrM;
}
+ (NSUInteger)videoCacheSize {
    NSUInteger size = 0;
    NSArray *downloadList = [self downloadList];
    NSArray *finishList = [self finishList];
    for (YCDownloadItem *item in downloadList) {
        size += item.downloadedSize;
    }
    for (YCDownloadItem *item in finishList) {
        size += item.fileSize;
    }
    return size;

}
+ (NSUInteger)fileSystemFreeSize {
    uint64_t totalFreeSpace = 0;
    NSError *error = nil;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSDictionary *dictionary = [[NSFileManager defaultManager] attributesOfFileSystemForPath:[paths lastObject] error: &error];
    
    if (dictionary) {
        NSNumber *freeFileSystemSizeInBytes = [dictionary objectForKey:NSFileSystemFreeSize];
        totalFreeSpace = [freeFileSystemSizeInBytes floatValue];
    }
    return totalFreeSpace;
}


@end