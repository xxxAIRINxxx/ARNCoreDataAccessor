//
//  ARNCoreDataAccessor.m
//  ARNCoreDataAccessor
//
//  Created by Airin on 2014/04/24.
//  Copyright (c) 2014 Airin. All rights reserved.
//

#import "ARNCoreDataAccessor.h"

static NSString                     *modelName_                 = nil;
static NSString                     *dbRootDirPath_             = nil;
static NSString                     *dbDirName_                 = nil;
static NSString                     *dbName_                    = nil;
static NSManagedObjectModel         *defaultManagedObjectModel_ = nil;
static NSPersistentStore            *defaultPersistentStore_    = nil;
static NSPersistentStoreCoordinator *defaultCoordinator_        = nil;
static NSManagedObjectContext       *mainQueueContext_          = nil;
static NSManagedObjectContext       *rootSaveingContext_        = nil;

static NSString const *kManagedObjectContextKey = @"ARNManagedObjectContextForThreadKey";

@implementation ARNCoreDataAccessor

+ (void)settingModelName:(NSString *)modelName
           dbRootDirPath:(NSString *)dbRootDirPath
               dbDirName:(NSString *)dbDirName
                  dbName:(NSString *)dbName
{
    if (!modelName || !dbRootDirPath || !dbDirName) { return; }
    
    modelName_     = modelName;
    dbRootDirPath_ = dbRootDirPath;
    dbDirName_     = dbDirName;
    dbName_        = dbName;
    
    [NSManagedObjectContext arn_rootSaveingContext];
    [NSManagedObjectContext arn_mainQueueContext];
}

@end

// -------------------------------------------------------------------------------------------------------------------------------//
#pragma mark NSManagedObjectContext Category

@implementation NSManagedObjectContext (NSManagedObjectContext_ARNCoreDataAccessor)

+ (NSManagedObjectContext *)arn_mainQueueContext
{
    @synchronized(self) {
        if (!mainQueueContext_) {
            mainQueueContext_ = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
            [mainQueueContext_ setParentContext:rootSaveingContext_];
            
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(arn_rootContextChanged:)
                                                         name:NSManagedObjectContextDidSaveNotification
                                                       object:[self arn_rootSaveingContext]];
            [mainQueueContext_ arn_obtainPermanentIDsBeforeSaving];
        }
        
        return mainQueueContext_;
    }
}

+ (NSManagedObjectContext *)arn_rootSaveingContext
{
    if (!rootSaveingContext_) {
        rootSaveingContext_ = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        [rootSaveingContext_ performBlockAndWait:^{
            [rootSaveingContext_ setPersistentStoreCoordinator:[NSPersistentStoreCoordinator arn_defaultStoreCoordinator]];
        }];
        [rootSaveingContext_ setMergePolicy:NSMergeByPropertyObjectTrumpMergePolicy];
        [rootSaveingContext_ arn_obtainPermanentIDsBeforeSaving];
    }
    
    return rootSaveingContext_;
}

+ (void)arn_rootContextChanged:(NSNotification *)notification
{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self arn_rootContextChanged:notification];
        });
        
        return;
    }
    
    [[self arn_mainQueueContext] mergeChangesFromContextDidSaveNotification:notification];
}

+ (NSManagedObjectContext *)arn_contextWithParent:(NSManagedObjectContext *)parentContext
{
    NSManagedObjectContext *context = [[self alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
    [context setParentContext:parentContext];
    [context arn_obtainPermanentIDsBeforeSaving];
    
    return context;
}

- (void)arn_obtainPermanentIDsBeforeSaving
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(arn_contextWillSave:)
                                                 name:NSManagedObjectContextWillSaveNotification
                                               object:self];
}

- (void)arn_contextWillSave:(NSNotification *)notification
{
    NSManagedObjectContext *context         = [notification object];
    NSSet                  *insertedObjects = [context insertedObjects];
    
    if ([insertedObjects count]) {
        NSError *error   = nil;
        BOOL     success = [context obtainPermanentIDsForObjects:[insertedObjects allObjects] error:&error];
        if (!success) {
            NSLog(@"contextWillSave error : %@", error.localizedDescription);
            abort();
        }
    }
}

+ (void)arn_saveWithBlockAndWait:(void (^)(NSManagedObjectContext *localContext))block completionBlock:(ARNSaveCompletionHandler)completionBlock
{
    NSManagedObjectContext *localContext = [NSManagedObjectContext arn_contextForCurrentThread];
    [localContext performBlockAndWait:^{
        if (block) {
            block(localContext);
        }
        [localContext arn_saveWithCompletion:completionBlock];
    }];
}

+ (NSManagedObjectContext *)arn_contextForCurrentThread
{
    if ([NSThread isMainThread]) {
        return [self arn_mainQueueContext];
    } else {
        NSMutableDictionary    *theads        = [[NSThread currentThread] threadDictionary];
        NSManagedObjectContext *threadContext = [theads objectForKey:kManagedObjectContextKey];
        if (!threadContext) {
            threadContext = [self arn_contextWithParent:[NSManagedObjectContext arn_rootSaveingContext]];
            [theads setObject:threadContext forKey:kManagedObjectContextKey];
        }
        
        return threadContext;
    }
}

- (void)arn_saveWithCompletion:(ARNSaveCompletionHandler)completion
{
    if (![self hasChanges]) {
        NSLog(@"No_Changes....");
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(NO, nil);
            }
        });
        
        return;
    }
    
    id saveBlock = ^{
        NSError *error = nil;
        BOOL     saved = NO;
        
        @try {
            NSLog(@"Save.........");
            saved = [self save:&error];
        }
        @catch (NSException *exception)
        {
            NSLog(@"save error : %@", (id)[exception userInfo] ? : (id)[exception reason]);
        }
        @finally
        {
            if (!saved) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (completion) {
                        completion(saved, error);
                    }
                });
            }
            else {
                if ([self parentContext]) {
                    [[self parentContext] arn_saveWithCompletion:completion];
                }
                else {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (completion) {
                            completion(saved, error);
                        }
                    });
                }
            }
        }
    };
    [self performBlockAndWait:saveBlock];
}

@end

// -------------------------------------------------------------------------------------------------------------------------------//
#pragma mark NSManagedObjectModel Category

@implementation NSManagedObjectModel (NSManagedObjectModel_ARNCoreDataAccessor)

+ (NSManagedObjectModel *)arn_defaultManagedObjectModel
{
    if (!defaultManagedObjectModel_) {
        NSURL *momURL = [[NSBundle mainBundle] URLForResource:modelName_ withExtension:@"momd"];
        defaultManagedObjectModel_ = [[NSManagedObjectModel alloc] initWithContentsOfURL:momURL];
    }
    
    return defaultManagedObjectModel_;
}

@end

// -------------------------------------------------------------------------------------------------------------------------------//
#pragma mark NSPersistentStore Category

@implementation NSPersistentStore (NSPersistentStore_ARNCoreDataAccessor)

+ (NSPersistentStore *)arn_defaultPersistentStore
{
    return defaultPersistentStore_;
}

+ (void)arn_setDefaultPersistentStore:(NSPersistentStore *)store
{
    defaultPersistentStore_ = store;
}

+ (NSURL *)arn_storeURL
{
    NSString      *path        = [[self class] arn_checkAndCreateDirectoryAtPath:[dbRootDirPath_ stringByAppendingPathComponent:dbDirName_]];
    NSString      *filePath    = [path stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.sqlite", dbName_]];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    if (![fileManager fileExistsAtPath:path]) {
        NSError *error          = nil;
        BOOL     pathWasCreated = [fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error];
        if (!pathWasCreated) {
            NSLog(@"createDirectoryAtPath error : %@", error.localizedDescription);
            abort();
        }
    }
    return [NSURL fileURLWithPath:filePath];
}

+ (NSString *)arn_checkAndCreateDirectoryAtPath:(NSString *)path
{
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        // ないので作る
        NSError *error = nil;
        if ([[NSFileManager defaultManager] createDirectoryAtPath:path
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&error]) {
            if (error) {
                NSLog(@"checkAndCreateDirectoryAtPath error : %@", [error localizedDescription]);
                return nil;
            }
            return path;
        } else {
            return nil;
        }
    } else {
        // already
        return path;
    }
}

@end

// -------------------------------------------------------------------------------------------------------------------------------//
#pragma mark NSPersistentStoreCoordinator Category

@implementation NSPersistentStoreCoordinator (NSPersistentStoreCoordinator_ARNCoreDataAccessor)

+ (NSPersistentStoreCoordinator *)arn_defaultStoreCoordinator
{
    if (!defaultCoordinator_) {
        NSManagedObjectModel *model = [NSManagedObjectModel arn_defaultManagedObjectModel];
        defaultCoordinator_ = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];
        
        NSError           *error = nil;
        NSPersistentStore *store = [defaultCoordinator_ addPersistentStoreWithType:NSSQLiteStoreType
                                                                     configuration:nil
                                                                               URL:[NSPersistentStore arn_storeURL]
                                                                           options:nil
                                                                             error:&error];
        if (!store) {
            // モデル更新してストアをとれない場合、作り直す
            BOOL isMigrationError = [error code] == NSPersistentStoreIncompatibleVersionHashError || [error code] == NSMigrationMissingSourceModelError;
            if ([[error domain] isEqualToString:NSCocoaErrorDomain] && isMigrationError) {
                [[NSFileManager defaultManager] removeItemAtURL:[NSPersistentStore arn_storeURL] error:nil];
                store = [defaultCoordinator_ addPersistentStoreWithType:NSSQLiteStoreType
                                                          configuration:nil
                                                                    URL:[NSPersistentStore arn_storeURL]
                                                                options:nil
                                                                  error:&error];
                if (!store) {
                    NSLog(@"addPersistentStoreWithType error : %@", error.localizedDescription);
                    abort();
                }
            }
        }
        
        NSArray *persistentStores = [defaultCoordinator_ persistentStores];
        if ([persistentStores count] && ![NSPersistentStore arn_defaultPersistentStore]) {
            [NSPersistentStore arn_setDefaultPersistentStore:[persistentStores objectAtIndex:0]];
        }
    }
    
    return defaultCoordinator_;
}

@end

// -------------------------------------------------------------------------------------------------------------------------------//
#pragma mark NSManagedObject Category

@implementation NSManagedObject (NSManagedObject_ARNCoreDataAccessor)

+ (NSArray *)arn_allEntityWithSortArray:(NSArray *)sortArray
{
    NSFetchRequest *request = [self arn_createFetchRequestInContext:[NSManagedObjectContext arn_contextForCurrentThread]];
    [request setSortDescriptors:sortArray];
    NSArray *result = [self arn_executeFetchRequest:request inContext:[NSManagedObjectContext arn_contextForCurrentThread]];
    
    return result;
}

+ (id)arn_createEntity
{
    return [NSEntityDescription insertNewObjectForEntityForName:NSStringFromClass(self)
                                         inManagedObjectContext:[NSManagedObjectContext arn_contextForCurrentThread]];
}

- (BOOL)arn_deleteEntity
{
    [[self managedObjectContext] deleteObject:self];
    
    return YES;
}

+ (void)arn_deleteAllEntity
{
    NSFetchRequest *request = [self arn_createFetchRequestInContext:[NSManagedObjectContext arn_contextForCurrentThread]];
    NSArray        *result  = [self arn_executeFetchRequest:request inContext:[NSManagedObjectContext arn_contextForCurrentThread]];
    
    if (result && [result count]) {
        [NSManagedObjectContext arn_saveWithBlockAndWait: ^(NSManagedObjectContext *localContext) {
            for (NSManagedObject * entity in result) {
                [entity arn_deleteEntity];
            }
        } completionBlock:nil];
    }
}

+ (NSFetchRequest *)arn_createFetchRequestInContext:(NSManagedObjectContext *)context
{
    NSFetchRequest *request = [[NSFetchRequest alloc] init];
    [request setEntity:[NSEntityDescription entityForName:NSStringFromClass(self) inManagedObjectContext:context]];
    
    return request;
}

+ (NSArray *)arn_executeFetchRequest:(NSFetchRequest *)request inContext:(NSManagedObjectContext *)context
{
    __block NSArray *results = nil;
    [context performBlockAndWait:^{
        NSError *error = nil;
        results = [context executeFetchRequest:request error:&error];
    }];
    
    return results;
}

+ (instancetype)arn_entityWithEntityProperty:(NSString *)entityProperty entityData:(NSString *)entityData needCreate:(BOOL)needCreate
{
    __block NSManagedObject *entity;
    __weak typeof(self) weakSelf = self;
    
    [[NSManagedObjectContext arn_contextForCurrentThread] performBlockAndWait: ^{
        NSFetchRequest *request = [[weakSelf class] arn_createFetchRequestInContext:[NSManagedObjectContext arn_contextForCurrentThread]];
        [request setFetchLimit:1];
        [request setPredicate:[NSPredicate predicateWithFormat:@"%K == %@", entityProperty, entityData]];
        
        NSArray *result = [[weakSelf class] arn_executeFetchRequest:request inContext:[NSManagedObjectContext arn_contextForCurrentThread]];
        if (!result || ![result count]) {
            if (needCreate) {
                entity = [[weakSelf class] arn_createEntity];
            } else {
                entity =  nil;
            }
        } else {
            entity = result[0];
        }
    }];
    
    return entity;
}

@end
