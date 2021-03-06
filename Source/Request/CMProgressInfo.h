//
//  CMProgressInfo.h
//  Cumulus
//
//  Created by John Clayton on 5/2/12.
//  Copyright (c) 2012 Fivesquare Software, LLC. All rights reserved.
//

/*
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * 3. Neither the name of Fivesquare Software, LLC nor the names of its contributors may
 *    be used to endorse or promote products derived from this software without
 *    specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL FIVESQUARE SOFTWARE BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 * OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import <Foundation/Foundation.h>

@class CMRequest;

/** Issued by requests as arguments to a supplied progress block when they receive data on their connection. */
@interface CMProgressInfo : NSObject

/** A weak pointer to the request issuing this progress information.
 *  @note This value is nil on the completion of a request (progress == 1.0) as it is in the process of being destroyed.
 */
@property (nonatomic, weak) CMRequest *request;

/** The URL being fetched. */
@property (nonatomic, strong) NSURL *URL;

/** If a file is being downloaded, representes the location of the temporary file. */
@property (nonatomic, strong) NSURL *tempFileURL;

/** If a file is being downloaded in chunks, representes the location of the temporary directory where chunks are stored. */
@property (nonatomic, strong) NSURL *tempDirURL;

/** If a file is being downloaded, represents the filename the server may have sent in the Content-Disposition header. Can be nil. */
@property (nonatomic, strong) NSString *filename;

/** An NSTimeInterval as an NSNumber representing the time since the request started.*/
@property (nonatomic, strong) NSNumber *elapsedTime;

/** A number from 0.0 to 1.0 representing the amount of data received on the connected in relation to the expected content length.
 *  @note If a file is being streamed (and the content length is not known) this value is meaningless. 
 */
@property (nonatomic, strong) NSNumber *progress;

/** A long long as an NSNumber representing expected total length of the content being retrieved. */
@property (nonatomic, strong) NSNumber *contentLength;

/** A long long as an NSNumber representing the offset in bytes that the current progress represents. Useful when a dowload is resuming and you want to know the actual size of the local temp file. */
@property (nonatomic, strong) NSNumber *fileOffset;

/** A long long as an NSNumber representing the size of the chunk of data received which caused the receiver to be posted. */
@property (nonatomic, strong) NSNumber *chunkSize;

/** An NSNumber representing bytes per second as an NSUInteger. */
@property (nonatomic, strong) NSNumber *bytesPerSecond;

/** A convenience that calculates the remaining time until completion based on the expexted length and byte rate. */
@property (nonatomic, readonly) NSTimeInterval timeRemaining;

/** A convenience for checking whether a download was complete without querying the request. */
@property (nonatomic) BOOL didComplete;

@end
