/*
    SyphonServerQCPlugIn.m
	SyphonQC
	
    Copyright 2010 bangnoise (Tom Butterworth) & vade (Anton Marini).
    All rights reserved.

    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.

    * Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in the
    documentation and/or other materials provided with the distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
    ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
    WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
    DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS BE LIABLE FOR ANY
    DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
    (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
    ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
    (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
    SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/* It's highly recommended to use CGL macros instead of changing the current context for plug-ins that perform OpenGL rendering */
#import <OpenGL/CGLMacro.h>

#import "SyphonServerQCPlugIn.h"

#define	kQCPlugIn_Name						@"Syphon Server"
#define	kQCPlugIn_Description				@"Share frames between applications using Syphon.\nTo use the OpenGL scene as the source, set this patch to be the last (top) layer rendered."
#define kSyphonServerQC_UntitledServerName	@"Untitled"

@implementation SyphonServerQCPlugIn

@dynamic inputServerID;
@dynamic inputImage;
@dynamic inputSource;

+ (NSDictionary*) attributes
{
    NSArray *examples = [NSArray arrayWithObjects:@"Examples/Syphon Server.qtz", nil];
	return [NSDictionary dictionaryWithObjectsAndKeys:kQCPlugIn_Name, QCPlugInAttributeNameKey,
            kQCPlugIn_Description, QCPlugInAttributeDescriptionKey,
            examples, @"examples", nil]; // Don't use QCPlugInAttributeExamplesKey as it isn't present on 10.6
}

+ (NSDictionary*) attributesForPropertyPortWithKey:(NSString*)key
{
	if([key isEqualToString:@"inputImage"])
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Image", QCPortAttributeNameKey, nil];
	
	if([key isEqualToString:@"inputServerID"])
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Name", QCPortAttributeNameKey, kSyphonServerQC_UntitledServerName, QCPortAttributeDefaultValueKey, nil];

	if([key isEqualToString:@"inputSource"])
		return [NSDictionary dictionaryWithObjectsAndKeys:@"Source", QCPortAttributeNameKey, 
				[NSArray arrayWithObjects:@"Image", @"OpenGL Scene", nil], QCPortAttributeMenuItemsKey,
				[NSNumber numberWithInt:0], QCPortAttributeDefaultValueKey,
				[NSNumber numberWithInt:0], QCPortAttributeMinimumValueKey,
				[NSNumber numberWithInt:1], QCPortAttributeMaximumValueKey, nil];	
	
	return nil;
}

+ (NSArray*) sortedPropertyPortKeys
{
	return [NSArray arrayWithObjects:@"inputServerID",
									@"inputSource",
									@"inputImage",
									nil];
}


+ (QCPlugInExecutionMode) executionMode
{
	return kQCPlugInExecutionModeConsumer;
}

+ (QCPlugInTimeMode) timeMode
{
	return kQCPlugInTimeModeNone;
}

- (id) init
{
    self = [super init];
	if(self)
	{
		name = [kSyphonServerQC_UntitledServerName retain];
	}
	return self;
}


- (void) finalize
{	
	[syServer stop];
	[super finalize];
}

- (void) dealloc
{
	[syServer release];
	[name release];
	[super dealloc];
}

@end

@implementation SyphonServerQCPlugIn (Execution)

- (BOOL) startExecution:(id<QCPlugInContext>)context
{	
	return YES;
}
/*
- (void) enableExecution:(id<QCPlugInContext>)context
{

}
*/
- (BOOL) execute:(id<QCPlugInContext>)context atTime:(NSTimeInterval)time withArguments:(NSDictionary*)arguments
{	
	if([self didValueForInputKeyChange:@"inputServerID"])
	{
		NSString *newName = self.inputServerID;
		// Enforce a name.
		if ([newName length] == 0)
		{
			newName = kSyphonServerQC_UntitledServerName;
		}
		[newName retain];
		[name release];
		name = newName;
		[syServer setName:newName];
	}
	BOOL sourceJustChanged = NO;
	if ([self didValueForInputKeyChange:@"inputSource"])
	{
		sourceJustChanged = YES;
		source = self.inputSource;
	}
	// handle new input frames
	if(source == 0 && (sourceJustChanged || [self didValueForInputKeyChange:@"inputImage"]))
	{
		id <QCPlugInInputImageSource> input = self.inputImage;
		if(input)
		{
			if([input lockTextureRepresentationWithColorSpace:[context colorSpace] forBounds:[input imageBounds]])
			{
				if (syServer == nil)
				{
					syServer = [[SyphonServer alloc] initWithName:name context:[context CGLContextObj] options:nil];
				}
				[syServer publishFrameTexture:[input textureName]
								textureTarget:[input textureTarget]
								  imageRegion:(NSRect){{0.0, 0.0}, {[input texturePixelsWide], [input texturePixelsHigh]}}
							textureDimensions:(NSSize){[input texturePixelsWide], [input texturePixelsHigh]}
									  flipped:[input textureFlipped]];				
				[self.inputImage unlockTextureRepresentation];
			} else {
				[context logMessage:@"Syphon Server can't obtain texture from input."];
			}
		}
        // Keep the last frame valid, and server alive.
//		else
//		{
//			// For now we stop the server, but we could output black instead and keep the server running.
//			[syServer stop];
//			[syServer release];
//			syServer = nil;			
//		}
	}
	
	if(source == 1)
	{
		CGLContextObj cgl_ctx = [context CGLContextObj];
		GLint dims[4];
	
		glPushAttrib(GL_TEXTURE_BIT | GL_ENABLE_BIT);
		glGetIntegerv(GL_VIEWPORT, dims);

        GLuint worldTexture;
        (GL_TEXTURE_RECTANGLE_EXT);
        glGenTextures(1, &worldTexture);
        glBindTexture(GL_TEXTURE_RECTANGLE_EXT, worldTexture);
        glTexImage2D(GL_TEXTURE_RECTANGLE_EXT, 0, GL_RGBA8, dims[2], dims[3], 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
        glCopyTexSubImage2D(GL_TEXTURE_RECTANGLE_EXT, 0, 0, 0, dims[0], dims[1], dims[2], dims[3]);

        if (syServer == nil)
        {
            syServer = [[SyphonServer alloc] initWithName:name
                                                  context:[context CGLContextObj]
                                                  options:nil];
        }
        [syServer publishFrameTexture:worldTexture
                        textureTarget:GL_TEXTURE_RECTANGLE_EXT
                          imageRegion:(NSRect){{0.0, 0.0}, {dims[2], dims[3]}}
                    textureDimensions:(NSSize){dims[2], dims[3]}
                              flipped:NO];

        glDeleteTextures(1, &worldTexture);

        glPopAttrib();
	}
	
	return YES;
}

- (void) disableExecution:(id<QCPlugInContext>)context
{
}
- (void) stopExecution:(id<QCPlugInContext>)context
{
	[syServer stop];
	[syServer release];
	syServer = nil;	
}

@end
