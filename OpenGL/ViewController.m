//
//  ViewController.m
//  OpenGL
//
//  Created by Igor Shpitalnik on 12/7/12.
//  Copyright (c) 2012 Igor Shpitalnik. All rights reserved.
//

#import "ViewController.h"

#define BUFFER_OFFSET(i) ((char *)NULL + (i))

// Uniform index.
enum
{
    UNIFORM_MODELVIEWPROJECTION_MATRIX,
    UNIFORM_NORMAL_MATRIX,
    UNIFORM_TEXTURE_SAMPLER,
    NUM_UNIFORMS
};
GLint uniforms[NUM_UNIFORMS];

static NSString *borderType = @"borderType";

// Attribute index.

@interface ViewController () {
    GLuint _program;
    
    GLKMatrix4 _modelViewProjectionMatrix[OBJECTS_COUNT];
    GLKMatrix3 _normalMatrix[OBJECTS_COUNT];
    
    GLuint _vertexArray[OBJECTS_COUNT];
    GLuint vbo[OBJECTS_COUNT];
    GLuint vinx[OBJECTS_COUNT];
   
    GLKVector3 _cameraRotate;

    GLfloat _cameraMoveZ;
    
    CGPoint _beginTouch;
    
    float _lastScale;
    
    GLKTextureInfo * _texture[OBJECTS_COUNT];
    
    
}
@property (strong, nonatomic) EAGLContext *context;
@property (strong, nonatomic) CMMotionManager *motionManager;

- (void)setupGL;
- (void)tearDownGL;

- (BOOL)loadShaders;
- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type file:(NSString *)file;
- (BOOL)linkProgram:(GLuint)prog;
- (BOOL)validateProgram:(GLuint)prog;
- (void)loadTextures;
- (void)logError:(NSError *) error;
@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];

    if (!self.context) {
        NSLog(@"Failed to create ES context");
    }
    
    GLKView *view = (GLKView *)self.view;
    view.context = self.context;
    view.drawableDepthFormat = GLKViewDrawableDepthFormat24;
    
	UIPinchGestureRecognizer *pinchRecognizer = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(scale:)];
	[pinchRecognizer setDelegate:self];
	[self.view addGestureRecognizer:pinchRecognizer];
    
    _cameraMoveZ = -4.0;
    
    _lastScale = 1;
    
    [self setupGL];
    
    [self initCoreMotion];
}

- (void) viewDidAppear:(BOOL)animated {
    if (self.motionManager.isDeviceMotionAvailable) {
        [self.motionManager startDeviceMotionUpdates];
        [self.motionManager startAccelerometerUpdates];
        //[self.motionManager startGyroUpdates];
    }
}

- (void) viewDidDisappear:(BOOL)animated {
    if (self.motionManager.isDeviceMotionAvailable) {
        [self.motionManager stopDeviceMotionUpdates];
        [self.motionManager stopAccelerometerUpdates];
    }
}

- (void) viewWillDisappear:(BOOL)animated {
    if (self.motionManager.isDeviceMotionAvailable) {
        [self.motionManager stopDeviceMotionUpdates];
        [self.motionManager stopAccelerometerUpdates];
    }
    
}

- (void)dealloc
{    
    [self tearDownGL];
    
    if ([EAGLContext currentContext] == self.context) {
        [EAGLContext setCurrentContext:nil];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];

    if ([self isViewLoaded] && ([[self view] window] == nil)) {
        self.view = nil;
        
        [self tearDownGL];
        
        if ([EAGLContext currentContext] == self.context) {
            [EAGLContext setCurrentContext:nil];
        }
        self.context = nil;
    }
}

- (void)setupGL
{
    [EAGLContext setCurrentContext:self.context];
    
    [self loadShaders];
    [self loadTextures];
    
    glEnable(GL_DEPTH_TEST);
    glEnable(GL_TEXTURE_2D);
    glEnable(GL_BLEND);
    //glBlendFunc(GL_ONE, GL_SRC_COLOR);
    
    for (int i = 0; i < OBJECTS_COUNT; i++) {
        glGenVertexArraysOES(1, &_vertexArray[i]);
        glBindVertexArrayOES(_vertexArray[i]);
    
        glGenBuffers(1, &vbo[i]);
        glBindBuffer(GL_ARRAY_BUFFER, vbo[i]);
        glBufferData(GL_ARRAY_BUFFER, sizeof (struct vertex_struct) * vertex_count[i], &vertices[vertex_offset_table[i]], GL_STATIC_DRAW);
    
        glGenBuffers(1, &vinx[i]);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, vinx[i]);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof (indexes[0]) * faces_count[i] * 3, &indexes[indices_offset_table[i]], GL_STATIC_DRAW);
        
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    
        glEnableVertexAttribArray(GLKVertexAttribPosition);
        glVertexAttribPointer(GLKVertexAttribPosition, 3, GL_FLOAT, GL_FALSE, sizeof (struct vertex_struct), BUFFER_OFFSET(0));
    
        glEnableVertexAttribArray(GLKVertexAttribNormal);
        glVertexAttribPointer(GLKVertexAttribNormal, 3, GL_FLOAT, GL_FALSE, sizeof (struct vertex_struct), BUFFER_OFFSET(3 * sizeof (float)));
        
        glEnableVertexAttribArray(GLKVertexAttribTexCoord0);
        glVertexAttribPointer(GLKVertexAttribTexCoord0, 2, GL_FLOAT, GL_FALSE, sizeof (struct vertex_struct), BUFFER_OFFSET(6 * sizeof (float)));

        glBindVertexArrayOES(0);
        
    }
}

- (void)tearDownGL
{
    [EAGLContext setCurrentContext:self.context];

    for (int i = 0; i < OBJECTS_COUNT; i++) {
        glDeleteBuffers(1, &vbo[i]);
        glDeleteVertexArraysOES(1, &vbo[i]);
    }
   
    
    if (_program) {
        glDeleteProgram(_program);
        _program = 0;
    }
}

#pragma mark - GLKView and GLKViewController delegate methods

- (void)update {

    CMRotationMatrix rm = self.motionManager.deviceMotion.attitude.rotationMatrix;
    
    float aspect = fabsf(self.view.bounds.size.width / self.view.bounds.size.height);
    
    GLKMatrix4 projectionMatrix = GLKMatrix4MakePerspective(GLKMathDegreesToRadians(65.0f), aspect, 0.001f, 100.0f);

    GLKMatrix4 rotationMatrix = GLKMatrix4Make(rm.m11, rm.m21, rm.m31, 0,
                                                 rm.m12, rm.m22, rm.m32, 0,
                                                 rm.m13, rm.m23, rm.m33, 0,
                                                 0, 0, 0, 1);

    GLKMatrix4 baseModelViewMatrix = GLKMatrix4MakeTranslation(0.0f, 0.0f, _cameraMoveZ);
    baseModelViewMatrix = GLKMatrix4Rotate(baseModelViewMatrix, _cameraRotate.x * 0.01, 0.0f, 1.0f, 0.0f);
    baseModelViewMatrix = GLKMatrix4Rotate(baseModelViewMatrix, _cameraRotate.y * 0.01, 1.0f, 0.0f, 0.0f);

    GLKVector3 newGravity = GLKMatrix4MultiplyVector3(GLKMatrix4Transpose(baseModelViewMatrix),
                                                      GLKVector3Make(
                                                                     self.motionManager.deviceMotion.gravity.x,
                                                                     self.motionManager.deviceMotion.gravity.y,
                                                                     self.motionManager.deviceMotion.gravity.z
                                                                     )
                                                      );
    
//    GLKVector3 bodyPos = GLKVector3Make(body.pos.x, body.pos.y, 0);

    if (self.motionManager.isDeviceMotionAvailable) {
        baseModelViewMatrix = GLKMatrix4Multiply(baseModelViewMatrix, rotationMatrix);
    }
    
    // Compute the model view matrix for the object rendered with ES2
    GLKMatrix4 modelViewMatrix = GLKMatrix4MakeTranslation(0.0f, 0.0f, -2);
    modelViewMatrix = GLKMatrix4Multiply(baseModelViewMatrix, modelViewMatrix);
    
    _normalMatrix[0] = GLKMatrix4GetMatrix3(modelViewMatrix);
    _modelViewProjectionMatrix[0] = GLKMatrix4Multiply(projectionMatrix, modelViewMatrix);
    
    // Compute the model view matrix for the object rendered with ES2
    modelViewMatrix = GLKMatrix4MakeTranslation(0.0f, 0.0f, 4);
    modelViewMatrix = GLKMatrix4Multiply(baseModelViewMatrix, modelViewMatrix);
    
    _normalMatrix[1] = GLKMatrix4GetMatrix3(modelViewMatrix);
    _modelViewProjectionMatrix[1] = GLKMatrix4Multiply(projectionMatrix, modelViewMatrix);
}

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{
    glClearColor(0.65f, 0.65f, 0.65f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    
    for (int i = 0; i < OBJECTS_COUNT; i++) {
        glBindVertexArrayOES(_vertexArray[i]);
        
    
        glUseProgram(_program);
        glBindTexture(GL_TEXTURE_2D, _texture[i].name);
    
        glUniformMatrix4fv(uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX], 1, 0, _modelViewProjectionMatrix[i].m);
        glUniformMatrix3fv(uniforms[UNIFORM_NORMAL_MATRIX], 1, 0, _normalMatrix[i].m);
        glUniform1f(uniforms[UNIFORM_TEXTURE_SAMPLER], 0);
    
        glDrawElements(GL_TRIANGLES, faces_count[i] * 3, INX_TYPE, BUFFER_OFFSET(0));
    }
}

#pragma mark -  OpenGL ES 2 shader compilation

- (BOOL)loadShaders
{
    GLuint vertShader, fragShader;
    NSString *vertShaderPathname, *fragShaderPathname;
    
    // Create shader program.
    _program = glCreateProgram();
    
    // Create and compile vertex shader.
    vertShaderPathname = [[NSBundle mainBundle] pathForResource:@"Shader" ofType:@"vsh"];
    if (![self compileShader:&vertShader type:GL_VERTEX_SHADER file:vertShaderPathname]) {
        NSLog(@"Failed to compile vertex shader");
        return NO;
    }
    
    // Create and compile fragment shader.
    fragShaderPathname = [[NSBundle mainBundle] pathForResource:@"Shader" ofType:@"fsh"];
    if (![self compileShader:&fragShader type:GL_FRAGMENT_SHADER file:fragShaderPathname]) {
        NSLog(@"Failed to compile fragment shader");
        return NO;
    }
    
    // Attach vertex shader to program.
    glAttachShader(_program, vertShader);
    
    // Attach fragment shader to program.
    glAttachShader(_program, fragShader);
    
    // Bind attribute locations.
    // This needs to be done prior to linking.
    glBindAttribLocation(_program, GLKVertexAttribPosition, "position");
    glBindAttribLocation(_program, GLKVertexAttribNormal, "normal");
    glBindAttribLocation(_program, GLKVertexAttribTexCoord0, "texcoord0");
    
    // Link program.
    if (![self linkProgram:_program]) {
        NSLog(@"Failed to link program: %d", _program);
        
        if (vertShader) {
            glDeleteShader(vertShader);
            vertShader = 0;
        }
        if (fragShader) {
            glDeleteShader(fragShader);
            fragShader = 0;
        }
        if (_program) {
            glDeleteProgram(_program);
            _program = 0;
        }
        
        return NO;
    }
    
    // Get uniform locations.
    uniforms[UNIFORM_MODELVIEWPROJECTION_MATRIX] = glGetUniformLocation(_program, "modelViewProjectionMatrix");
    uniforms[UNIFORM_NORMAL_MATRIX] = glGetUniformLocation(_program, "normalMatrix");
    uniforms[UNIFORM_TEXTURE_SAMPLER] = glGetUniformLocation(_program, "texture");
    
    // Release vertex and fragment shaders.
    if (vertShader) {
        glDetachShader(_program, vertShader);
        glDeleteShader(vertShader);
    }
    if (fragShader) {
        glDetachShader(_program, fragShader);
        glDeleteShader(fragShader);
    }
    
    return YES;
}

- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type file:(NSString *)file
{
    GLint status;
    const GLchar *source;
    
    source = (GLchar *)[[NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil] UTF8String];
    if (!source) {
        NSLog(@"Failed to load vertex shader");
        return NO;
    }
    
    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &source, NULL);
    glCompileShader(*shader);
    
#if defined(DEBUG)
    GLint logLength;
    glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetShaderInfoLog(*shader, logLength, &logLength, log);
        NSLog(@"Shader compile log:\n%s", log);
        free(log);
    }
#endif
    
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
    if (status == 0) {
        glDeleteShader(*shader);
        return NO;
    }
    
    return YES;
}

- (BOOL)linkProgram:(GLuint)prog
{
    GLint status;
    glLinkProgram(prog);
    
#if defined(DEBUG)
    GLint logLength;
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program link log:\n%s", log);
        free(log);
    }
#endif
    
    glGetProgramiv(prog, GL_LINK_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

- (BOOL)validateProgram:(GLuint)prog
{
    GLint logLength, status;
    
    glValidateProgram(prog);
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        NSLog(@"Program validate log:\n%s", log);
        free(log);
    }
    
    glGetProgramiv(prog, GL_VALIDATE_STATUS, &status);
    if (status == 0) {
        return NO;
    }
    
    return YES;
}

#pragma mark - touches deligate methods 

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [[event allTouches] anyObject];
    CGPoint location = [touch locationInView:touch.view];
    _beginTouch = location;
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [[event allTouches] anyObject];
    CGPoint location = [touch locationInView:touch.view];
    _cameraRotate.x += (location.x - _beginTouch.x);
    _cameraRotate.y += (location.y - _beginTouch.y);
    _beginTouch = location;
}

#pragma mark - pinch 

-(void)scale:(id)sender {

    if([(UIPinchGestureRecognizer*)sender state] == UIGestureRecognizerStateEnded) {
        _lastScale = 1.0;
		return;
	}
    
    CGFloat scale = 1.0 - (_lastScale - [(UIPinchGestureRecognizer*)sender scale]);
    _lastScale = [(UIPinchGestureRecognizer*)sender scale];

    //NSLog(@"Old scale %f", scale);

    //scale = 1 - (1 - scale) * 0.05;

    //NSLog(@"New scale %f", scale);
    _cameraMoveZ /= scale;
    //NSLog(@"New _moveCameraZ %f", _cameraMoveZ);
}

#pragma mark - TextureLoad

- (void)loadTextures {
    NSError *error = nil;
    UIImage *image1 = [UIImage imageNamed:@"03.jpg"];
    UIImage *image2 = [UIImage imageNamed:@"04.jpg"];

    _texture[0] = [GLKTextureLoader textureWithCGImage:image1.CGImage options:nil error:&error];
    if (error != nil) {
        [self logError:error];
    }
    
    _texture[1] = [GLKTextureLoader textureWithCGImage:image2.CGImage options:nil error:&error];
    if (error != nil) {
        [self logError:error];
    }
}

- (void)logError:(NSError *) error {
    if (error) {
        NSString * domain = [error domain];
        NSLog(@"Error loading texture: %@.  Domain: %@", [error localizedDescription],domain);
        NSDictionary * userInfo = [error userInfo];
        if (domain == GLKTextureLoaderErrorDomain) {
            if (nil != [userInfo objectForKey:GLKTextureLoaderErrorKey])
                NSLog(@"%@", [userInfo objectForKey:GLKTextureLoaderErrorKey]);
            if (nil != [userInfo objectForKey:GLKTextureLoaderGLErrorKey])
                NSLog(@"%@", [userInfo objectForKey:GLKTextureLoaderGLErrorKey]);
        }
    }
}

#pragma mark - init motion 

- (void) initCoreMotion {
    self.motionManager = [[CMMotionManager alloc] init];
    if(!self.motionManager.accelerometerAvailable) {
        NSLog(@"Accelerometer not available");
    }
    self.motionManager.deviceMotionUpdateInterval   = 1/60; //60 Hz
    self.motionManager.gyroUpdateInterval           = 1/60;
    self.motionManager.accelerometerUpdateInterval  = 1/60;
}

@end
