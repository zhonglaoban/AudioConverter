//
//  ViewController.m
//  AudioConverter
//
//  Created by 钟凡 on 2019/11/20.
//  Copyright © 2019 钟凡. All rights reserved.
//

#import "ZFAudioConverter.h"
#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>

@interface ViewController ()

@property (nonatomic, strong) ZFAudioConverter *converter;

@end


@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _converter = [ZFAudioConverter new];
    [self convert];
}
-(void)convert {
//    NSString *source1 = [[NSBundle mainBundle] pathForResource:@"goodbye" ofType:@"mp3"];
    NSString *source1 = [[NSBundle mainBundle] pathForResource:@"DrumsMonoSTP" ofType:@"aif"];
    NSString *source2 = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).lastObject stringByAppendingPathComponent:@"a.caf"];
    [_converter openInputFile:source1];
    
    NSLog(@"source1: %@", source1);
    NSLog(@"source2: %@", source2);
    
    int length = 100000;
    void *buffer = malloc(length);
    AudioStreamBasicDescription dataFormat = {};
    dataFormat.mFormatID = kAudioFormatLinearPCM;
    dataFormat.mSampleRate = 16000;
    dataFormat.mChannelsPerFrame = 1;
    dataFormat.mBitsPerChannel = 16;
    dataFormat.mBytesPerPacket = 1 * sizeof(SInt16);
    dataFormat.mBytesPerFrame = 1 * sizeof(SInt16);
    dataFormat.mFramesPerPacket = 1;
    dataFormat.mFormatFlags = kLinearPCMFormatFlagIsBigEndian | kLinearPCMFormatFlagIsSignedInteger;
    
    [_converter createOutputFile:source2 type:kAudioFileCAFType format:&dataFormat];
    [_converter convert];
    [_converter closeFiles];
    free(buffer);
}
@end
