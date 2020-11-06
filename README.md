# AudioToolBox中AudioConverter的使用

在前面的几篇文章中，我们关注的是相关API实现的功能，一些封装度较高的API会自动的帮我们实现不同音频格式的转换，如`ExtAudioFile`和`Audio Queue Service`。那么，如果我们只想单纯的做格式转换应该怎么处理呢，本篇文章将带你一探究竟。

本篇文章分为以下2个部分：
1、`AudioFile`相关的读写文件。
2、`AudioConverter`的具体使用。

## AudioFile
和[ExtAudioFile如何使用](https://www.jianshu.com/p/03491bf9bd0b)一篇中类似，AudioFile也有打开文件，创建文件，读取属性等操作，我们这里重点介绍一些不太一样的地方。
### 读数据
```objc
AudioFileReadPacketData (	AudioFileID  					inAudioFile, 
                       		Boolean							inUseCache,
                       		UInt32 *						ioNumBytes,
                       		AudioStreamPacketDescription * __nullable outPacketDescriptions,
                       		SInt64							inStartingPacket, 
                       		UInt32 * 						ioNumPackets,
                       		void * __nullable				outBuffer)
```
- inAudioFile 文件句柄
- inUseCache 是否缓存，如果多次访问，使用缓存会快一点。
- ioNumBytes 读取的数据大小。
- outPacketDescriptions 数据包的描述文件，动态码率格式才需要。
- inStartingPacket 文件指针位置，如果一次读不完数据，需要更新读取位置。
- ioNumPackets 数据包的个数，如果数据不够，这个指针会返回实际度了多少个数据包。
- outBuffer 数据内容
还有一个类似的API叫`AudioFileReadPackets`，读取动态码率格式时，`AudioFileReadPacketData`更高效。
### 写数据
```objc
AudioFileWritePackets (	AudioFileID							inAudioFile,  
                        Boolean								inUseCache,
                        UInt32								inNumBytes,
                        const AudioStreamPacketDescription * __nullable inPacketDescriptions,
                        SInt64								inStartingPacket, 
                        UInt32								*ioNumPackets, 
                        const void							*inBuffer)
```
- inAudioFile 文件句柄
- inUseCache 是否缓存，如果多次访问，使用缓存会快一点。
- ioNumBytes 写入的数据大小。
- outPacketDescriptions 数据包的描述文件，动态码率格式才需要。
- inStartingPacket 文件指针位置，如果一次写不完数据，需要更新写入的位置。
- ioNumPackets 数据包的个数，如果数据超过最大可写入大小，这个指针会返回实际写了多少个数据包。
- outBuffer 数据内容

## AudioConverter
### 创建
```objc
AudioConverterRef audioConverter;
OSStatus status = AudioConverterNew(&_inputFormat,
                                    _outputFormat,
                                    &audioConverter);
CheckError(status, "AudioConveterNew failed");
```
比较简单，输入格式，输出格式，一个AudioConverterRef指针。
### 数据转换
```objc
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
```
outputBufferSize我们可以自定义一个大小，这里packetsPerBuffer需要做一点计算，对于动态码率和静态码率有不同的处理。动态码率处理需要从`audioConverter`中获取最大包大小外，还需为`AudioStreamPacketDescription`数组分配好空间。具体实现看代码。
```objc
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
```
### 数据填充回调
```objc
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
```
这个回调里有3点需要注意的。
1、创建的`converter.sourceBuffer`需要及时释放。
2、更新文件指针`converter.inputFilePacketPosition`。
3、将从文件中读取的`AudioStreamPacketDescription`传给`converter`，以便在数据转换的时候使用。

### 销毁创建的资源
```objc
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
```
[Github地址](https://github.com/zhonglaoban/AudioConverter)


