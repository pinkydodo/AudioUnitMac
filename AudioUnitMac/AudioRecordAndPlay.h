////////////////////////////////////////////////
///麦克风采集声音，延迟一定时间之后用扬声器播放
///
/////////////////////////////////////////////////
#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaToolbox/MediaToolbox.h>

//#define QUEUE_BUFFER_SIZE 4   //队列缓冲个数
//#define AUDIO_BUFFER_SIZE 372 //数据区大小
#define MAX_BUFFER_SIZE 409600 //
//#define AUDIO_FRAME_SIZE 372


@interface AudioRecordAndPlay : NSObject

-(void)Start;
-(void)Stop;

@end 
