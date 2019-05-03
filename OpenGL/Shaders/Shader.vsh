//
//  Shader.vsh
//  OpenGL
//
//  Created by Igor Shpitalnik on 12/7/12.
//  Copyright (c) 2012 Igor Shpitalnik. All rights reserved.
//

attribute vec4 position;
attribute vec3 normal;
attribute vec2 texcoord0;

varying lowp vec4 colorVarying;
varying mediump vec2 texcoord_varying;

uniform mat4 modelViewProjectionMatrix;
uniform mat3 normalMatrix;

void main()
{
    vec3 eyeNormal = normalize(normalMatrix * normal);
    vec3 lightPosition = vec3(0.5, -1.0, 1.0);
    vec4 diffuseColor = vec4(1.0, 1.0, 1.0, 1.0);
    
    float nDotVP = max(0.0, dot(eyeNormal, normalize(lightPosition)));

    colorVarying = diffuseColor;
    //colorVarying = diffuseColor * nDotVP;
    texcoord_varying = texcoord0;
    
    gl_Position = modelViewProjectionMatrix * position;
}
