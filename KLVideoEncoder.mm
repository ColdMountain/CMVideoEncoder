//
//  KLH265Encoder.m
//  H265Demo
//
//  Created by Cold Mountain on 2022/7/27.
//

#import "KLVideoEncoder.h"

#import <VideoToolbox/VideoToolbox.h>
#import <CoreFoundation/CFDictionary.h>

//#define Log

static KLVideoEncoder *Encoder = NULL;

@interface KLVideoEncoder()
{
    KLEncoderType encoderType;
    int frameID;
    int w;
    int h;
    dispatch_queue_t kl_EncodeQueue;
    VTCompressionSessionRef EncodingSession;
    
    uint8_t    *kEncoderData;
    int32_t     kEncoderSize;
    
    int64_t    ptsOldTime;
    int64_t    ptsNewTime;
    
    int64_t    fPTSTime;
}
@end

@implementation KLVideoEncoder


- (instancetype)initEncodeWithType:(KLEncoderType)type width:(int)width height:(int)height{
    self = [super init];
    if (self) {
        kl_EncodeQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0); // 获取全局队列，后台执行
        encoderType  = type;
        kEncoderSize = width*height*3/2;
        kEncoderData = new uint8_t[kEncoderSize];
        ptsOldTime = -1;
        ptsNewTime = -1;
        fPTSTime = -1;
        
        [self initVideoToolBoxWithWidth:width height:height];
    }
    return self;
}

- (void)initVideoToolBoxWithWidth:(int)width height:(int)height {
    dispatch_sync(kl_EncodeQueue  , ^{  // 在后台 同步执行 （同步，需要加锁）
        self->frameID = 0;
        self->w=width;
        self->h=height;
        // ----- 1. 创建session -----
        OSStatus status = -1;
        if (encoderType == KLH264Encoder) {
            status = VTCompressionSessionCreate(NULL,
                                                width,
                                                height,
                                                kCMVideoCodecType_H264,
                                                NULL,
                                                NULL,
                                                NULL,
                                                didCompressH264Encoder,
                                                (__bridge void *)(self),
                                                &self->EncodingSession);
            NSLog(@"H264: VTCompressionSessionCreate %d", (int)status);
        }else if (encoderType == KLHEVCEncoder){
            status = VTCompressionSessionCreate(NULL,
                                                width,
                                                height,
                                                kCMVideoCodecType_HEVC,
                                                NULL,
                                                NULL,
                                                NULL,
                                                didCompressHEVCEncoder,
                                                (__bridge void *)(self),
                                                &self->EncodingSession);
            NSLog(@"HEVC: VTCompressionSessionCreate %d", (int)status);
        }
        if (status != 0)
        {
            if (encoderType == KLH264Encoder) {
                NSLog(@"H264 Session 创建失败");
            }else if (encoderType == KLHEVCEncoder) {
                if (status == -12908) {
                    NSLog(@"请使用iPhone7及以上设备");
                }
                NSLog(@"HEVC Session 创建失败");
            }
            return;
        }
        
        // ----- 2. 设置session属性 -----
        // 设置实时编码输出（避免延迟）
        VTSessionSetProperty(self->EncodingSession, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
        if (encoderType == KLH264Encoder) {
            VTSessionSetProperty(self->EncodingSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_Baseline_AutoLevel);
        }else if (encoderType == KLHEVCEncoder) {
            VTSessionSetProperty(self->EncodingSession, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_HEVC_Main10_AutoLevel);
        }

        // 设置期望帧率
        int fps = 30;
        CFNumberRef  fpsRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &fps);
        VTSessionSetProperty(self->EncodingSession, kVTCompressionPropertyKey_ExpectedFrameRate, fpsRef);

        // 设置关键帧（GOPsize)间隔
        int frameInterval = fps*2;
        CFNumberRef  frameIntervalRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &frameInterval);
        VTSessionSetProperty(self->EncodingSession, kVTCompressionPropertyKey_MaxKeyFrameInterval, frameIntervalRef);

        // 配置I帧持续时间，x秒编一个I帧
        int frameIntervals = 2;
        CFNumberRef  frameIntervalRefs = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &frameIntervals);
        status = VTSessionSetProperty(self->EncodingSession, kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, frameIntervalRefs);
        
        //设置码率，上限，单位是bps
        int bitRate = 60*1024*8;
//        int bitRate = (width * height * 3) * 4;
        CFNumberRef bitRateRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitRate);
        VTSessionSetProperty(self->EncodingSession, kVTCompressionPropertyKey_AverageBitRate, bitRateRef);

        //设置码率，均值，单位是byte
//        int bitRateLimit = (width * height * 3) * 4;
        int bitRateLimit = 60*1024;
        CFNumberRef bitRateLimitRef = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &bitRateLimit);
        VTSessionSetProperty(self->EncodingSession, kVTCompressionPropertyKey_DataRateLimits, bitRateLimitRef);


        // Tell the encoder to start encoding
        VTCompressionSessionPrepareToEncodeFrames(self->EncodingSession);
    });
}

- (void)encode:(CMSampleBufferRef)sampleBuffer {
    CVImageBufferRef imageBuffer = (CVImageBufferRef)CMSampleBufferGetImageBuffer(sampleBuffer);
    //根据传入的 SampleBuffer 获取 PTS 时间戳
    CMTime presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    //系统时间戳纳秒为单位 除以1000 换算成微妙 计算出回调时差
    ptsNewTime = (int64_t)(presentationTimeStamp.value/1000);
    if (ptsOldTime < 0) {
        ptsOldTime = ptsNewTime;
    }
    if (fPTSTime < 0) {
        fPTSTime = ptsNewTime;
    }
//    NSLog(@"ptsNewTime: %lld | ptsOldTime: %lld", ptsNewTime, ptsOldTime);
    //初始化编码 Duration PTS
    CMTime encoderDuration = CMTimeMake(ptsNewTime - ptsOldTime, 1000000);
    CMTime encoderPTS = CMTimeMake(ptsNewTime - fPTSTime, 1000000);
    
    ptsOldTime = ptsNewTime;
    VTEncodeInfoFlags flags;
    
    OSStatus statusCode = VTCompressionSessionEncodeFrame(EncodingSession,
                                                          imageBuffer,
                                                          encoderPTS,
                                                          encoderDuration,
                                                          NULL, NULL, &flags);
    if(statusCode == kVTInvalidSessionErr) {
        //程序切换到后台，会话会失效 需重启会话
        [self initVideoToolBoxWithWidth:w height:h];
        NSLog(@"IOS8VT: Invalid session, reset decoder session");
    }else if (statusCode != noErr) {
        if (encoderType == KLH264Encoder) {
            NSLog(@"H264: VTCompressionSessionEncodeFrame failed with %d", (int)statusCode);
        }else if (encoderType == KLHEVCEncoder) {
            NSLog(@"HEVC: VTCompressionSessionEncodeFrame failed with %d", (int)statusCode);
        }
        [self EndVideoToolBox];
        return;
    }
}

void didCompressH264Encoder(void *outputCallbackRefCon,
                            void *sourceFrameRefCon,
                            OSStatus status,
                            VTEncodeInfoFlags infoFlags,
                            CMSampleBufferRef sampleBuffer) {
    //    NSLog(@"didCompressH264 called with status %d infoFlags %d", (int)status, (int)infoFlags); // 0 1
    if (status != 0) {
        return;
    }

    CMTime pts;
    CMTime dts;
    CMTime duration;
    
    pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    dts = CMSampleBufferGetDecodeTimeStamp(sampleBuffer);
    duration = CMSampleBufferGetDuration(sampleBuffer);

    if (!CMSampleBufferDataIsReady(sampleBuffer)) {
        NSLog(@"didCompressH264 data is not ready ");
        return;
    }
    OSStatus statusCode ;
    KLVideoEncoder *encoder = (__bridge KLVideoEncoder*)(outputCallbackRefCon);
    encoder->kEncoderSize = 0;
    
    // ----- 关键帧获取SPS和PPS ------
    CFDictionaryRef dicRef = (CFDictionaryRef)CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0);
    bool keyframe = !CFDictionaryContainsKey(dicRef, kCMSampleAttachmentKey_NotSync);

//    NSLog(@"didCompressH264 | %2d, %8lld %8lld %8lld %@",keyframe,pts.value,dts.value,duration.value,[NSThread currentThread]);
    
    // 判断当前帧是否为关键帧
    // 获取sps & pps数据
    if (keyframe)
    {
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        
        const uint8_t *sparameterSet = NULL;
        const uint8_t *pparameterSet = NULL;
        size_t sparameterSetSize  = 0;
        size_t sparameterSetCount = 0;
        size_t pparameterSetSize  = 0;
        size_t pparameterSetCount = 0;
        
        statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 0, &sparameterSet, &sparameterSetSize, &sparameterSetCount, 0 );
        statusCode = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(format, 1, &pparameterSet, &pparameterSetSize, &pparameterSetCount, 0 );
        
        if (statusCode == noErr)
        {
            encoder->kEncoderData[encoder->kEncoderSize + 0] = 0x00;
            encoder->kEncoderData[encoder->kEncoderSize + 1] = 0x00;
            encoder->kEncoderData[encoder->kEncoderSize + 2] = 0x00;
            encoder->kEncoderData[encoder->kEncoderSize + 3] = 0x01;
            encoder->kEncoderSize += 4;
            memcpy(encoder->kEncoderData + encoder->kEncoderSize, sparameterSet, sparameterSetSize);
            encoder->kEncoderSize += sparameterSetSize;
            
            encoder->kEncoderData[encoder->kEncoderSize + 0] = 0x00;
            encoder->kEncoderData[encoder->kEncoderSize + 1] = 0x00;
            encoder->kEncoderData[encoder->kEncoderSize + 2] = 0x00;
            encoder->kEncoderData[encoder->kEncoderSize + 3] = 0x01;
            encoder->kEncoderSize += 4;
            memcpy(encoder->kEncoderData + encoder->kEncoderSize, pparameterSet, pparameterSetSize);
            encoder->kEncoderSize += pparameterSetSize;
        }
    }
    // --------- 写入数据 ----------
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length, totalLength;
    char *dataPointer;
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (statusCodeRet == noErr)
    {
        size_t bufferOffset = 0;
        // 返回的nalu数据前四个字节不是0001的startcode，而是大端模式的帧长度length
        // 循环获取nalu数据
        while (bufferOffset < totalLength) {
            uint32_t NALUnitLength = 0;
            // Read the NAL unit length
            memcpy(&NALUnitLength, dataPointer + bufferOffset, 4);
            // 从大端转系统端
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);

            encoder->kEncoderData[encoder->kEncoderSize + 0] = 0x00;
            encoder->kEncoderData[encoder->kEncoderSize + 1] = 0x00;
            encoder->kEncoderData[encoder->kEncoderSize + 2] = 0x00;
            encoder->kEncoderData[encoder->kEncoderSize + 3] = 0x01;
            
            memcpy(encoder->kEncoderData + encoder->kEncoderSize + 4, dataPointer + bufferOffset + 4, NALUnitLength);
#ifdef Log
            NSLog(@"lEncoderData | %6d,%.2X %.2X %.2X %.2X %.2X %.2X\n",NALUnitLength,
                   encoder->kEncoderData[encoder->kEncoderSize + 0],
                   encoder->kEncoderData[encoder->kEncoderSize + 1],
                   encoder->kEncoderData[encoder->kEncoderSize + 2],
                   encoder->kEncoderData[encoder->kEncoderSize + 3],
                   encoder->kEncoderData[encoder->kEncoderSize + 4],
                   encoder->kEncoderData[encoder->kEncoderSize + 5]);
#endif
            encoder->kEncoderSize+= 4 + NALUnitLength;
            bufferOffset += 4 + NALUnitLength;
        }
#ifdef Log
        NSLog(@"kEncoderData | %6d,%.2X %.2X %2.X %.2X %.2X %.2X\n",encoder->kEncoderSize,
               encoder->kEncoderData[0],
               encoder->kEncoderData[1],
               encoder->kEncoderData[2],
               encoder->kEncoderData[3],
               encoder->kEncoderData[4],
               encoder->kEncoderData[5]);
#endif
        if (encoder.returnDataBlock) {
            encoder.returnDataBlock(encoder->kEncoderData, encoder->kEncoderSize, (int64_t)pts.value, (int32_t)duration.value);
        }
    }
}


void didCompressHEVCEncoder(void *outputCallbackRefCon,
                            void *sourceFrameRefCon,
                            OSStatus status,
                            VTEncodeInfoFlags infoFlags,
                            CMSampleBufferRef sampleBuffer) {
    //    NSLog(@"didCompressH264 called with status %d infoFlags %d", (int)status, (int)infoFlags); // 0 1
    if (status != 0) {
        return;
    }

    CMTime pts;
    CMTime dts;
    CMTime duration;
    
    pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    dts = CMSampleBufferGetDecodeTimeStamp(sampleBuffer);
    duration = CMSampleBufferGetDuration(sampleBuffer);
    
    if (!CMSampleBufferDataIsReady(sampleBuffer)) {
        NSLog(@"didCompressHEVC data is not ready ");
        return;
    }
    OSStatus statusCode ;
    KLVideoEncoder *encoder = (__bridge KLVideoEncoder*)(outputCallbackRefCon);
    encoder->kEncoderSize = 0;
    
    // ----- 关键帧获取VPS、SPS和PPS ------
    CFDictionaryRef dicRef = (CFDictionaryRef)CFArrayGetValueAtIndex(CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true), 0);
    bool keyframe = !CFDictionaryContainsKey(dicRef, kCMSampleAttachmentKey_NotSync);

//    NSLog(@"didCompressH264 | %2d, %8lld %8lld %8lld %@",keyframe,pts.value,dts.value,duration.value,[NSThread currentThread]);
    
    // 判断当前帧是否为关键帧
    // 获取vps & sps & pps数据
    if (keyframe)
    {
        CMFormatDescriptionRef format = CMSampleBufferGetFormatDescription(sampleBuffer);
        
        const uint8_t *vparameterSet = NULL;
        const uint8_t *sparameterSet = NULL;
        const uint8_t *pparameterSet = NULL;
        size_t vparameterSetSize  = 0;
        size_t vparameterSetCount = 0;
        size_t sparameterSetSize  = 0;
        size_t sparameterSetCount = 0;
        size_t pparameterSetSize  = 0;
        size_t pparameterSetCount = 0;
        
        statusCode = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format, 0, &vparameterSet, &vparameterSetSize, &vparameterSetCount, 0 );
        statusCode = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format, 1, &sparameterSet, &sparameterSetSize, &sparameterSetCount, 0 );
        statusCode = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(format, 2, &pparameterSet, &pparameterSetSize, &pparameterSetCount, 0 );
        
        if (statusCode == noErr)
        {
            //VPS
            encoder->kEncoderData[encoder->kEncoderSize + 0] = 0x00;
            encoder->kEncoderData[encoder->kEncoderSize + 1] = 0x00;
            encoder->kEncoderData[encoder->kEncoderSize + 2] = 0x00;
            encoder->kEncoderData[encoder->kEncoderSize + 3] = 0x01;
            encoder->kEncoderSize += 4;
            memcpy(encoder->kEncoderData + encoder->kEncoderSize, vparameterSet, vparameterSetSize);
            encoder->kEncoderSize += vparameterSetSize;
            //SPS
            encoder->kEncoderData[encoder->kEncoderSize + 0] = 0x00;
            encoder->kEncoderData[encoder->kEncoderSize + 1] = 0x00;
            encoder->kEncoderData[encoder->kEncoderSize + 2] = 0x00;
            encoder->kEncoderData[encoder->kEncoderSize + 3] = 0x01;
            encoder->kEncoderSize += 4;
            memcpy(encoder->kEncoderData + encoder->kEncoderSize, sparameterSet, sparameterSetSize);
            encoder->kEncoderSize += sparameterSetSize;
            //PPS
            encoder->kEncoderData[encoder->kEncoderSize + 0] = 0x00;
            encoder->kEncoderData[encoder->kEncoderSize + 1] = 0x00;
            encoder->kEncoderData[encoder->kEncoderSize + 2] = 0x00;
            encoder->kEncoderData[encoder->kEncoderSize + 3] = 0x01;
            encoder->kEncoderSize += 4;
            memcpy(encoder->kEncoderData + encoder->kEncoderSize, pparameterSet, pparameterSetSize);
            encoder->kEncoderSize += pparameterSetSize;
        }
    }
    // --------- 写入数据 ----------
    CMBlockBufferRef dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
    size_t length, totalLength;
    char *dataPointer;
    OSStatus statusCodeRet = CMBlockBufferGetDataPointer(dataBuffer, 0, &length, &totalLength, &dataPointer);
    if (statusCodeRet == noErr)
    {
        size_t bufferOffset = 0;
        // 返回的nalu数据前四个字节不是0001的startcode，而是大端模式的帧长度length
        // 循环获取nalu数据
        while (bufferOffset < totalLength) {
            uint32_t NALUnitLength = 0;
            // Read the NAL unit length
            memcpy(&NALUnitLength, dataPointer + bufferOffset, 4);
            // 从大端转系统端
            NALUnitLength = CFSwapInt32BigToHost(NALUnitLength);

            encoder->kEncoderData[encoder->kEncoderSize + 0] = 0x00;
            encoder->kEncoderData[encoder->kEncoderSize + 1] = 0x00;
            encoder->kEncoderData[encoder->kEncoderSize + 2] = 0x00;
            encoder->kEncoderData[encoder->kEncoderSize + 3] = 0x01;
            
            memcpy(encoder->kEncoderData + encoder->kEncoderSize + 4, dataPointer + bufferOffset + 4, NALUnitLength);
#ifdef Log
            NSLog(@"lEncoderData | %6d,%.2X %.2X %.2X %.2X %.2X %.2X\n",NALUnitLength,
                   encoder->kEncoderData[encoder->kEncoderSize + 0],
                   encoder->kEncoderData[encoder->kEncoderSize + 1],
                   encoder->kEncoderData[encoder->kEncoderSize + 2],
                   encoder->kEncoderData[encoder->kEncoderSize + 3],
                   encoder->kEncoderData[encoder->kEncoderSize + 4],
                   encoder->kEncoderData[encoder->kEncoderSize + 5]);
#endif
            encoder->kEncoderSize+= 4 + NALUnitLength;
            bufferOffset += 4 + NALUnitLength;
        }
#ifdef Log
        NSLog(@"kEncoderData | %6d,%.2X %.2X %2.X %.2X %.2X %.2X\n",encoder->kEncoderSize,
               encoder->kEncoderData[0],
               encoder->kEncoderData[1],
               encoder->kEncoderData[2],
               encoder->kEncoderData[3],
               encoder->kEncoderData[4],
               encoder->kEncoderData[5]);
#endif
        if (encoder.returnDataBlock) {
            encoder.returnDataBlock(encoder->kEncoderData, encoder->kEncoderSize, (int64_t)pts.value, (int32_t)duration.value);
        }
    }
}

- (void)kl_startVideoEncodeWithSampleBuffer:(CMSampleBufferRef)sampleBuffer andReturnData:(ReturnEncoderDataBlock)block {
    self.returnDataBlock = block;
    dispatch_sync(kl_EncodeQueue, ^{
        [self encode:sampleBuffer];
    });
}

- (void)kl_stopVideoEncode {
    [self EndVideoToolBox];
    if(kEncoderData){
        delete []kEncoderData;
        kEncoderData = nullptr;
    }
}


- (void)EndVideoToolBox
{
    if (EncodingSession) {
        VTCompressionSessionCompleteFrames(EncodingSession, kCMTimeInvalid);
        VTCompressionSessionInvalidate(EncodingSession);
        CFRelease(EncodingSession);
        EncodingSession = NULL;
    }
}

- (void)dealloc{
    NSLog(@"KLVideoEncoder编码器销毁");
}
@end
