//
//  ViewController.m
//  AudioUnitMac
//
//  Created by pinky on 2018/6/7.
//  Copyright © 2018年 youme. All rights reserved.
//

#import "ViewController.h"
#import "AudioRecordAndPlay.h"

@interface ViewController()
{
    AudioRecordAndPlay* stream;
}
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    stream = [[AudioRecordAndPlay alloc] init];
    [stream Start];
    // Do any additional setup after loading the view.
}


- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}


@end
