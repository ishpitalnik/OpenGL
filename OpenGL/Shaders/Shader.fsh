//
//  Shader.fsh
//  OpenGL
//
//  Created by Igor Shpitalnik on 12/7/12.
//  Copyright (c) 2012 Igor Shpitalnik. All rights reserved.
//

varying lowp vec4 colorVarying;
varying mediump vec2 texcoord_varying;

uniform sampler2D texture;

void main()
{
    gl_FragColor = texture2D(texture, texcoord_varying) * colorVarying;
}
