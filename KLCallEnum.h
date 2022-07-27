//
//  KLCallEnum.h
//  KLRTC
//
//  Created by ColdMountain on 2020/6/15.
//  Copyright © 2020 ColdMountain. All rights reserved.
//

#ifndef KLCallEnum_h
#define KLCallEnum_h

typedef enum {
    KLRTCTypeVoice    = 0,    // 语音模式
    KLRTCTypeVideo    = 1,    // 视频模式
} KLRTCType;

typedef enum {
    KLCaptureSessionPreset352x288    = 0,     // 352x288
    KLCaptureSessionPreset640x480    = 1,     // 640x480
    KLCaptureSessionPreset1280x720   = 2,     // 720x1280
    KLCaptureSessionPreset1920x1080  = 3,     // 1920x1080
    KLCaptureSessionPreset3840x2160  = 4      // 3840x2160
} KLCaptureSessionPreset;

typedef enum {
    KLAudioSampleRate_Defalut = 8000,
    KLAudioSampleRate_22050Hz = 22050,
    KLAudioSampleRate_24000Hz = 24000,
    KLAudioSampleRate_32000Hz = 32000,
    KLAudioSampleRate_44100Hz = 44100,
} KLAudioSampleRate;

typedef enum {
    KLCaptureDevicePositionFront = 0,   //前置摄像头
    KLCaptureDevicePositionBack         //后置摄像头
} KLCaptureDevicePosition;

typedef enum{
    KLCaptureOutputYUV = 0,         //返回YUV数据
    KLCaptureOutputSampleBuffer     //返回CMSampleBufferRef
} KLCaptureOutput;

typedef enum{
    KLH264Encoder = 0,    //H.264
    KLHEVCEncoder         //H.265
} KLEncoderType;
#endif /* KLCallEnum_h */
