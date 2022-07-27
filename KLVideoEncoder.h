//
//  KLH265Encoder.h
//  H265Demo
//
//  Created by Cold Mountain on 2022/7/27.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "KLCallEnum.h"

typedef void (^ReturnEncoderDataBlock)(uint8_t *buffer,int32_t size, int64_t pts, int32_t duration);

@interface KLVideoEncoder : NSObject

@property (nonatomic, copy) ReturnEncoderDataBlock returnDataBlock;
- (instancetype)initEncodeWithType:(KLEncoderType)type width:(int)width height:(int)height;
/**
 视频编码
 @param sampleBuffer 视频帧数据
 @param block  返回NSData
 */
-(void)kl_startVideoEncodeWithSampleBuffer:(CMSampleBufferRef)sampleBuffer andReturnData:(ReturnEncoderDataBlock)block;
-(void)kl_stopVideoEncode;

@end

