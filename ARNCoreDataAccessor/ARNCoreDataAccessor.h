//
//  ARNCoreDataAccessor.h
//  ARNCoreDataAccessor
//
//  Created by Airin on 2014/04/24.
//  Copyright (c) 2014 Airin. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

typedef void (^ARNSaveCompletionHandler)(BOOL success, NSError *error);

@interface ARNCoreDataAccessor : NSObject

+ (void)settingModelName:(NSString *)modelName
           dbRootDirPath:(NSString *)dbRootDirPath
               dbDirName:(NSString *)dbDirName
                  dbName:(NSString *)dbName;

@end

// NSManagedObjectContext Category
@interface NSManagedObjectContext (NSManagedObjectContext_ARNCoreDataAccessor)

+ (NSManagedObjectContext *)arn_mainQueueContext;
+ (NSManagedObjectContext *)arn_rootSaveingContext;
+ (NSManagedObjectContext *)arn_contextWithParent:(NSManagedObjectContext *)parentContext;
+ (void)arn_saveWithBlockAndWait:(void (^)(NSManagedObjectContext *localContext))block completionBlock:(ARNSaveCompletionHandler)completionBlock;
+ (NSManagedObjectContext *)arn_contextForCurrentThread;
- (void)arn_obtainPermanentIDsBeforeSaving;
- (void)arn_contextWillSave:(NSNotification *)notification;
- (void)arn_saveWithCompletion:(ARNSaveCompletionHandler)completion;

@end

// NSManagedObjectModel Category
@interface NSManagedObjectModel (NSManagedObjectModel_ARNCoreDataAccessor)

+ (NSManagedObjectModel *)arn_defaultManagedObjectModel;

@end

// NSPersistentStore Category
@interface NSPersistentStore (NSPersistentStore_ARNCoreDataAccessor)

+ (NSPersistentStore *)arn_defaultPersistentStore;
+ (void)arn_setDefaultPersistentStore:(NSPersistentStore *)store;
+ (NSURL *)arn_storeURL;

@end

// NSPersistentStoreCoordinator Category
@interface NSPersistentStoreCoordinator (NSPersistentStoreCoordinator_ARNCoreDataAccessor)

+ (NSPersistentStoreCoordinator *)arn_defaultStoreCoordinator;

@end

// NSManagedObject Category
@interface NSManagedObject (NSManagedObject_ARNCoreDataAccessor)

+ (NSArray *)arn_allEntityWithSortArray:(NSArray *)sortArray;
+ (id)arn_createEntity;
- (BOOL)arn_deleteEntity;
+ (void)arn_deleteAllEntity;
+ (NSFetchRequest *)arn_createFetchRequestInContext:(NSManagedObjectContext *)context;
+ (NSArray *)arn_executeFetchRequest:(NSFetchRequest *)request inContext:(NSManagedObjectContext *)context;
+ (instancetype)arn_entityWithEntityProperty:(NSString *)entityProperty entityData:(NSString *)entityData needCreate:(BOOL)needCreate;

@end
