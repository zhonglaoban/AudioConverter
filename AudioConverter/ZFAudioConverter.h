//
//  ZFAudioConverter.h
//  AudioConverter
//
//  Created by 钟凡 on 2020/11/4.
//  Copyright © 2020 钟凡. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZFAudioConverter : NSObject

- (void)openInputFile:(NSString *)path;
- (void)createOutputFile:(NSString *)path type:(AudioFileTypeID)type format:(AudioStreamBasicDescription *)format;
- (void)convert;
- (void)closeFiles;

@end

NS_ASSUME_NONNULL_END
