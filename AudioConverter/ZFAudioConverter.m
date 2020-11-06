//
//  ZFAudioConverter.m
//  AudioConverter
//
//  Created by 钟凡 on 2020/11/4.
//  Copyright © 2020 钟凡. All rights reserved.
//

#import "ZFAudioConverter.h"

static void CheckError(OSStatus error, const char *operation)
{
    if (error == noErr) return;
    char errorString[20];
    // See if it appears to be a 4-char-code
    *(UInt32 *)(errorString + 1) = CFSwapInt32HostToBig(error);
    if (isprint(errorString[1]) && isprint(errorString[2]) && isprint(errorString[3]) && isprint(errorString[4])) {
        errorString[0] = errorString[5] = '\'';
        errorString[6] = '\0';
    } else {
        // No, format it as an integer
        sprintf(errorString, "%d", (int)error);
        fprintf(stderr, "Error: %s (%s)\n", operation, errorString);
    }
}

@interface ZFAudioConverter()

@property (nonatomic) AudioFileID inputFile;
@property (nonatomic) AudioFileID outputFile;

@property (nonatomic) AudioStreamBasicDescription inputFormat;
@property (nonatomic) AudioStreamBasicDescription *outputFormat;
@property (nonatomic) AudioStreamPacketDescription *aspd;
@property (nonatomic) void *sourceBuffer;

@property (nonatomic, assign) UInt32 inputFilePacketPosition;
@property (nonatomic, assign) UInt64 inputFilePackets;
@property (nonatomic, assign) UInt32 inputFileMaximumPacketSize;

@end

OSStatus MyAudioConverterCallback(AudioConverterRef inAudioConverter,
                                  UInt32 *ioDataPacketCount,
                                  AudioBufferList *ioData,
                                  AudioStreamPacketDescription **outDataPacketDescription,
                                  void *inUserData)
{
    ZFAudioConverter *converter = (__bridge ZFAudioConverter *)inUserData;
    UInt32 ioNumBytes = *ioDataPacketCount * converter.inputFileMaximumPacketSize;
    if (converter.sourceBuffer) {
        free(converter.sourceBuffer);
        converter.sourceBuffer = NULL;
    }
    converter.sourceBuffer = malloc(ioNumBytes);

    OSStatus status = AudioFileReadPacketData(converter.inputFile,
                                              false,
                                              &ioNumBytes,
                                              converter.aspd,
                                              converter.inputFilePacketPosition,
                                              ioDataPacketCount,
                                              converter.sourceBuffer);
    CheckError(status, "AudioFileReadPacketData");
    converter.inputFilePacketPosition += *ioDataPacketCount;
    
    ioData->mBuffers[0].mData = converter.sourceBuffer;
    ioData->mBuffers[0].mDataByteSize = ioNumBytes;
    
    //convert时创建的aspd，将读取文件中的aspd赋值给它
    if (outDataPacketDescription)
        *outDataPacketDescription = converter.aspd;
    
    return status;
}

@implementation ZFAudioConverter
- (void)openInputFile:(NSString *)path {
    CFURLRef fileUrl = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)path, kCFURLPOSIXPathStyle, false);
    OSStatus status = AudioFileOpenURL(fileUrl,
                                       kAudioFileReadPermission,
                                       0,
                                       &(_inputFile));
    CheckError(status, "AudioFileOpenURL failed");
    
    UInt32 propSize = sizeof(AudioStreamBasicDescription);
    status = AudioFileGetProperty(_inputFile,
                                  kAudioFilePropertyDataFormat,
                                  &propSize,
                                  &_inputFormat);
    CheckError(status, "Get File DataFormat failed");
    propSize = sizeof(_inputFilePackets);
    status = AudioFileGetProperty(_inputFile,
                                  kAudioFilePropertyAudioDataPacketCount,
                                  &propSize,
                                  &_inputFilePackets);
    CheckError(status, "Get File packets failed");
    propSize = sizeof(_inputFileMaximumPacketSize);
    status = AudioFileGetProperty(_inputFile,
                                  kAudioFilePropertyMaximumPacketSize,
                                  &propSize,
                                  &_inputFileMaximumPacketSize);
    CheckError(status, "Get File max packet size");
}
- (void)createOutputFile:(NSString *)path type:(AudioFileTypeID)type format:(AudioStreamBasicDescription *)format {
    CFURLRef outputFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)path, kCFURLPOSIXPathStyle, false);
    OSStatus status = AudioFileCreateWithURL(outputFileURL,
                                             kAudioFileAIFFType,
                                             format,
                                             kAudioFileFlags_EraseFile,
                                             &_outputFile);
    _outputFormat = format;
    CheckError(status, "AudioFileCreateWithURL failed");
}
- (void)convert {
    AudioConverterRef audioConverter;
    OSStatus status = AudioConverterNew(&_inputFormat,
                                        _outputFormat,
                                        &audioConverter);
    CheckError(status, "AudioConveterNew failed");
    
    UInt32 packetsPerBuffer = 0;
    UInt32 outputBufferSize = 32 * 1024; // 32 KB is a good starting point
    UInt32 sizePerPacket = _inputFormat.mBytesPerPacket;
    //包大小不固定，需要使用AudioStreamPacketDescription
    if (sizePerPacket == 0) {
        UInt32 size = sizeof(sizePerPacket);
        status = AudioConverterGetProperty(audioConverter,
                                           kAudioConverterPropertyMaximumOutputPacketSize,
                                           &size,
                                           &sizePerPacket);
        CheckError(status, "Couldn't get kAudioConverterPropertyMaximumOutputPacketSize");
        if (sizePerPacket > outputBufferSize)
            outputBufferSize = sizePerPacket;
        packetsPerBuffer = outputBufferSize / sizePerPacket;
        _aspd = (AudioStreamPacketDescription *)malloc(sizeof(AudioStreamPacketDescription) * packetsPerBuffer);
    } else {
        packetsPerBuffer = outputBufferSize / sizePerPacket;
    }

    void *outputBuffer = malloc(outputBufferSize);
    UInt32 outputFilePacketPosition = 0;
    while(1) {
        AudioBufferList convertedData;
        convertedData.mNumberBuffers = 1;
        convertedData.mBuffers[0].mNumberChannels = _inputFormat.mChannelsPerFrame;
        convertedData.mBuffers[0].mDataByteSize = outputBufferSize;
        convertedData.mBuffers[0].mData = outputBuffer;
        UInt32 ioOutputDataPackets = packetsPerBuffer;
        status = AudioConverterFillComplexBuffer(audioConverter,
                                                 MyAudioConverterCallback,
                                                 (__bridge void *)(self),
                                                 &ioOutputDataPackets,
                                                 &convertedData,
                                                 _aspd);
        CheckError(status, "AudioConverterFillComplexBuffer");
        if (status || !ioOutputDataPackets)
        {
            break; // This is the termination condition
        }
        //第三个参数不能传packets，要传bytes
        UInt32 inNumBytes = sizePerPacket * ioOutputDataPackets;
        status = AudioFileWritePackets(_outputFile,
                                       false,
                                       inNumBytes,
                                       NULL,
                                       outputFilePacketPosition,
                                       &ioOutputDataPackets,
                                       outputBuffer);
        CheckError(status, "Couldn't write packets to file");
        outputFilePacketPosition += ioOutputDataPackets;
    }
    if (outputBuffer) {
        free(outputBuffer);
    }
    if (_aspd) {
        free(_aspd);
    }
    if (_sourceBuffer) {
        free(_sourceBuffer);
    }
    AudioConverterDispose(audioConverter);
}
- (void)closeFiles {
    AudioFileClose(_inputFile);
    AudioFileClose(_outputFile);
}
@end


