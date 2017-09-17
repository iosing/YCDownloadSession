//
//  YCDownloadManager.h
//  YCDownloadSession
//
//  Created by wz on 17/3/24.
//  Copyright © 2017年 onezen.cc. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "YCDownloadTask.h"
#import "YCDownloadItem.h"

#define kCommonUtilsGigabyte (1024 * 1024 * 1024)
#define kCommonUtilsMegabyte (1024 * 1024)
#define kCommonUtilsKilobyte 1024

@interface YCDownloadManager : NSObject


/**
 开始一个后台下载任务
 
 @param downloadURLString 下载url
 */
+ (void)startDownloadWithUrl:(NSString *)downloadURLString fileName:(NSString *)fileName thumbImageUrl:(NSString *)imagUrl;

/**
 暂停一个后台下载任务
 
 @param downloadURLString 下载url
 */
+ (void)pauseDownloadWithUrl:(NSString *)downloadURLString;

/**
 继续开始一个后台下载任务
 
 @param downloadURLString 下载url
 */
+ (void)resumeDownloadWithUrl:(NSString *)downloadURLString;

/**
 删除一个后台下载任务，同时会删除当前任务下载的缓存数据
 
 @param downloadURLString 下载url
 */
+ (void)stopDownloadWithUrl:(NSString *)downloadURLString;


/**
 暂停所有的下载
 */
+ (void)pauseAllDownloadTask;



+ (NSArray *)downloadList;
+ (NSArray *)finishList;
+ (NSUInteger)videoCacheSize;
+ (NSUInteger)fileSystemFreeSize;

+ (void)saveDownloadStatus;
+ (NSString *)fileSizeStringFromBytes:(uint64_t)byteSize;


@end
