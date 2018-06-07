#import "AudioRecordAndPlay.h"
//pu1SampleSz:bytes_per_sample
//pu4TotalSz:input size

#define SAMPLE_RATE 16000

////////////////////////////////////////////////////////////////////////////////////////////////////////
///把float格式的音频数据，转换为int16格式的
void tdav_codec_float_to_int16 (void *pInput, void* pOutput, uint8_t* pu1SampleSz, uint32_t* pu4TotalSz, bool bFloat)
{
    int16_t i2SampleNumTotal = *pu4TotalSz / *pu1SampleSz;  //
    int16_t *pi2Buf = (int16_t *)pOutput;
    if (!pInput || !pOutput) {
        return;
    }
    
    if (bFloat && *pu1SampleSz == 4) {
        float* pf4Buf = (float*)pInput;
        for (int i = 0; i < i2SampleNumTotal; i++) {
            pi2Buf[i] = (int16_t)(pf4Buf[i] * 32767 + 0.5); // float -> int16 + rounding
        }
        *pu4TotalSz /= 2;     // transfer to int16 byte size
        *pu1SampleSz /= 2;
    }
    if (!bFloat && *pu1SampleSz == 2) {
        memcpy (pOutput, pInput, *pu4TotalSz);
    }
    return;
}

///把int16格式的音频数据，转换为float格式的
void tdav_codec_int16_to_float (void *pInput, void* pOutput, uint8_t* pu1SampleSz, uint32_t* pu4TotalSz, bool bInt16)
{
    int16_t i2SampleNumTotal = *pu4TotalSz / *pu1SampleSz;
    float *pf4Buf = (float *)pOutput;
    if (!pInput || !pOutput) {
        return;
    }
    
    if ( bInt16 && *pu1SampleSz == 2) {
        int16_t* pi2Buf = (int16_t*)pInput;
        for (int i = 0; i < i2SampleNumTotal; i++) {
            pf4Buf[i] =    (float)pi2Buf[i] / 32767 ;  // int16 -> float
        }
        *pu4TotalSz *= 2;     // transfer to int16 byte size
        *pu1SampleSz *= 2;
    }
    if (!bInt16 && *pu1SampleSz == 4) {     //如果是float，直接拷贝
        memcpy (pOutput, pInput, *pu4TotalSz);
    }
    return;
}
////////////////////////////////////////////////////////////////////////////////////////////////////////


void checkStatus(int code, char*  param = "" ){
    if(code != 0 )
    {
        NSLog(@"checkStatus error:%s:    %d",  param, code );
    }
}

@interface AudioRecordAndPlay(){
    AudioComponentInstance audioUnit;
    int kInputBus;
    int kOutputBus;

    NSCondition *mAudioLock;
    
    int mDataLen;               //等待播放的pcm大小
    void *mPCMData;             //等待播放的pcm数据
    
    NSMutableData* mRecordData;     //麦克风采集的数据放在缓存里，等积累2秒的数据后，给扬声器播放
    bool savemic; //是否把麦克风采集数据计入文件，用于检查是否采集正确
    FILE* mic;      //麦克风采集的pcm数据文件
}
@end


@implementation AudioRecordAndPlay

- (id) init {
    self = [super init];
    
    kInputBus = 1;
    kOutputBus = 0;
    mDataLen=0;
    
    savemic = false;
    
    mRecordData = [[NSMutableData alloc] init];
 
    if( savemic )
    {
        mic = fopen( "/tmp/mic.pcm","wb");
    }

    [self initVoiceProcessingIO];
    
    return self;
}

-(void) initVoiceProcessingIO
{
    ///创建audio unit
    OSStatus status;
    // Describe audio component
    AudioComponentDescription desc;
    desc.componentType = kAudioUnitType_Output;
    desc.componentSubType = kAudioUnitSubType_VoiceProcessingIO;
    desc.componentFlags = 0;
    desc.componentFlagsMask = 0;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    // Get component
    AudioComponent inputComponent = AudioComponentFindNext(NULL, &desc);
    
    // Get audio units
    status = AudioComponentInstanceNew(inputComponent, &audioUnit);
    checkStatus(status);
    
    
#if TARGET_OS_IPHONE
    ///在mac上，input, output都是默认打开，且不能修改的。所以，不需要下面两个设置
    // Enable IO for recording
    UInt32 flag = 1;
    status = AudioUnitSetProperty(audioUnit,
                                  kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Input,
                                  kInputBus,
                                  &flag,
                                  sizeof(flag));
    checkStatus(status， "EnableIO, input");

    // Enable IO for playback
    UInt32 zero = 1;// 设置为0 关闭playback
    status = AudioUnitSetProperty(audioUnit,
                                  kAudioOutputUnitProperty_EnableIO,
                                  kAudioUnitScope_Output,
                                  kOutputBus,
                                  &zero,
                                  sizeof(zero));
    checkStatus(status, "EnableIO, output");
#endif
    
    UInt32 size = 0;

    // Describe format
    AudioStreamBasicDescription audioFormat = {0};

    audioFormat.mSampleRate = SAMPLE_RATE;
    audioFormat.mFormatID = kAudioFormatLinearPCM;
    audioFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked |kAudioFormatFlagIsNonInterleaved;
    audioFormat.mChannelsPerFrame = 1;
    audioFormat.mFramesPerPacket = 1;
    audioFormat.mBitsPerChannel = 16;
    audioFormat.mBytesPerPacket = 2;
    audioFormat.mBytesPerFrame = 2;
    audioFormat.mReserved = 0;
    
    // Apply format
    status = AudioUnitSetProperty(audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output,
                                  kInputBus,
                                  &audioFormat,
                                  sizeof(audioFormat));
    
    checkStatus( status, "StreamFormat  input" );
    
    UInt32 preferredBufferSize = (( 20 * audioFormat.mSampleRate) / 1000); // in bytes
    size = sizeof (preferredBufferSize);
    
    // Set input callback
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = recordingCallback;
    callbackStruct.inputProcRefCon = (__bridge void *)(self);
    status = AudioUnitSetProperty(audioUnit,
                                  kAudioOutputUnitProperty_SetInputCallback,
                                  kAudioUnitScope_Global,
                                  kInputBus,
                                  &callbackStruct,
                                  sizeof(callbackStruct));
    checkStatus(status, "SetInputCallback");
    
    ///测试发现，kAudioFormatFlagIsSignedInteger ，16位的格式，可以采集，但是无法播放声音
    ///所以播放端使用了kAudioFormatFlagIsFloat格式，并在采集数据后需要进行转换
    AudioStreamBasicDescription audioFormatPlay = {0};
    audioFormatPlay.mSampleRate = SAMPLE_RATE;
    audioFormatPlay.mFormatID = kAudioFormatLinearPCM;
    audioFormatPlay.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked |kAudioFormatFlagIsNonInterleaved ;
    audioFormatPlay.mChannelsPerFrame = 1;
    audioFormatPlay.mFramesPerPacket = 1;
    audioFormatPlay.mBitsPerChannel = 32;
    audioFormatPlay.mBytesPerPacket = 4;
    audioFormatPlay.mBytesPerFrame = 4;
    audioFormatPlay.mReserved = 0;

    status = AudioUnitSetProperty(audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  kOutputBus,
                                  &audioFormatPlay,
                                  sizeof(audioFormatPlay));
    checkStatus(status, "StreamFormat Output");
    

///设置buffsize的时候，IOS和MAC系统不一样
#if TARGET_OS_OSX
    status = AudioUnitSetProperty ( audioUnit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &preferredBufferSize, size);
    checkStatus(status, "Set BufferFrameSize");
    
    status = AudioUnitGetProperty ( audioUnit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &preferredBufferSize, &size);
    NSLog(@"buffer size:%d",preferredBufferSize );
    checkStatus(status, "Get BufferFrameSize");
#else
    Float32 duration = ( 20.0 / 1000.f); // in seconds
    UInt32 dsize = sizeof (duration);
    status = AudioSessionSetProperty (kAudioSessionProperty_PreferredHardwareIOBufferDuration, sizeof (duration), &duration);
    checkStatus(status, "PreferredHardwareIOBufferDuration");
    
    status = AudioSessionGetProperty (kAudioSessionProperty_CurrentHardwareIOBufferDuration,&dsize, &duration );
    checkStatus(status,"CurrentHardwareIOBufferDuration");
    NSLog(@"buffer time:%d",duration );
#endif
    
    // Set output callback
    callbackStruct.inputProc = playbackCallback;
    callbackStruct.inputProcRefCon = (__bridge void *)(self);
    status = AudioUnitSetProperty(audioUnit,
                                  kAudioUnitProperty_SetRenderCallback,
                                  kAudioUnitScope_Global,
                                  kOutputBus,
                                  &callbackStruct,
                                  sizeof(callbackStruct));
    checkStatus(status, "SetRenderCallback");
    
    ///检查设置的streamFormat是否成功
    size = sizeof(audioFormat);
    status = AudioUnitGetProperty( audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Output,
                                  kInputBus,
                                  &audioFormat,
                                  &size);
    
    size = sizeof(audioFormatPlay);
    status = AudioUnitGetProperty( audioUnit,
                                  kAudioUnitProperty_StreamFormat,
                                  kAudioUnitScope_Input,
                                  kOutputBus,
                                  &audioFormatPlay,
                                  &size);
    
    
    
    // Initialise
    status = AudioUnitInitialize(audioUnit);
    checkStatus(status);
    
    mPCMData = malloc(MAX_BUFFER_SIZE);
    mAudioLock = [[NSCondition alloc]init];
}


-(AudioComponentInstance) audioUnit{
    return audioUnit;
}

-(void *)audioBuffer{
    return mPCMData;
}

-(void)processAudio:(AudioBufferList *)bufferList{
    [mAudioLock lock];
    [mRecordData appendBytes: bufferList[0].mBuffers[0].mData length:bufferList[0].mBuffers[0].mDataByteSize];
    [mAudioLock unlock];
  

    //积累2秒的数据后播放
    if( [mRecordData length] > SAMPLE_RATE * 4  )
    {
        [self play: mRecordData];
        
        [mAudioLock lock];
        [mRecordData resetBytesInRange:NSMakeRange(0, [mRecordData length])];
        [mRecordData setLength:0];
        [mAudioLock unlock];
    }
}

-(void)play:(NSData *)data{
    if(mPCMData == NULL){
        return;
    }
    
    [mAudioLock lock];
    
    static float* buff = new float[ SAMPLE_RATE * 4 ];
    memset( buff, 0 , sizeof( float ) * SAMPLE_RATE * 4 );
    uint8_t samplesize = 2;
    uint32_t totalsize = [mRecordData length];
    
    tdav_codec_int16_to_float( (void*)[data bytes],  buff,  &samplesize, &totalsize,  1 );
    
    if (totalsize > 0 && totalsize + mDataLen < MAX_BUFFER_SIZE) {
        memcpy( (char*)mPCMData+mDataLen, buff, totalsize );
        mDataLen += totalsize;
    }
    
    [mAudioLock unlock];
}

-(void)Start{
    OSStatus state = AudioOutputUnitStart(audioUnit);
    return ;
}

-(void)Stop{
    OSStatus state =  AudioOutputUnitStop(audioUnit);
    return ;
}

static OSStatus recordingCallback(void *inRefCon,
                                  AudioUnitRenderActionFlags *ioActionFlags,
                                  const AudioTimeStamp *inTimeStamp,
                                  UInt32 inBusNumber,
                                  UInt32 inNumberFrames,
                                  AudioBufferList *ioData) {
    
    // Because of the way our audio format (setup below) is chosen:
    // we only need 1 buffer, since it is mono
    // Samples are 16 bits = 2 bytes.
    // 1 frame includes only 1 sample
    
    AudioRecordAndPlay *ars = (__bridge AudioRecordAndPlay*)inRefCon;
    
    AudioBuffer buffer;
    
    buffer.mNumberChannels = 1;
    buffer.mDataByteSize = inNumberFrames * 2;
    buffer.mData = NULL;
    
    // Put buffer in a AudioBufferList
    AudioBufferList bufferList;
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0] = buffer;
    
    // Then:
    // Obtain recorded samples
    
    OSStatus status;
    
    status = AudioUnitRender([ars audioUnit],
                             ioActionFlags,
                             inTimeStamp,
                             inBusNumber,
                             inNumberFrames,
                             &bufferList);
    checkStatus(status);
    
    if( status == 0 )
    {
        if( ars->savemic && ars->mic != nullptr  )
        {
            fwrite( bufferList.mBuffers[0].mData, 1, bufferList.mBuffers[0].mDataByteSize, ars->mic );
        }
        
        
        [ars processAudio:&bufferList];
    }
    
    // Now, we have the samples we just read sitting in buffers in bufferList
    // Process the new data
    
    // release the malloc'ed data in the buffer we created earlier
//    free(bufferList.mBuffers[0].mData);
    
    return noErr;
}

static OSStatus playbackCallback(void *inRefCon,
                                AudioUnitRenderActionFlags *ioActionFlags,
                                const AudioTimeStamp *inTimeStamp,
                                UInt32 inBusNumber,
                                UInt32 inNumberFrames,
                                AudioBufferList *ioData) {
    // Notes: ioData contains buffers (may be more than one!)
    // Fill them up as much as you can. Remember to set the size value in each buffer to match how
    // much data is in the buffer.
    AudioRecordAndPlay *ars = (__bridge AudioRecordAndPlay*)inRefCon;
    
    for (int i=0; i < ioData->mNumberBuffers; i++) { // in practice we will only ever have 1 buffer, since audio format is mono
        AudioBuffer buffer = ioData->mBuffers[i];

        BOOL isFull = NO;
        [ars->mAudioLock lock];
        if( ars->mDataLen >=  buffer.mDataByteSize)
        {
            memcpy(buffer.mData,  ars->mPCMData, buffer.mDataByteSize);
            ars->mDataLen -= buffer.mDataByteSize;
            memmove( ars->mPCMData,  (char*)ars->mPCMData+buffer.mDataByteSize, ars->mDataLen);
            isFull = YES;
        }
        [ ars->mAudioLock unlock];
        if (!isFull) {
            memset(buffer.mData, 0, buffer.mDataByteSize);
        }
    }
    
    return noErr;
}

@end
