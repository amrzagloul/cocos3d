/*
 * CC3GLProgram.m
 *
 * cocos3d 2.0.0
 * Author: Bill Hollings
 * Copyright (c) 2011-2013 The Brenwill Workshop Ltd. All rights reserved.
 * http://www.brenwill.com
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 * 
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 * 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 *
 * http://en.wikipedia.org/wiki/MIT_License
 * 
 * See header file CC3GLProgram.h for full API documentation.
 */

#import "CC3GLProgram.h"
#import "CC3GLProgramContext.h"
#import "CC3GLProgramMatchers.h"
#import "CC3OpenGLESEngine.h"

#pragma mark -
#pragma mark CC3GLProgram

@interface CC3OpenGLESShaders (TemplateMethods)
-(void) setActiveProgram: (CC3GLProgram*) aProgram;
@end

@implementation CC3GLProgram

@synthesize semanticDelegate=_semanticDelegate;
@synthesize maxUniformNameLength=_maxUniformNameLength;
@synthesize maxAttributeNameLength=_maxAttributeNameLength;

-(void) dealloc {
	[_name release];
	[_uniforms release];
	[_attributes release];
	[super dealloc];
}


#pragma mark Variables

-(CC3GLSLUniform*) uniformNamed: (NSString*) name {
	for (CC3GLSLUniform* var in _uniforms) {
		if ( [var.name isEqualToString: name] ) return var;
	}
	return nil;
}

-(CC3GLSLUniform*) uniformAtLocation: (GLint) uniformLocation {
	for (CC3GLSLUniform* var in _uniforms) if (var.location == uniformLocation) return var;
	return nil;
}

-(CC3GLSLUniform*) uniformForSemantic: (GLenum) semantic {
	return [self uniformForSemantic: semantic at: 0];
}

-(CC3GLSLUniform*) uniformForSemantic: (GLenum) semantic at: (GLuint) semanticIndex {
	for (CC3GLSLUniform* var in _uniforms)
		if (var.semantic == semantic && var.semanticIndex == semanticIndex) return var;
	return nil;
}

-(CC3GLSLAttribute*) attributeNamed: (NSString*) name {
	for (CC3GLSLAttribute* var in _attributes) if ( [var.name isEqualToString: name] ) return var;
	return nil;
}

-(CC3GLSLAttribute*) attributeAtLocation: (GLint) attrLocation {
	for (CC3GLSLAttribute* var in _attributes) if (var.location == attrLocation) return var;
	return nil;
}

-(CC3GLSLAttribute*) attributeForSemantic: (GLenum) semantic {
	return [self attributeForSemantic: semantic at: 0];
}

-(CC3GLSLAttribute*) attributeForSemantic: (GLenum) semantic at: (GLuint) semanticIndex {
	for (CC3GLSLAttribute* var in _attributes)
		if (var.semantic == semantic && var.semanticIndex == semanticIndex) return var;
	return nil;
}

#if CC3_OGLES_2

#pragma mark Binding and linking

// Cache this program in the GL state tracker, bind the program to the GL engine,
// and populate the uniforms into the GL engine, allowing the context to override first.
// Raise an assertion error if the uniform cannot be resolved by either context or delegate!
-(void) bindWithVisitor: (CC3NodeDrawingVisitor*) visitor fromContext: (CC3GLProgramContext*) context {
	LogTrace(@"Binding program %@ for %@", self, visitor.currentNode);
	CC3OpenGLESEngine.engine.shaders.activeProgram = self;
	[self use];
	for (CC3GLSLUniform* var in _uniforms)
		if ([context populateUniform: var withVisitor: visitor] ||
			[_semanticDelegate populateUniform: var withVisitor: visitor]) {
			[var updateGLValue];
		} else {
			CC3Assert(NO, @"%@ could not resolve the value of uniform %@ with semantic %@. Consider creating a uniform override on the program context in your material to set the value of the uniform directly.",
					  self, var.name, NSStringFromCC3Semantic(var.semantic));
		}
}

-(BOOL) compileShader: (GLuint*) shader type: (GLenum) type byteArray: (const GLchar*) source {
    GLint status;
	
    if (!source) return NO;

	MarkRezActivityStart();
	
    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &source, NULL);
	LogGLErrorTrace(@"while specifying %@ shader source in %@", NSStringFromGLEnum(type), self);

    glCompileShader(*shader);
	LogGLErrorTrace(@"while compiling %@ shader in %@", NSStringFromGLEnum(type), self);
	
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
	LogGLErrorTrace(@"while retrieving %@ shader status in %@", NSStringFromGLEnum(type), self);
	
	if( !status ) {
		GLsizei length;
		glGetShaderiv(*shader, GL_SHADER_SOURCE_LENGTH, &length);
		LogGLErrorTrace(@"while retrieving %@ shader source length in %@", NSStringFromGLEnum(type), self);

		GLchar src[length];
		glGetShaderSource(*shader, length, NULL, src);
		LogGLErrorTrace(@"while retrieving %@ shader source in %@", NSStringFromGLEnum(type), self);

		LogError(@"Failed to compile %@ shader in %@:\n%s", NSStringFromGLEnum(type), self, src);
		LogError(@"Compilation error log: %@",
				 (type == GL_VERTEX_SHADER ? [self vertexShaderLog] : [self fragmentShaderLog]));
	}
	 CC3Assert(status, @"Error compiling %@ shader in %@", NSStringFromGLEnum(type), self);
	LogRez(@"Compiled %@ %@ in %.4f seconds", self, NSStringFromGLEnum(type), GetRezActivityDuration());
	return (status == GL_TRUE);
}

-(BOOL) link {
	CC3Assert(_semanticDelegate, @"%@ requires the semanticDelegate property be set before linking.", self);
	MarkRezActivityStart();
	BOOL wasLinked = [super link];
	CC3Assert(wasLinked, @"%@ could not be linked. See previously logged error.", self);
	if (wasLinked) {
		LogRez(@"Linked %@ in %.4f seconds", self, GetRezActivityDuration());	// Timing before config vars
		[self configureVariables];
		LogRez(@"Completed %@", self.fullDescription);
	}
	return wasLinked;
}

-(void) configureVariables {
	[self configureUniforms];
	[self configureAttributes];
}

-(void) configureUniforms {
	MarkRezActivityStart();
	[_uniforms removeAllObjects];
	
	GLint varCnt;
	glGetProgramiv(program_, GL_ACTIVE_UNIFORMS, &varCnt);
	LogGLErrorTrace(@"while retrieving number of active uniforms in %@", self);
	glGetProgramiv(program_, GL_ACTIVE_UNIFORM_MAX_LENGTH, &_maxUniformNameLength);
	LogGLErrorTrace(@"while retrieving max uniform name length in %@", self);
	for (GLint varIdx = 0; varIdx < varCnt; varIdx++) {
		CC3GLSLUniform* var = [CC3OpenGLESStateTrackerGLSLUniform variableInProgram: self atIndex: varIdx];
		if ( [_semanticDelegate configureVariable: var] ) [_uniforms addObject: var];
		CC3Assert(var.location >= 0, @"%@ has an invalid location. Make sure the maximum number of program uniforms for this platform has not been exceeded.", var.fullDescription);
	}
	LogRez(@"%@ configured %u uniforms in %.4f seconds", self, varCnt, GetRezActivityDuration());
}

-(void) configureAttributes {
	MarkRezActivityStart();
	[_attributes removeAllObjects];
	
	GLint varCnt;
	glGetProgramiv(program_, GL_ACTIVE_ATTRIBUTES, &varCnt);
	LogGLErrorTrace(@"while retrieving number of active attributes in %@", self);
	glGetProgramiv(program_, GL_ACTIVE_ATTRIBUTE_MAX_LENGTH, &_maxAttributeNameLength);
	LogGLErrorTrace(@"while retrieving max attribute name length in %@", self);
	for (GLint varIdx = 0; varIdx < varCnt; varIdx++) {
		CC3GLSLAttribute* var = [CC3OpenGLESStateTrackerGLSLAttribute variableInProgram: self atIndex: varIdx];
		if ( [_semanticDelegate configureVariable: var] ) [_attributes addObject: var];
		CC3Assert(var.location >= 0, @"%@ has an invalid location. Make sure the maximum number of program attributes for this platform has not been exceeded.", var.fullDescription);
	}
	LogRez(@"%@ configured %u attributes in %.4f seconds", self, varCnt, GetRezActivityDuration());
}

// Overridden to do nothing
-(void) updateUniforms {}

#endif

#if CC3_OGLES_1
-(void) bindWithVisitor: (CC3NodeDrawingVisitor*) visitor fromContext: (CC3GLProgramContext*) context {}
-(BOOL) link { return NO; }
#endif


#pragma mark Allocation and initialization

-(id) initWithName: (NSString*) name fromVertexShaderBytes: (const GLchar*) vshBytes andFragmentShaderBytes: (const GLchar*) fshBytes {
	CC3Assert(name, @"%@ cannot be created without a name", [self class]);
	self.name = name;				// retained - set name before init for logging during compilation
	if ( (self = [super initWithVertexShaderByteArray: vshBytes
							  fragmentShaderByteArray: fshBytes]) ) {
		_uniforms = [CCArray new];		// retained
		_attributes = [CCArray new];	// retained
		_maxUniformNameLength = 0;
		_maxAttributeNameLength = 0;
	}
	return self;
}

-(id) initWithName: (NSString*) name fromVertexShaderFile: (NSString*) vshFilename andFragmentShaderFile: (NSString*) fshFilename {
	LogRez(@"");
	LogRez(@"--------------------------------------------------");
	LogRez(@"Loading GLSL program named %@ from vertex shader file '%@' and fragment shader file '%@'", name, vshFilename, fshFilename);
		   
	const GLchar* vshSrc = [self.class glslSourceFromFile: vshFilename];
	const GLchar* fshSrc = [self.class glslSourceFromFile: fshFilename];
	return [self initWithName: name fromVertexShaderBytes: vshSrc andFragmentShaderBytes: fshSrc];
}

// Overridden superclass implementation to require a name
-(id)initWithVertexShaderByteArray: (const GLchar*)vShaderByteArray fragmentShaderByteArray: (const GLchar*)fShaderByteArray {
	CC3Assert(NO, @"%@ instances require a name. Use initWithName:fromVertexShaderBytes:andFragmentShaderBytes: instead", [self class]);
	return nil;
}

// Overridden superclass implementation to require a name
-(id) initWithVertexShaderFilename: (NSString*) vshFilename fragmentShaderFilename: fshFilename {
	CC3Assert(NO, @"%@ instances require a name. Use initWithName:fromVertexShaderFile:andFragmentShaderFile: instead", [self class]);
	return nil;
}

+(NSString*) programNameFromVertexShaderFile: (NSString*) vshFilename
					   andFragmentShaderFile: (NSString*) fshFilename {
	return [NSString stringWithFormat: @"%@-%@", vshFilename, fshFilename];
}

+(GLchar*) glslSourceFromFile: (NSString*) glslFilename {
	MarkRezActivityStart();
	NSError* err = nil;
	NSString* filePath = CC3EnsureAbsoluteFilePath(glslFilename);
	CC3Assert([[NSFileManager defaultManager] fileExistsAtPath: filePath],
			  @"Could not load GLSL file '%@' because it could not be found", filePath);
	NSString* glslSrcStr = [NSString stringWithContentsOfFile: filePath encoding: NSUTF8StringEncoding error: &err];
	CC3Assert(!err, @"Could not load GLSL file '%@' because %@, (code %i), failure reason %@",
			  glslFilename, err.localizedDescription, err.code, err.localizedFailureReason);
	LogRez(@"Loaded GLSL source from file %@ in %.4f seconds", glslFilename, GetRezActivityDuration());
	return (GLchar*)glslSrcStr.UTF8String;
}

-(NSString*) description { return [NSString stringWithFormat: @"%@ named: %@", [self class], self.name]; }

-(NSString*) fullDescription {
	NSMutableString* desc = [NSMutableString stringWithCapacity: 500];
	[desc appendFormat: @"%@ declaring %i attributes and %i uniforms:", self.description, _attributes.count, _uniforms.count];
	for (CC3GLSLVariable* var in _attributes) [desc appendFormat: @"\n\t %@", var.fullDescription];
	for (CC3GLSLVariable* var in _uniforms) [desc appendFormat: @"\n\t %@", var.fullDescription];
	return desc;
}


#pragma mark Program cache

static NSMutableDictionary* _programsByName = nil;

+(void) addProgram: (CC3GLProgram*) program {
	if ( !program ) return;
	CC3Assert( ![self getProgramNamed: program.name], @"%@ already contains a program named %@", self, program.name);
	if ( !_programsByName ) _programsByName = [NSMutableDictionary new];		// retained
	[_programsByName setObject: program forKey: program.name];
}

+(CC3GLProgram*) getProgramNamed: (NSString*) name { return [_programsByName objectForKey: name]; }

+(void) removeProgram: (CC3GLProgram*) program { [self removeProgramNamed: program.name]; }

+(void) removeProgramNamed: (NSString*) name { [_programsByName removeObjectForKey: name]; }


#pragma mark Program matching

static id<CC3GLProgramMatcher> _programMatcher = nil;

+(id<CC3GLProgramMatcher>) programMatcher {
	if ( !_programMatcher ) _programMatcher = [CC3GLProgramMatcherBase new];	// retained
	return _programMatcher;
}

+(void) setProgramMatcher: (id<CC3GLProgramMatcher>) programMatcher {
	id old = _programMatcher;
	_programMatcher = [programMatcher retain];
	[old release];
}

@end

