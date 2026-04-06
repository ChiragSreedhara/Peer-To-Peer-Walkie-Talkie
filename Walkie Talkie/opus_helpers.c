//
//  opus_helpers.c
//  Walkie Talkie
//
//  Created by Nicole Li on 4/5/26.
//


#include "opus_helpers.h"

int opus_encoder_set_bitrate(OpusEncoder *encoder, int bitrate) {
    return opus_encoder_ctl(encoder, OPUS_SET_BITRATE(bitrate));
}