# AudioUnitMac
Demo for use AudioUnit of type kAudioUnitSubType_VoiceProcessingIO on Mac 

kAudioUnitSubType_VoiceProcessingIO is Supported on Mac, but it'is a little different。


1.  kAudioOutputUnitProperty_EnableIO  can't be set。 On Mac, input and output is both open，and can't be modified。
2.  The Sample Rate for input and output must be same. 
3.  The method to set buffer size is different。 On Mac use kAudioDevicePropertyBufferFrameSize property, instead of kAudioSessionProperty_PreferredHardwareIOBufferDuration.
4.  When I test , I found  the StreamFromat kAudioFormatFlagIsSignedInteger  could be used for record, but when use in playback, you can't hear anything.
