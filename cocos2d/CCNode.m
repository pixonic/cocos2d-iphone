/* cocos2d for iPhone
 *
 * http://www.cocos2d-iphone.org
 *
 * Copyright (C) 2008,2009,2010 Ricardo Quesada
 * Copyright (C) 2009 Valentin Milea
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the 'cocos2d for iPhone' license.
 *
 * You will find a copy of this license within the cocos2d for iPhone
 * distribution inside the "LICENSE" file.
 *
 */


#import "ccConfig.h"
#import "CCNode.h"
#import "CCCamera.h"
#import "CCGrid.h"
#import "CCScheduler.h"
#import "ccMacros.h"
#import "CCDirector.h"
#import "CCActionManager.h"
#import "Support/CGPointExtension.h"
#import "Support/ccArray.h"
#import "Support/TransformUtils.h"


#if CC_COCOSNODE_RENDER_SUBPIXEL
#define RENDER_IN_SUBPIXEL
#else
#define RENDER_IN_SUBPIXEL (int)
#endif

@interface CCNode (Private)
// lazy allocs
-(void) childrenAlloc;
// helper that reorder a child
-(void) insertChild:(CCNode*)child z:(int)z;
// used internally to alter the zOrder variable. DON'T call this method manually
-(void) _setZOrder:(int) z;
-(void) detachChild:(CCNode *)child cleanup:(BOOL)doCleanup;
@end

@implementation CCNode

@synthesize visible;
@synthesize parent;
@synthesize grid=grid_;
@synthesize zOrder;
@synthesize tag;
@synthesize vertexZ = vertexZ_;
@synthesize isRunning;

#pragma mark CCNode - Transform related properties

@synthesize rotation=rotation_, scaleX=scaleX_, scaleY=scaleY_, position=position_;
@synthesize anchorPointInPixels=anchorPointInPixels_, relativeAnchorPoint=relativeAnchorPoint_;
@synthesize userData;

// getters synthesized, setters explicit
-(void) setRotation: (float)newRotation
{
	rotation_ = newRotation;
	isTransformDirty_ = isInverseDirty_ = YES;
}

-(void) setScaleX: (float)newScaleX
{
	scaleX_ = newScaleX;
	isTransformDirty_ = isInverseDirty_ = YES;
}

-(void) setScaleY: (float)newScaleY
{
	scaleY_ = newScaleY;
	isTransformDirty_ = isInverseDirty_ = YES;
}

-(void) setPosition: (CGPoint)newPosition
{
	position_ = newPosition;
	isTransformDirty_ = isInverseDirty_ = YES;
}

-(void) setRelativeAnchorPoint: (BOOL)newValue
{
	relativeAnchorPoint_ = newValue;
	isTransformDirty_ = isInverseDirty_ = YES;
}

-(void) setAnchorPoint:(CGPoint)point
{
	if( ! CGPointEqualToPoint(point, anchorPoint_) ) {
		anchorPoint_ = point;
		anchorPointInPixels_ = ccp( contentSize_.width * anchorPoint_.x, contentSize_.height * anchorPoint_.y );
		isTransformDirty_ = isInverseDirty_ = YES;
	}
}
-(CGPoint) anchorPoint
{
	return anchorPoint_;
}

-(void) setContentSize:(CGSize)size
{
	if( ! CGSizeEqualToSize(size, contentSize_) ) {
		contentSize_ = size;
		anchorPointInPixels_ = ccp( contentSize_.width * anchorPoint_.x, contentSize_.height * anchorPoint_.y );
		isTransformDirty_ = isInverseDirty_ = YES;
	}
}
-(CGSize) contentSize
{
	return contentSize_;
}

- (CGRect) boundingBox
{
	CGRect rect = CGRectMake(0, 0, contentSize_.width, contentSize_.height);
	return CGRectApplyAffineTransform(rect, [self nodeToParentTransform]);
}

-(float) scale
{
	NSAssert( scaleX_ == scaleY_, @"CCNode#scale. ScaleX != ScaleY. Don't know which one to return");
	return scaleX_;
}

-(void) setScale:(float) s
{
	scaleX_ = scaleY_ = s;
	isTransformDirty_ = isInverseDirty_ = YES;
}

#pragma mark CCNode - Init & cleanup

+(id) node
{
	return [[[self alloc] init] autorelease];
}

-(id) init
{
	if ((self=[super init]) ) {

		isRunning = NO;
	
		rotation_ = 0.0f;
		scaleX_ = scaleY_ = 1.0f;
		position_ = CGPointZero;
		anchorPointInPixels_ = anchorPoint_ = CGPointZero;
		contentSize_ = CGSizeZero;
		

		// "whole screen" objects. like Scenes and Layers, should set relativeAnchorPoint to NO
		relativeAnchorPoint_ = YES; 
		
		isTransformDirty_ = isInverseDirty_ = YES;
		
		
		vertexZ_ = 0;

		grid_ = nil;
		
		visible = YES;
		perFrameUpdates = NO;

		tag = kCCNodeTagInvalid;
		
		zOrder = 0;

		// lazy alloc
		camera_ = nil;

		// children (lazy allocs)
		children = nil;
		
		// userData is always inited as nil
		userData = nil;
	}
	
	return self;
}

- (void)cleanup
{
	// actions
	[self stopAllActions];
	
	// Selectors
	[self stopAllTimers];
	
	// Per Frame Updates
	[self cancelPerFrameUpdates];
	
	[children makeObjectsPerformSelector:@selector(cleanup)];
}

- (NSString*) description
{
	return [NSString stringWithFormat:@"<%@ = %08X | Tag = %i>", [self class], self, tag];
}

- (void) dealloc
{
	CCLOG( @"cocos2d: deallocing %@", self);
	
	// attributes
	[camera_ release];

	[grid_ release];
	
	// children
	
	for (CCNode *child in children) {
		child.parent = nil;
	}
	
	[children release];
	
		
	[super dealloc];
}

#pragma mark CCNode Composition

-(void) childrenAlloc
{
	children = [[NSMutableArray arrayWithCapacity:4] retain];
}

// camera: lazy alloc
-(CCCamera*) camera
{
	if( ! camera_ ) {
		camera_ = [[CCCamera alloc] init];
		
		// by default, center camera at the Sprite's anchor point
//		[camera_ setCenterX:anchorPointInPixels_.x centerY:anchorPointInPixels_.y centerZ:0];
//		[camera_ setEyeX:anchorPointInPixels_.x eyeY:anchorPointInPixels_.y eyeZ:1];

//		[camera_ setCenterX:0 centerY:0 centerZ:0];
//		[camera_ setEyeX:0 eyeY:0 eyeZ:1];

	}

	return camera_;
}

-(CCNode*) getChildByTag:(int) aTag
{
	NSAssert( aTag != kCCNodeTagInvalid, @"Invalid tag");
	
	for( CCNode *node in children ) {
		if( node.tag == aTag )
			return node;
	}
	// not found
	return nil;
}

- (NSArray *)children
{
	return (NSArray *) children;
}

/* "add" logic MUST only be on this selector
 * If a class want's to extend the 'addChild' behaviour it only needs
 * to override this selector
 */
-(id) addChild: (CCNode*) child z:(int)z tag:(int) aTag
{	
	NSAssert( child != nil, @"Argument must be non-nil");
	NSAssert( child.parent == nil, @"child already added. It can't be added again");
	
	if( ! children )
		[self childrenAlloc];
	
	[self insertChild:child z:z];
	
	child.tag = aTag;
	
	[child setParent: self];
	
	if( isRunning )
		[child onEnter];
	return self;
}

-(id) addChild: (CCNode*) child z:(int)z
{
	NSAssert( child != nil, @"Argument must be non-nil");
	return [self addChild:child z:z tag:child.tag];
}

-(id) addChild: (CCNode*) child
{
	NSAssert( child != nil, @"Argument must be non-nil");
	return [self addChild:child z:child.zOrder tag:child.tag];
}

/* "remove" logic MUST only be on this method
 * If a class want's to extend the 'removeChild' behavior it only needs
 * to override this method
 */
-(void) removeChild: (CCNode*)child cleanup:(BOOL)cleanup
{
	// explicit nil handling
	if (child == nil)
		return;
	
	if ( [children containsObject:child] )
		[self detachChild:child cleanup:cleanup];
}

-(void) removeChildByTag:(int)aTag cleanup:(BOOL)cleanup
{
	NSAssert( aTag != kCCNodeTagInvalid, @"Invalid tag");

	CCNode *child = [self getChildByTag:aTag];
	
	if (child == nil)
		CCLOG(@"cocos2d: removeChildByTag: child not found!");
	else
		[self removeChild:child cleanup:cleanup];
}

-(void) removeAllChildrenWithCleanup:(BOOL)cleanup
{
	// not using detachChild improves speed here
	for (CCNode *c in children)
	{
		// IMPORTANT:
		//  -1st do onExit
		//  -2nd cleanup
		if (isRunning)
			[c onExit];

		if (cleanup)
			[c cleanup];

		// set parent nil at the end (issue #476)
		[c setParent:nil];
	}

	[children removeAllObjects];
}

-(void) detachChild:(CCNode *)child cleanup:(BOOL)doCleanup
{
	// IMPORTANT:
	//  -1st do onExit
	//  -2nd cleanup
	if (isRunning)
		[child onExit];

	// If you don't do cleanup, the child's actions will not get removed and the
	// its scheduledSelectors dict will not get released!
	if (doCleanup)
		[child cleanup];

	// set parent nil at the end (issue #476)
	[child setParent:nil];

	[children removeObject:child];
}

// used internally to alter the zOrder variable. DON'T call this method manually
-(void) _setZOrder:(int) z
{
	zOrder = z;
}

// helper used by reorderChild & add
-(void) insertChild:(CCNode*) child z:(int)z
{
	int index=0;
	BOOL added = NO;
	for( CCNode *a in children ) {
		if ( a.zOrder > z ) {
			added = YES;
			[ children insertObject:child atIndex:index];
			break;
		}
		index++;
	}
	
	if( ! added )
		[children addObject:child];
	
	[child _setZOrder:z];
}

-(void) reorderChild:(CCNode*) child z:(int)z
{
	NSAssert( child != nil, @"Child must be non-nil");
	
	[child retain];
	[children removeObject:child];
	
	[self insertChild:child z:z];
	
	[child release];
}

#pragma mark CCNode Draw

-(void) draw
{
	// override me
	// Only use this function to draw your staff.
	// DON'T draw your stuff outside this method
}

-(void) visit
{
	if (!visible)
		return;
	
	glPushMatrix();
	
	if ( grid_ && grid_.active) {
		[grid_ beforeDraw];
		[self transformAncestors];
	}
	
	[self transform];
	
	for (CCNode * child in children) {
		if ( child.zOrder < 0 )
			[child visit];
		else
			break;
	}
	
	[self draw];
	
	for (CCNode * child in children) {		
		if ( child.zOrder >= 0 )
			[child visit];
	}
	
	if ( grid_ && grid_.active)
		[grid_ afterDraw:self];
	
	glPopMatrix();
}


#pragma mark CCNode - Per Frame Updates

-(void) perFrameUpdate:(ccTime) dt {
	// override me
}

-(void) scheduleForPerFrameUpdates {
	[self scheduleForPerFrameUpdatesWithPriority:0];
}

-(void) scheduleForPerFrameUpdatesWithPriority:(NSInteger) aPriority {
	if(perFrameUpdates) {
		[self cancelPerFrameUpdates];
	}
	[[CCScheduler sharedScheduler] requestPerFrameUpdatesForTarget:self priority:aPriority];
	perFrameUpdates = YES;
}

-(void) cancelPerFrameUpdates {
	if(perFrameUpdates) {
		[[CCScheduler sharedScheduler] cancelPerFrameUpdatesForTarget:self];
		perFrameUpdates = NO;
	}
}



#pragma mark CCNode - Transformations

-(void) transformAncestors
{
	if( parent ) {
		[parent transformAncestors];
		[parent transform];
	}
}

-(void) transform
{
	
	// transformations
	
#if CC_NODE_TRANSFORM_USING_AFFINE_MATRIX
	// BEGIN alternative -- using cached transform
	//
	static GLfloat m[16];
	CGAffineTransform t = [self nodeToParentTransform];
	CGAffineToGL(&t, m);
	glMultMatrixf(m);
	if( vertexZ_ )
		glTranslatef(0, 0, vertexZ_);

	// XXX: Expensive calls. Camera should be integrated into the cached affine matrix
	if ( camera_ && !(grid_ && grid_.active) ) {
		BOOL translate = (anchorPointInPixels_.x != 0.0f || anchorPointInPixels_.y != 0.0f);
		
		if( translate )
			glTranslatef(RENDER_IN_SUBPIXEL(anchorPointInPixels_.x), RENDER_IN_SUBPIXEL(anchorPointInPixels_.y), 0);

		[camera_ locate];
		
		if( translate )
			glTranslatef(RENDER_IN_SUBPIXEL(-anchorPointInPixels_.x), RENDER_IN_SUBPIXEL(-anchorPointInPixels_.y), 0);
	}


	// END alternative

#else
	// BEGIN original implementation
	// 
	// translate
	if ( relativeAnchorPoint_ && (anchorPointInPixels_.x != 0 || anchorPointInPixels_.y != 0 ) )
		glTranslatef( RENDER_IN_SUBPIXEL(-anchorPointInPixels_.x), RENDER_IN_SUBPIXEL(-anchorPointInPixels_.y), 0);

	if (anchorPointInPixels_.x != 0 || anchorPointInPixels_.y != 0)
		glTranslatef( RENDER_IN_SUBPIXEL(position_.x + anchorPointInPixels_.x), RENDER_IN_SUBPIXEL(position_.y + anchorPointInPixels_.y), vertexZ_);
	else if ( position_.x !=0 || position_.y !=0 || vertexZ_ != 0)
		glTranslatef( RENDER_IN_SUBPIXEL(position_.x), RENDER_IN_SUBPIXEL(position_.y), vertexZ_ );
	
	// rotate
	if (rotation_ != 0.0f )
		glRotatef( -rotation_, 0.0f, 0.0f, 1.0f );
	
	// scale
	if (scaleX_ != 1.0f || scaleY_ != 1.0f)
		glScalef( scaleX_, scaleY_, 1.0f );
	
	if ( camera_ && !(grid_ && grid_.active) )
		[camera_ locate];
	
	// restore and re-position point
	if (anchorPointInPixels_.x != 0.0f || anchorPointInPixels_.y != 0.0f)
		glTranslatef(RENDER_IN_SUBPIXEL(-anchorPointInPixels_.x), RENDER_IN_SUBPIXEL(-anchorPointInPixels_.y), 0);

	//
	// END original implementation
#endif

}

#pragma mark CCNode SceneManagement

-(void) onEnter
{
	for( id child in children )
		[child onEnter];
	
	[self activateTimers];

	isRunning = YES;
}

-(void) onEnterTransitionDidFinish
{
	for( id child in children )
		[child onEnterTransitionDidFinish];
}

-(void) onExit
{
	[self deactivateTimers];

	isRunning = NO;	
	
	for( id child in children )
		[child onExit];
}

#pragma mark CCNode Actions

-(CCAction*) runAction:(CCAction*) action
{
	NSAssert( action != nil, @"Argument must be non-nil");
	
	[[CCActionManager sharedManager] addAction:action target:self paused:!isRunning];
	return action;
}

-(void) stopAllActions
{
	[[CCActionManager sharedManager] removeAllActionsFromTarget:self];
}

-(void) stopAction: (CCAction*) action
{
	[[CCActionManager sharedManager] removeAction:action];
}

-(void) stopActionByTag:(int)aTag
{
	NSAssert( aTag != kActionTagInvalid, @"Invalid tag");
	[[CCActionManager sharedManager] removeActionByTag:aTag target:self];
}

-(CCAction*) getActionByTag:(int) aTag
{
	NSAssert( aTag != kActionTagInvalid, @"Invalid tag");

	return [[CCActionManager sharedManager] getActionByTag:aTag target:self];
}

-(int) numberOfRunningActions
{
	return [[CCActionManager sharedManager] numberOfRunningActionsInTarget:self];
}


#pragma mark CCNode Timers 


-(void) schedule: (SEL) selector repeat:(int)times
{
	[self schedule:selector interval:0 repeat:times];
}

-(void) schedule: (SEL) selector
{
	[self schedule:selector interval:0 repeat:CCTIMER_REPEAT_FOREVER];
}


-(void) schedule: (SEL) selector interval:(ccTime)interval {
	[self schedule:selector interval:interval repeat:CCTIMER_REPEAT_FOREVER];
}

-(void) schedule: (SEL) selector interval:(ccTime)interval repeat:(int)times
{
	NSAssert( times >= CCTIMER_REPEAT_FOREVER, @"Repeat argument invalid");
	NSAssert( selector != nil, @"Argument must be non-nil");
	NSAssert( interval >=0, @"Arguemnt must be positive");
	
	CCTimer *timer = [CCTimer timerWithTarget:self selector:selector interval:interval repeat:times paused:!isRunning];
	[[CCScheduler sharedScheduler] addTimer:timer];
	
}

-(void) unschedule: (SEL) selector
{
	// explicit nil handling
	if (selector == nil)
		return;

	[[CCScheduler sharedScheduler] unscheduleSelector:selector target:self];

}

- (void) activateTimers
{
	[self activateTimersWithChildren:NO];
}

-(void) activateTimersWithChildren:(bool) affectChildren;
{
	[[CCScheduler sharedScheduler] resumeAllTimersForTarget:self];
	[[CCActionManager sharedManager] resumeAllActionsForTarget:self];
	if(children) {
		if(affectChildren) {
			for(CCNode* n in children) {
				[n activateTimersWithChildren:YES];
			}
		}
	}
}

- (void) deactivateTimers
{
	[self deactivateTimersWithChildren:NO];
}

-(void) deactivateTimersWithChildren:(bool) affectChildren
{
	[[CCScheduler sharedScheduler] pauseAllTimersForTarget:self];
	[[CCActionManager sharedManager] pauseAllActionsForTarget:self];
	if(children) {
		if(affectChildren) {
			for(CCNode* n in children) {
				[n deactivateTimersWithChildren:YES];
			}
		}
	}
}

-(void) stopAllTimers {
	[[CCScheduler sharedScheduler] removeAllTimersFromTarget:self];
}

-(void) scaleAllTimers:(float) scale
{
	[self scaleAllTimers:scale withChildren:NO];
}

-(void) scaleAllTimers:(float) scale withChildren:(bool) affectChildren;
{
	[[CCScheduler sharedScheduler] scaleAllTimersForTarget:self scaleFactor:scale];
	[[CCActionManager sharedManager] timeScaleAllActionsForTarget:self scale:scale];
	if(affectChildren) {
		for(CCNode* n in children) {
			[n scaleAllTimers:scale withChildren:YES];
		}
	}
}


#pragma mark CCNode Transform

- (CGAffineTransform)nodeToParentTransform
{
	if ( isTransformDirty_ ) {
		
		transform_ = CGAffineTransformIdentity;
		
		if ( !relativeAnchorPoint_ )
			transform_ = CGAffineTransformTranslate(transform_, anchorPointInPixels_.x, anchorPointInPixels_.y);
		
		transform_ = CGAffineTransformTranslate(transform_, position_.x, position_.y);
		transform_ = CGAffineTransformRotate(transform_, -CC_DEGREES_TO_RADIANS(rotation_));
		transform_ = CGAffineTransformScale(transform_, scaleX_, scaleY_);
		
		transform_ = CGAffineTransformTranslate(transform_, -anchorPointInPixels_.x, -anchorPointInPixels_.y);
		
		isTransformDirty_ = NO;
	}
	
	return transform_;
}

- (CGAffineTransform)parentToNodeTransform
{
	if ( isInverseDirty_ ) {
		inverse_ = CGAffineTransformInvert([self nodeToParentTransform]);
		isInverseDirty_ = NO;
	}
	
	return inverse_;
}

- (CGAffineTransform)nodeToWorldTransform
{
	CGAffineTransform t = [self nodeToParentTransform];
	
	for (CCNode *p = parent; p != nil; p = p.parent)
		t = CGAffineTransformConcat(t, [p nodeToParentTransform]);
	
	return t;
}

- (CGAffineTransform)worldToNodeTransform
{
	return CGAffineTransformInvert([self nodeToWorldTransform]);
}

- (CGPoint)convertToNodeSpace:(CGPoint)worldPoint
{
	return CGPointApplyAffineTransform(worldPoint, [self worldToNodeTransform]);
}

- (CGPoint)convertToWorldSpace:(CGPoint)nodePoint
{
	return CGPointApplyAffineTransform(nodePoint, [self nodeToWorldTransform]);
}

- (CGPoint)convertToNodeSpaceAR:(CGPoint)worldPoint
{
	CGPoint nodePoint = [self convertToNodeSpace:worldPoint];
	return ccpSub(nodePoint, anchorPointInPixels_);
}

- (CGPoint)convertToWorldSpaceAR:(CGPoint)nodePoint
{
	nodePoint = ccpAdd(nodePoint, anchorPointInPixels_);
	return [self convertToWorldSpace:nodePoint];
}

- (CGPoint)convertToWindowSpace:(CGPoint)nodePoint
{
    CGPoint worldPoint = [self convertToWorldSpace:nodePoint];
	return [[CCDirector sharedDirector] convertToUI:worldPoint];
}

// convenience methods which take a UITouch instead of CGPoint

- (CGPoint)convertTouchToNodeSpace:(UITouch *)touch
{
	CGPoint point = [touch locationInView: [touch view]];
	point = [[CCDirector sharedDirector] convertToGL: point];
	return [self convertToNodeSpace:point];
}

- (CGPoint)convertTouchToNodeSpaceAR:(UITouch *)touch
{
	CGPoint point = [touch locationInView: [touch view]];
	point = [[CCDirector sharedDirector] convertToGL: point];
	return [self convertToNodeSpaceAR:point];
}

@end
