//
//  VideoShader.metal
//  HalloApp
//
//  Created by Tanveer on 10/28/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

#include <metal_stdlib>
using namespace metal;

constant sampler kBilinearSampler(filter::linear,  coord::pixel, address::clamp_to_edge);

void portraitShader(texture2d<half, access::sample>    leftInput        [[ texture(0) ]],
                    texture2d<half, access::sample>    rightInput       [[ texture(1) ]],
                    texture2d<half, access::write>     outputTexture    [[ texture(2) ]],
                    uint2                              gid              [[thread_position_in_grid]])

{
    half4 output;
    bool useRightTexture = gid.y >= outputTexture.get_height() / 2;
    texture2d<half, access::sample> toSample = useRightTexture ? rightInput : leftInput;

    float2 inputSize = float2((float)toSample.get_width(), (float)toSample.get_height());
    float2 outputSize = float2((float)outputTexture.get_width(), ((float)outputTexture.get_height() * 0.5));

    float aspectWidth = outputSize.x / inputSize.x;
    float aspectHeight = outputSize.y / inputSize.y;
    float f = max(aspectWidth, aspectHeight);

    inputSize.x *= f;
    inputSize.y *= f;

    float xOffset = (outputSize.x - inputSize.x) / 2.0;
    float yOffset = (outputSize.y - inputSize.y) / 2.0;

    float x = ((float)gid.x - xOffset) / f;
    float y;

    if (useRightTexture) {
        y = (((float)gid.y - outputSize.y) - yOffset) / f;
    } else {
        y = ((float)gid.y - yOffset) / f;
    }

    float2 coord = float2(x, y);
    output = toSample.sample(kBilinearSampler, coord + 0.5);

    outputTexture.write(output, gid);
}

void landscapeShader(texture2d<half, access::sample>    leftInput        [[ texture(0) ]],
                     texture2d<half, access::sample>    rightInput       [[ texture(1) ]],
                     texture2d<half, access::write>     outputTexture    [[ texture(2) ]],
                     uint2                              gid              [[thread_position_in_grid]])

{
    half4 output;
    bool useLeftTexture = gid.x >= outputTexture.get_width() / 2;
    texture2d<half, access::sample> toSample = useLeftTexture ? leftInput : rightInput;

    float2 inputSize = float2((float)toSample.get_width(), (float)toSample.get_height());
    float2 outputSize = float2(((float)outputTexture.get_width() * 0.5), ((float)outputTexture.get_height()));

    float aspectWidth = outputSize.x / inputSize.x;
    float aspectHeight = outputSize.y / inputSize.y;
    float f = max(aspectWidth, aspectHeight);

    inputSize.x *= f;
    inputSize.y *= f;

    float xOffset = (outputSize.x - inputSize.x) / 2.0;
    float yOffset = (outputSize.y - outputSize.y) / 2.0;

    float x;
    float y = ((float)gid.y - yOffset) / f;

    if (useLeftTexture) {
        x = (((float)gid.x - outputSize.x) - xOffset) / f;
    } else {
        x = ((float)gid.x - xOffset) / f;
    }

    float2 coord = float2(x, y) + 0.5;
    output = toSample.sample(kBilinearSampler, coord);

    outputTexture.write(output, gid);
}

kernel void videoShader(texture2d<half, access::sample>    leftInput        [[ texture(0) ]],
                        texture2d<half, access::sample>    rightInput       [[ texture(1) ]],
                        texture2d<half, access::write>     outputTexture    [[ texture(2) ]],
                        const device    bool&              layout           [[ buffer(0) ]],
                        uint2                              gid              [[thread_position_in_grid]])

{
    if (layout) {
        portraitShader(leftInput, rightInput, outputTexture, gid);
    } else {
        landscapeShader(leftInput, rightInput, outputTexture, gid);
    }
}




