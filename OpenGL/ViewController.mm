//
//  ViewController.m
//  OpenGL
//
//  Created by Igor Shpitalnik on 12/7/12.
//  Copyright (c) 2012 Igor Shpitalnik. All rights reserved.
//

#import "ViewController.h"
#include "btBulletDynamicsCommon.h"
#import "GLDebugDrawer.h"
#import <OpenGLES/ES2/glext.h>

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
    
    GLKMatrix4 _viewMatrix;
    GLKMatrix4 _modelViewProjectionMatrix[OBJECTS_COUNT];
    GLKMatrix3 _normalMatrix[OBJECTS_COUNT];
    
    GLuint _vertexArray[OBJECTS_COUNT];
    GLuint vbo[OBJECTS_COUNT];
    GLuint vinx[OBJECTS_COUNT];
   
    GLKMatrix4 _rotationMatrix;

    GLfloat _cameraMoveZ;

    float _lastScale;
    
    GLKTextureInfo*  _texture[OBJECTS_COUNT];
    
    GLDebugDrawer               debugDrawer;
    btDiscreteDynamicsWorld*    dynamicsWorld;
    btRigidBody*                fallRigidBody;
    GLKBaseEffect*              _bulletDebugEffect;
}

@property (strong, nonatomic) EAGLContext *context;
@property (strong, nonatomic) CMMotionManager *motionManager;
@property (strong, nonatomic) GLKBaseEffect *bulletDebugEffect;

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
    
    [self initBullet];
    
    _rotationMatrix = GLKMatrix4Identity;
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
    
    delete dynamicsWorld;
    
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
    
    self.bulletDebugEffect = [[GLKBaseEffect alloc] init];
    self.bulletDebugEffect.light0.enabled = GL_TRUE;
    self.bulletDebugEffect.light0.diffuseColor = GLKVector4Make(1.0f, 0.4f, 0.4f, 1.0f);
    self.bulletDebugEffect.useConstantColor = GL_TRUE;
    self.bulletDebugEffect.constantColor = GLKVector4Make(0, 1, 0, 1);
    
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
        glDeleteBuffers(1, &vinx[i]);
        glDeleteVertexArraysOES(1, &vbo[i]);
    }
   
    
    if (_program) {
        glDeleteProgram(_program);
        _program = 0;
    }
    
    self.bulletDebugEffect = nil;
}

#pragma mark - GLKView and GLKViewController delegate methods

- (void)update {
    
    CMRotationMatrix rm = self.motionManager.deviceMotion.attitude.rotationMatrix;
    
    float aspect = fabsf(self.view.bounds.size.width / self.view.bounds.size.height);
    
    GLKMatrix4 projectionMatrix = GLKMatrix4MakePerspective(GLKMathDegreesToRadians(65.0f), aspect, 0.001f, 100.0f);
    self.bulletDebugEffect.transform.projectionMatrix = projectionMatrix;
    
    GLKMatrix4 deviceMatrix = GLKMatrix4Make(rm.m11, rm.m12, rm.m13, 0,
                                       rm.m21, rm.m22, rm.m23, 0,
                                       rm.m31, rm.m32, rm.m33, 0,
                                       0,      0,      0,      1);
    
    GLKVector3 acceleration = GLKVector3Make(self.motionManager.deviceMotion.userAcceleration.x,
                                             self.motionManager.deviceMotion.userAcceleration.y,
                                             self.motionManager.deviceMotion.userAcceleration.z);
                                             

    GLKMatrix4 baseModelViewMatrix = GLKMatrix4MakeTranslation(0.0f, 0.0f, _cameraMoveZ);

    GLKVector3 gravityVector = GLKVector3Make(self.motionManager.deviceMotion.gravity.x,
                                        self.motionManager.deviceMotion.gravity.y,
                                        self.motionManager.deviceMotion.gravity.z);
    
    if (self.motionManager.isDeviceMotionAvailable) {
        baseModelViewMatrix = GLKMatrix4Multiply(baseModelViewMatrix, GLKMatrix4Transpose(deviceMatrix));
    }
    baseModelViewMatrix = GLKMatrix4Multiply(baseModelViewMatrix, _rotationMatrix);
    
    
    self.bulletDebugEffect.transform.modelviewMatrix = baseModelViewMatrix;


    gravityVector = GLKMatrix4MultiplyVector3(deviceMatrix, gravityVector);
    gravityVector = GLKMatrix4MultiplyVector3(GLKMatrix4Transpose(_rotationMatrix), gravityVector);
    
    acceleration = GLKMatrix4MultiplyVector3(GLKMatrix4Transpose(_rotationMatrix), acceleration);
    
    static float gravity = 9.8;
    dynamicsWorld -> setGravity(btVector3(gravityVector.x * gravity,
                                          gravityVector.y * gravity,
                                          gravityVector.z * gravity));

    dynamicsWorld->stepSimulation(1/60.f,1);
    fallRigidBody->applyCentralForce(btVector3(acceleration.x * gravity,
                                               acceleration.y * gravity,
                                               acceleration.z * gravity));

    btTransform trans;
    fallRigidBody->getMotionState()->getWorldTransform(trans);
    btScalar btBodyMatrix[16];
    trans.getOpenGLMatrix(btBodyMatrix);
    
    // Compute the model view matrix for the object rendered with ES2
    GLKMatrix4 modelViewMatrix = GLKMatrix4MakeTranslation(0.0f, 0.0f, -5);
    modelViewMatrix = GLKMatrix4Multiply(baseModelViewMatrix, modelViewMatrix);
    
    _normalMatrix[0] = GLKMatrix4GetMatrix3(modelViewMatrix);
    _modelViewProjectionMatrix[0] = GLKMatrix4Multiply(projectionMatrix, modelViewMatrix);
    
    // Compute the model view matrix for the object rendered with ES2
    modelViewMatrix = GLKMatrix4Make(btBodyMatrix[0], btBodyMatrix[1], btBodyMatrix[2], btBodyMatrix[3],
                                     btBodyMatrix[4], btBodyMatrix[5], btBodyMatrix[6], btBodyMatrix[7],
                                     btBodyMatrix[8], btBodyMatrix[9], btBodyMatrix[10],btBodyMatrix[11],
                                     btBodyMatrix[12],btBodyMatrix[13],btBodyMatrix[14], btBodyMatrix[15]);
    modelViewMatrix = GLKMatrix4Multiply(baseModelViewMatrix, modelViewMatrix);
    
    _normalMatrix[1] = GLKMatrix4GetMatrix3(modelViewMatrix);
    _modelViewProjectionMatrix[1] = GLKMatrix4Multiply(projectionMatrix, modelViewMatrix);
}

- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect
{

    glClearColor(0.65f, 0.65f, 0.65f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    dynamicsWorld -> debugDrawWorld();
    glUseProgram(_program);

    for (int i = 0; i < OBJECTS_COUNT; i++) {
        glBindVertexArrayOES(_vertexArray[i]);
        
        glBindTexture(GL_TEXTURE_2D, _texture[i].name);
        //glActiveTexture(_texture[i].name);
    
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


- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [[event allTouches] anyObject];
    CGPoint location = [touch locationInView: touch.view];
    CGPoint lastLocation = [touch previousLocationInView: touch.view];
    CGPoint diff = CGPointMake(lastLocation.x - location.x, lastLocation.y - location.y);

    
    float rotX = -1 * GLKMathDegreesToRadians(diff.y);
    float rotY = -1 * GLKMathDegreesToRadians(diff.x);
    
    CMRotationMatrix rm = self.motionManager.deviceMotion.attitude.rotationMatrix;
    GLKMatrix4 deviceMatrix = GLKMatrix4Make(rm.m11, rm.m12, rm.m13, 0,
                                             rm.m21, rm.m22, rm.m23, 0,
                                             rm.m31, rm.m32, rm.m33, 0,
                                             0,      0,      0,      1);
    bool isInverible;
    if (rotX != 0) {
        GLKVector3 xAxis = GLKMatrix4MultiplyVector3(deviceMatrix, GLKVector3Make(1, 0, 0));
        xAxis = GLKMatrix4MultiplyVector3(GLKMatrix4Invert(_rotationMatrix, &isInverible), xAxis);
        _rotationMatrix = GLKMatrix4Rotate(_rotationMatrix, rotX, xAxis.x, xAxis.y, xAxis.z);
    }
    for (int i = 0; i < 16; i++) {
        if ([[NSString stringWithFormat:@"%f", _rotationMatrix.m[i]] isEqualToString:@"nan"]) {
            NSLog(@"ppc");
        }
    }
    
    if (rotY != 0) {
        GLKVector3 yAxis = GLKMatrix4MultiplyVector3(deviceMatrix, GLKVector3Make(0, 1, 0));
        yAxis = GLKMatrix4MultiplyVector3(GLKMatrix4Invert(_rotationMatrix, &isInverible), yAxis);
        _rotationMatrix = GLKMatrix4Rotate(_rotationMatrix, rotY, yAxis.x, yAxis.y, yAxis.z);
    }

    for (int i = 0; i < 16; i++) {
        if ([[NSString stringWithFormat:@"%f", _rotationMatrix.m[i]] isEqualToString:@"nan"]) {
            NSLog(@"ppc");
        }
    }
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

- (void) initBullet {
    btBroadphaseInterface* broadphase = new btDbvtBroadphase();
    btDefaultCollisionConfiguration* collisionConfiguration = new btDefaultCollisionConfiguration();
    btCollisionDispatcher* dispatcher = new btCollisionDispatcher(collisionConfiguration);
    btSequentialImpulseConstraintSolver* solver = new btSequentialImpulseConstraintSolver();
    dynamicsWorld = new btDiscreteDynamicsWorld(dispatcher,broadphase,solver,collisionConfiguration);
    
    btCollisionShape *lowYShape = new btBoxShape(btVector3(15, 0.1, 15));
    btDefaultMotionState *lowYMotionState = new btDefaultMotionState(btTransform(btQuaternion(0, 0, 0, 1), btVector3(0, -5, 0)));
    btRigidBody::btRigidBodyConstructionInfo lowYRigidBodyCI(0,lowYMotionState, lowYShape, btVector3(0, 0, 0));
    lowYRigidBodyCI.m_restitution = 0.0;
    btRigidBody* lowYRigidBody = new btRigidBody(lowYRigidBodyCI);
    dynamicsWorld->addRigidBody(lowYRigidBody);
    
    btCollisionShape *cielingShape = new btBoxShape(btVector3(15,0.1,15));
    btDefaultMotionState *cielingMotionState = new btDefaultMotionState(btTransform(btQuaternion(0, 0, 0, 1),btVector3(0, 5, 0)));
    btRigidBody::btRigidBodyConstructionInfo cielingRigidBodyCI(0,cielingMotionState,cielingShape,btVector3(0,0,0));
    cielingRigidBodyCI.m_restitution = 0.3;
    btRigidBody* cielingRigidBody = new btRigidBody(cielingRigidBodyCI);
    dynamicsWorld->addRigidBody(cielingRigidBody);
    
    btCollisionShape *leftWallShape = new btBoxShape(btVector3(0.1,15,15));
    btDefaultMotionState *leftWallMotionState = new btDefaultMotionState(btTransform(btQuaternion(0, 0, 0, 1),btVector3(-5, 0, 0)));
    btRigidBody::btRigidBodyConstructionInfo leftWallRigidBodyCI(0,leftWallMotionState,leftWallShape,btVector3(0,0,0));
    leftWallRigidBodyCI.m_restitution = 0.8;
    btRigidBody* leftWallRigidBody = new btRigidBody(leftWallRigidBodyCI);
    dynamicsWorld->addRigidBody(leftWallRigidBody);
    
    btCollisionShape *rightWallShape = new btBoxShape(btVector3(0.1,15,15));
    btDefaultMotionState *rightWallMotionState = new btDefaultMotionState(btTransform(btQuaternion(0, 0, 0, 1),btVector3(5, 0, 0)));
    btRigidBody::btRigidBodyConstructionInfo rightWallRigidBodyCI(0,rightWallMotionState,rightWallShape,btVector3(0,0,0));
    rightWallRigidBodyCI.m_restitution = 0.8;
    btRigidBody* rightWallRigidBody = new btRigidBody(rightWallRigidBodyCI);
    dynamicsWorld->addRigidBody(rightWallRigidBody);
    
    btCollisionShape *lowZShape = new btBoxShape(btVector3(15, 15, 0.1));
    btDefaultMotionState *lowZMotionState = new btDefaultMotionState(btTransform(btQuaternion(0, 0, 0, 1), btVector3(0, 0, -5)));
    btRigidBody::btRigidBodyConstructionInfo lowZRigidBodyCI(0, lowZMotionState, lowZShape, btVector3(0, 0, 0));
    lowZRigidBodyCI.m_restitution = 0.8;
    btRigidBody* lowZRigidBody = new btRigidBody(lowZRigidBodyCI);
    dynamicsWorld->addRigidBody(lowZRigidBody);
    
    btCollisionShape *topZShape = new btBoxShape(btVector3(15, 15, 0.1));
    btDefaultMotionState *topZMotionState = new btDefaultMotionState(btTransform(btQuaternion(0, 0, 0, 1), btVector3(0, 0, 5)));
    btRigidBody::btRigidBodyConstructionInfo topZRigidBodyCI(0, topZMotionState, topZShape, btVector3(0, 0, 0));
    topZRigidBodyCI.m_restitution = 0.8;
    btRigidBody* topZRigidBody = new btRigidBody(topZRigidBodyCI);
    dynamicsWorld->addRigidBody(topZRigidBody);


    // ---------------
    // Shape 1
    btCollisionShape *fallShape = new btBoxShape(btVector3(1.0,1.0,1.0));//btSphereShape(1);
    btDefaultMotionState *fallMotionState = new btDefaultMotionState(btTransform(btQuaternion(0,0,0,1), btVector3(-2.5,0,0)));
    btScalar mass = 1;
    btVector3 fallInertia(0.5,0.5,0.5);
    fallShape->calculateLocalInertia(mass, fallInertia);
    btRigidBody::btRigidBodyConstructionInfo fallRigidBodyCI(mass,fallMotionState,fallShape,fallInertia);
    fallRigidBodyCI.m_restitution = 0.3;
    fallRigidBody = new btRigidBody(fallRigidBodyCI);
    fallRigidBody->setDamping(0.3,0.8);
    fallRigidBody->setLinearFactor(btVector3(1,1,1));
    fallRigidBody->setAngularFactor(btVector3(0,0,1));
    fallRigidBody->setActivationState(DISABLE_DEACTIVATION);
    dynamicsWorld->addRigidBody(fallRigidBody);
    // ---------------
    // Shape 2
//    btCollisionShape *fallShape2 = new btBoxShape(btVector3(0.5,0.5,0.5));//btSphereShape(1);
//    btDefaultMotionState *fall2MotionState = new btDefaultMotionState(btTransform(btQuaternion(0,0,0,1), btVector3(2.5,0,0)));
//    fallShape2->calculateLocalInertia(mass, fallInertia);
//    btRigidBody::btRigidBodyConstructionInfo fallRigidBodyCI2(mass,fall2MotionState,fallShape2,fallInertia);
//    fallRigidBodyCI2.m_restitution = 0.3;
//    fallRigidBody2 = new btRigidBody(fallRigidBodyCI2);
//    fallRigidBody2->setDamping(0.3,0.8);
//    fallRigidBody2->setLinearFactor(btVector3(1,1,0));
//    fallRigidBody2->setAngularFactor(btVector3(0,0,1));
//    dynamicsWorld->addRigidBody(fallRigidBody2);
    
    debugDrawer.setDebugMode(btIDebugDraw::DBG_DrawWireframe  |  btIDebugDraw::DBG_DrawAabb);
    debugDrawer.setShader(self.bulletDebugEffect);
    
    dynamicsWorld -> setDebugDrawer(&debugDrawer);
}

@end
