//
//  CMS3AuthProvider.h
//  Cumulus
//
//  Created by John Clayton on 8/16/12.
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

#import "CMAuthProvider.h"

#import "CMTypes.h"

@class CMResource;

@protocol CMAmazonCredentials;

/** Provides Amazon S3 authentication to CMResources. Lots of the auth code was adapted from what Amazon are doing in their AmazonS3Client, available in their SDK. */
@interface CMS3AuthProvider : NSObject<CMAuthProvider>

/** Any object that implements <CMAmazonCredentials> can satisfy this role. If the credentials are present and valid they will be used, otherwise if a provider is supplied, new ones will be requested. */
@property (nonatomic, strong) id<CMAmazonCredentials> credentials;

/** A resource that knows how to fetch new credentials. It must have a postProcessor block that knows how to transform response#result to an CMAmazonCredentials object. */
@property (nonatomic, strong) CMResource *credentialsProvider;



@end
