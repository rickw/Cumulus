//
//  CMChunkedDownloadRequest.m
//  Cumulus
//
//  Created by John Clayton on 5/29/13.
//  Copyright (c) 2013 Fivesquare Software, LLC. All rights reserved.
//

#import "CMChunkedDownloadRequest.h"

#import "CMRequest+Protected.h"
#import "CMDownloadRequest.h"
#import "Cumulus.h"


@interface CMDownloadChunk : NSObject
@property (nonatomic) NSUInteger sequence;
@property (nonatomic) long long size;
@property (nonatomic, strong) CMRequest *request;
@property (nonatomic, strong) CMResponse *response;
@property (nonatomic, strong) NSError *error;
@property (nonatomic, strong) NSURL *file;
@end
@implementation CMDownloadChunk
@end


@interface CMChunkedDownloadRequest () {
	dispatch_semaphore_t _chunksSemaphore;
}
@property BOOL sentInitialProgress;
@property (nonatomic) long long expectedAggregatedContentLength;
@property long long receivedAggregatedContentLength;
@property long long assembledAggregatedContentLength;
@property (nonatomic, strong) NSURLRequest *baseChunkRequest;
@property (copy) NSURL *downloadedFileTempURL;
@property (copy) NSString *downloadedFilename;
@property (nonatomic, strong) NSURL *chunksDirURL;

@property (readonly, getter = isDownloadingChunks) BOOL downloadingChunks;
@property (strong) NSMutableSet *waitingChunks;
@property (strong) NSMutableSet *runningChunks;
@property (strong) NSMutableSet *completedChunks;
@property (nonatomic, readonly) NSSet *chunkErrors;
@end

@implementation CMChunkedDownloadRequest

// ========================================================================== //

#pragma mark - Properties

- (NSSet *) chunkErrors {
	return [_completedChunks valueForKey:@"error"];
}

@dynamic completed;
- (BOOL) didComplete {
	return self.expectedAggregatedContentLength == self.assembledAggregatedContentLength;
}

@dynamic downloadingChunks;
- (BOOL) isDownloadingChunks {
	dispatch_semaphore_wait(_chunksSemaphore, DISPATCH_TIME_FOREVER);
	NSUInteger waitingCount = self.waitingChunks.count;
	NSUInteger runningCount = self.runningChunks.count;
	dispatch_semaphore_signal(_chunksSemaphore);
	return (waitingCount > 0 || runningCount > 0);
}

// ========================================================================== //

#pragma mark - Object

- (void)dealloc {
    dispatch_release(_chunksSemaphore);
}


- (id)initWithURLRequest:(NSURLRequest *)URLRequest {
    self = [super initWithURLRequest:URLRequest];
    if (self) {
		_maxConcurrentChunks = kCMChunkedDownloadRequestDefaultMaxConcurrentChunks;
		_chunkSize = kCMChunkedDownloadRequestDefaultChunkSize;
		_waitingChunks = [NSMutableSet new];
		_runningChunks = [NSMutableSet new];
		_completedChunks = [NSMutableSet new];
		_chunksSemaphore = dispatch_semaphore_create(1);
    }
    return self;
}


// ========================================================================== //

#pragma mark - CMRequest


- (void) cancel {
	[super cancel];
	dispatch_semaphore_wait(_chunksSemaphore, DISPATCH_TIME_FOREVER);
	[_runningChunks enumerateObjectsUsingBlock:^(CMDownloadChunk *chunk, BOOL *stop) {
		[chunk.request cancel];
	}];
	dispatch_semaphore_signal(_chunksSemaphore);

}

- (CMProgressInfo *) progressReceivedInfo {
	CMProgressInfo *progressReceivedInfo = [CMProgressInfo new];
	progressReceivedInfo.request = self;
	progressReceivedInfo.URL = [self.URLRequest URL];
	progressReceivedInfo.tempFileURL = self.downloadedFileTempURL;
	progressReceivedInfo.chunkSize = @(self.lastChunkSize);
	float progress = 0;
	if (self.expectedAggregatedContentLength > 0) {
		progress = (float)self.receivedAggregatedContentLength / (float)self.expectedAggregatedContentLength;
		progressReceivedInfo.progress = @(progress);
	}
	else {
		progressReceivedInfo.progress = @(0);
	}
	return progressReceivedInfo;
}

- (void) handleConnectionWillStart {
	NSAssert(self.URLRequest.HTTPMethod = kCumulusHTTPMethodHEAD, @"Chunked downloads need to start with a HEAD request!");
	NSAssert(self.cachesDir && self.cachesDir.length, @"Attempted a download without setting cachesDir!");
	NSFileManager *fm = [NSFileManager new];
	if (NO == [fm fileExistsAtPath:self.cachesDir]) {
		NSError *error = nil;
		if (NO == [fm createDirectoryAtPath:self.cachesDir withIntermediateDirectories:YES attributes:nil error:&error]) {
			RCLog(@"Could not create cachesDir: %@ %@ (%@)", self.cachesDir, [error localizedDescription], [error userInfo]);
		}
	}
	
	CFUUIDRef UUID = CFUUIDCreate(NULL);
	NSString *tempFilename = (__bridge_transfer NSString *)CFUUIDCreateString(NULL, UUID);
	CFRelease(UUID);
	
	NSString *filePath = [self.cachesDir stringByAppendingPathComponent:tempFilename];
	self.downloadedFileTempURL = [NSURL fileURLWithPath:filePath];
	
	_chunksDirURL = [NSURL fileURLWithPath:[NSString stringWithFormat:@"%@-%@",[self.downloadedFileTempURL path],@"chunks"] isDirectory:YES];
	if (NO == [fm fileExistsAtPath:[_chunksDirURL path]]) {
		NSError *error = nil;
		if (NO == [fm createDirectoryAtPath:[_chunksDirURL path] withIntermediateDirectories:YES attributes:nil error:&error]) {
			RCLog(@"Could not create chunks dir: %@ %@ (%@)", _chunksDirURL, [error localizedDescription], [error userInfo]);
		}
	}
}

- (void) handleConnectionDidReceiveData {
	if (NO == _sentInitialProgress) {
		_sentInitialProgress = YES;
		[super handleConnectionDidReceiveData];
	}
	// do nothing here, see #reallyHandleConnectionDidReceiveData which is called when chunk requests get data
}

- (void) handleConnectionFinished {
	self.expectedAggregatedContentLength = self.expectedContentLength;
	if (self.expectedAggregatedContentLength < 1LL) {
		[self reallyHandleConnectionFinished];
		return;
	}
	
	NSMutableURLRequest *baseChunkRequest = [self.originalURLRequest mutableCopy];
	baseChunkRequest.HTTPMethod = kCumulusHTTPMethodGET;
	_baseChunkRequest = baseChunkRequest;
	
	NSUInteger idx = 0;
	for (long long i = 0; i < self.expectedContentLength; i+=_chunkSize) {
		long long len = _chunkSize;
		if (i+len > self.expectedAggregatedContentLength) {
			len = self.expectedAggregatedContentLength - i;
		}
		CMContentRange range = CMContentRangeMake(i, len, 0);
		[self startChunkForRange:range sequence:idx++];
	}
}

- (void) startChunkForRange:(CMContentRange)range sequence:(NSUInteger)idx {
	CMDownloadChunk *chunk = [CMDownloadChunk new];
	chunk.sequence = idx;
	chunk.size = range.length;

	
	CMDownloadRequest *chunkRequest = [[CMDownloadRequest alloc] initWithURLRequest:_baseChunkRequest];
	
	chunkRequest.timeout = self.timeout;
	[chunkRequest.authProviders addObjectsFromArray:self.authProviders];
	chunkRequest.cachePolicy = self.cachePolicy;
	[chunkRequest.headers addEntriesFromDictionary:self.headers];
	chunkRequest.cachesDir = self.cachesDir;
	chunkRequest.range = range;
	chunkRequest.shouldResume = YES;
	
	__weak typeof(self) self_ = self;
	chunkRequest.didReceiveDataBlock = ^(CMProgressInfo *progressInfo) {
		long long chunkSize = [progressInfo.chunkSize longLongValue];
		self_.receivedAggregatedContentLength += chunkSize;
		if (chunkSize > 0LL) {
			[self_ setLastChunkSize:chunkSize];
			[self_ reallyHandleConnectionDidReceiveData];
		}
	};
	chunkRequest.completionBlock = ^(CMResponse *response) {
		dispatch_semaphore_wait(_chunksSemaphore, DISPATCH_TIME_FOREVER);
		[self_.completedChunks addObject:chunk];
		[self_.runningChunks removeObject:chunk];
		dispatch_semaphore_signal(_chunksSemaphore);

		
		chunk.response = response;
		chunk.request = nil;
		
		if (response.error) {
			chunk.error = response.error;
		}
		else if (response.wasSuccessful) {
			CMProgressInfo *result = response.result;
			NSURL *chunkTempURL = result.tempFileURL;
			NSURL *chunkNewURL = [_chunksDirURL URLByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@",@(idx),[chunkTempURL lastPathComponent]]];
			
			if (nil == self.downloadedFilename) {
				self.downloadedFilename = result.filename;
			}
			
			NSFileManager *fm = [NSFileManager new];
			
			NSError *moveError = nil;
			if (NO == [fm moveItemAtURL:chunkTempURL toURL:chunkNewURL error:&moveError]) {
				RCLog(@"Error moving completed chunk into place! %@ (%@)",[moveError localizedDescription],[moveError userInfo]);
				chunk.error = moveError;
			}
			else {
				chunk.file = chunkNewURL;
			}
		}
		if (NO == self_.isDownloadingChunks) {
			[self_ reallyHandleConnectionFinished];
		}
		else {
			[self_ dispatchNextChunk];
		}
	};
	
	dispatch_semaphore_wait(_chunksSemaphore, DISPATCH_TIME_FOREVER);
	[_waitingChunks addObject:chunk];
	dispatch_semaphore_signal(_chunksSemaphore);
	chunk.request = chunkRequest;
	[self dispatchNextChunk];
}

- (void) dispatchNextChunk {
	dispatch_semaphore_wait(_chunksSemaphore, DISPATCH_TIME_FOREVER);
	NSUInteger runningChunkCount = self.runningChunks.count;
	if (runningChunkCount < self.maxConcurrentChunks) {
		CMDownloadChunk *nextChunk = [self.waitingChunks anyObject];
		if (nextChunk) {
			[self.runningChunks addObject:nextChunk];
			[self.waitingChunks removeObject:nextChunk];
			[nextChunk.request start];
		}
	}
	dispatch_semaphore_signal(_chunksSemaphore);
}


// ========================================================================== //

#pragma mark - Oh Really? Handlers :)



- (void) reallyHandleConnectionFinished {
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
		if (self.chunkErrors.count < 1 && NO == self.wasCanceled) {
			
			dispatch_semaphore_wait(_chunksSemaphore, DISPATCH_TIME_FOREVER);
			NSArray *sortedChunks = [_completedChunks sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"sequence" ascending:YES]]];
			dispatch_semaphore_signal(_chunksSemaphore);

			NSFileManager *fm = [NSFileManager new];
			if ([fm createFileAtPath:[self.downloadedFileTempURL path] contents:nil attributes:nil]) {
				NSError *writeError = nil;
				NSFileHandle *outHandle = [NSFileHandle fileHandleForWritingToURL:self.downloadedFileTempURL error:&writeError];
				if (outHandle) {
					[sortedChunks enumerateObjectsUsingBlock:^(CMDownloadChunk *chunk, NSUInteger idx, BOOL *stop) {
						NSAssert(idx == chunk.sequence, @"Chunks must be sequential");
						if (idx != chunk.sequence) {
							*stop = YES;
							NSDictionary *info = @{ NSLocalizedDescriptionKey : @"Chunk order not sane" };
							self.error = [NSError errorWithDomain:kCumulusErrorDomain code:kCumulusErrorCodeErrorOutOfOrderChunks userInfo:info];
							RCLog(info[NSLocalizedDescriptionKey]);
							return;
						}
						
						NSError *readError = nil;
						long long movedChunkDataLength = 0;
						NSFileHandle *chunkReadHandle = [NSFileHandle fileHandleForReadingFromURL:chunk.file error:&readError];
						if (chunkReadHandle) {
							NSData *readData = [chunkReadHandle readDataOfLength:1024];
							NSUInteger length = [readData length];
							while ( length > 0 ) {
								@try {
									[outHandle writeData:readData];
									movedChunkDataLength += length;
									self.assembledAggregatedContentLength += length;
									readData = [chunkReadHandle readDataOfLength:1024];
									length = [readData length];
								}
								@catch (NSException *exception) {
									*stop = YES;
									NSError *readWriteError = [NSError errorWithDomain:kCumulusErrorDomain code:kCumulusErrorCodeErrorWritingToTempFile userInfo:[exception userInfo]];
									self.error = readWriteError;
									RCLog(@"Error moving data from chunk to aggregate file: %@->%@ %@ (%@)", chunk.file, self.downloadedFileTempURL, [readWriteError localizedDescription], [readWriteError userInfo]);
									length = 0;
									return;
								}
							}
						}
						else {
							*stop = YES;
							self.error = readError;
							RCLog(@"Could not create file handle to read chunk file: %@ %@ (%@)", chunk.file, [readError localizedDescription], [readError userInfo]);
							return;
						}
						if (movedChunkDataLength != chunk.size) {
							*stop = YES;
							NSDictionary *info = @{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Actual chunk size did not match expected chunk size %@ != %@ (%@)",@(movedChunkDataLength), @(chunk.size),[chunk.file lastPathComponent]] };
							self.error = [NSError errorWithDomain:kCumulusErrorDomain code:kCumulusErrorCodeErrorMismatchedChunkSize userInfo:info];
							RCLog(info[NSLocalizedDescriptionKey]);
							RCLog(@"chunk.request.headers: %@",chunk.request.headers);
							RCLog(@"chunk.response.headers: %@",chunk.response.headers);
						}
					}];
				}
				else {
					self.error = writeError;
					RCLog(@"Could not create file handle to aggregated file: %@ %@ (%@)", self.downloadedFileTempURL, [writeError localizedDescription], [writeError userInfo]);
				}
			}
			else {
				NSDictionary *info = @{ NSLocalizedDescriptionKey : @"Not able to create temporary file for chunked download" };
				self.error = [NSError errorWithDomain:kCumulusErrorDomain code:kCumulusErrorCodeErrorCreatingTempFile userInfo:info];
				RCLog(info[NSLocalizedDescriptionKey]);
			}
		}
		else {
			self.error = [self.chunkErrors anyObject];
		}
		
		self.receivedContentLength = self.assembledAggregatedContentLength;
		
		CMProgressInfo *progressInfo = [CMProgressInfo new];
		progressInfo.progress = @(1.f);
		progressInfo.tempFileURL = self.downloadedFileTempURL;
		progressInfo.URL = [self.URLRequest URL];
		progressInfo.filename = self.downloadedFilename;

		self.result = progressInfo;

		[super handleConnectionFinished];
		if (self.didComplete || (NO == self.wasCanceled && self.responseInternal.wasUnsuccessful)) {
			[self removeTempFiles];
		}
	});
}

- (void) removeTempFiles {
	dispatch_async(dispatch_get_main_queue(), ^{
		NSFileManager *fm = [NSFileManager new];
		NSError *error = nil;
		if (NO == [fm removeItemAtURL:self.downloadedFileTempURL error:&error]) {
			RCLog(@"Could not remove temp file: %@ %@ (%@)", self.downloadedFileTempURL, [error localizedDescription], [error userInfo]);
		}
		if (NO == [fm removeItemAtURL:self.chunksDirURL error:&error]) {
			RCLog(@"Could not remove chunks dir: %@ %@ (%@)", self.chunksDirURL, [error localizedDescription], [error userInfo]);
		}
	});
}

- (void) reallyHandleConnectionDidReceiveData {
	[super handleConnectionDidReceiveData];
}


@end