//
//  opus_helpers.h
//  Walkie Talkie
//
//  Created by Nicole Li on 4/5/26.
//


#ifndef opus_helpers_h
#define opus_helpers_h

#include <opus.h>

int opus_encoder_set_bitrate(OpusEncoder *encoder, int bitrate);

#endif