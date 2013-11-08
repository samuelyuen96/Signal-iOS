#import <SenTestingKit/SenTestingKit.h>

#import "YapDatabase.h"
#import "YapDatabaseSecondaryIndex.h"

#import "TestObject.h"

#import "DDLog.h"
#import "DDTTYLogger.h"


@interface TestYapDatabaseSecondaryIndex : SenTestCase

@end

@implementation TestYapDatabaseSecondaryIndex

- (NSString *)databasePath:(NSString *)suffix
{
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
	NSString *baseDir = ([paths count] > 0) ? [paths objectAtIndex:0] : NSTemporaryDirectory();
	
	NSString *databaseName = [NSString stringWithFormat:@"%@-%@.sqlite", THIS_FILE, suffix];
	
	return [baseDir stringByAppendingPathComponent:databaseName];
}

- (void)setUp
{
	[super setUp];
	[DDLog removeAllLoggers];
	[DDLog addLogger:[DDTTYLogger sharedInstance]];
}

- (void)tearDown
{
	[DDLog flushLog];
	[super tearDown];
}

- (void)test
{
	NSString *databasePath = [self databasePath:NSStringFromSelector(_cmd)];
	
	[[NSFileManager defaultManager] removeItemAtPath:databasePath error:NULL];
	YapDatabase *database = [[YapDatabase alloc] initWithPath:databasePath];
	
	STAssertNotNil(database, @"Oops");
	
	YapDatabaseConnection *connection = [database newConnection];
	
	YapDatabaseSecondaryIndexSetup *setup = [[YapDatabaseSecondaryIndexSetup alloc] init];
	[setup addColumn:@"someDate" withType:YapDatabaseSecondaryIndexTypeReal];
	[setup addColumn:@"someInt" withType:YapDatabaseSecondaryIndexTypeInteger];
	
	YapDatabaseSecondaryIndexBlockType blockType = YapDatabaseSecondaryIndexBlockTypeWithObject;
	YapDatabaseSecondaryIndexWithObjectBlock block =
	    ^(NSMutableDictionary *dict, NSString *key, id object){
		
		// If we're storing other types of objects in our database,
		// then we should check the object before presuming we can cast it.
		if ([object isKindOfClass:[TestObject class]])
		{
			__unsafe_unretained TestObject *testObject = (TestObject *)object;
			
			if (testObject.someDate)
				[dict setObject:testObject.someDate forKey:@"someDate"];
			
			[dict setObject:@(testObject.someInt) forKey:@"someInt"];
		}
	};
	
	YapDatabaseSecondaryIndex *secondaryIndex =
	    [[YapDatabaseSecondaryIndex alloc] initWithSetup:setup block:block blockType:blockType];
	
	[database registerExtension:secondaryIndex withName:@"idx"];
	
	//
	// Test populating the database
	//
	
	NSDate *startDate = [NSDate date];
	int startInt = 0;
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		for (int i = 0; i < 20; i++)
		{
			NSDate *someDate = [startDate dateByAddingTimeInterval:i];
			int someInt = startInt + i;
			
			TestObject *object = [TestObject generateTestObjectWithSomeDate:someDate someInt:someInt];
			
			NSString *key = [NSString stringWithFormat:@"key%d", i];
			
			[transaction setObject:object forKey:key];
		}
	}];
	
	//
	// Test basic queries
	//
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		__block NSUInteger count = 0;
		YapDatabaseQuery *query = nil;
		
		count = 0;
		query = [YapDatabaseQuery queryWithFormat:@"WHERE someInt < 5"];
		[[transaction ext:@"idx"] enumerateKeysMatchingQuery:query usingBlock:^(NSString *key, BOOL *stop) {
			
			count++;
		}];
		
		STAssertTrue(count == 5, @"Incorrect count: %lu", (unsigned long)count);
		
		count = 0;
		query = [YapDatabaseQuery queryWithFormat:@"WHERE someInt < ?", @(5)];
		
		[[transaction ext:@"idx"] enumerateKeysMatchingQuery:query usingBlock:^(NSString *key, BOOL *stop) {
			
			count++;
		}];
		
		STAssertTrue(count == 5, @"Incorrect count: %lu", (unsigned long)count);
	}];
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		__block NSUInteger count = 0;
		YapDatabaseQuery *query = nil;
		
		count = 0;
		query = [YapDatabaseQuery queryWithFormat:@"WHERE someDate < ?", [startDate dateByAddingTimeInterval:5]];
		[[transaction ext:@"idx"] enumerateKeysMatchingQuery:query usingBlock:^(NSString *key, BOOL *stop) {
			
			count++;
		}];
		
		STAssertTrue(count == 5, @"Incorrect count: %lu", (unsigned long)count);
		
		count = 0;
		query = [YapDatabaseQuery queryWithFormat:@"WHERE someDate < ? AND someInt < ?",
		                         [startDate dateByAddingTimeInterval:5],           @(4)];
		
		[[transaction ext:@"idx"] enumerateKeysMatchingQuery:query usingBlock:^(NSString *key, BOOL *stop) {
			
			count++;
		}];
		
		STAssertTrue(count == 4, @"Incorrect count: %lu", (unsigned long)count);
	}];
	
	//
	// Test updating the database
	//
	
	startDate = [NSDate dateWithTimeIntervalSinceNow:4];
	startInt = 100;
	
	[connection readWriteWithBlock:^(YapDatabaseReadWriteTransaction *transaction) {
		
		for (int i = 0; i < 20; i++)
		{
			NSDate *someDate = [startDate dateByAddingTimeInterval:i];
			int someInt = startInt + i;
			
			TestObject *object = [TestObject generateTestObjectWithSomeDate:someDate someInt:someInt];
			
			NSString *key = [NSString stringWithFormat:@"key%d", i];
			
			[transaction setObject:object forKey:key];
		}
	}];
	
	//
	// Re-check basic queries
	//
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		__block NSUInteger count = 0;
		YapDatabaseQuery *query = nil;
		
		count = 0;
		query = [YapDatabaseQuery queryWithFormat:@"WHERE someInt < 105"];
		[[transaction ext:@"idx"] enumerateKeysMatchingQuery:query usingBlock:^(NSString *key, BOOL *stop) {
			
			count++;
		}];
		
		STAssertTrue(count == 5, @"Incorrect count: %lu", (unsigned long)count);
		
		count = 0;
		query = [YapDatabaseQuery queryWithFormat:@"WHERE someInt < ?", @(105)];
		[[transaction ext:@"idx"] enumerateKeysMatchingQuery:query usingBlock:^(NSString *key, BOOL *stop) {
			
			count++;
		}];
		
		STAssertTrue(count == 5, @"Incorrect count: %lu", (unsigned long)count);
		
		count = 0;
		query = [YapDatabaseQuery queryWithFormat:@"WHERE someInt < 105"];
		[[transaction ext:@"idx"] getNumberOfRows:&count matchingQuery:query];
		
		STAssertTrue(count == 5, @"Incorrect count: %lu", (unsigned long)count);
		
		count = 0;
		query = [YapDatabaseQuery queryWithFormat:@"WHERE someInt < ?", @(105)];
		[[transaction ext:@"idx"] getNumberOfRows:&count matchingQuery:query];
		
		STAssertTrue(count == 5, @"Incorrect count: %lu", (unsigned long)count);
	}];
	
	[connection readWithBlock:^(YapDatabaseReadTransaction *transaction) {
		
		__block NSUInteger count = 0;
		YapDatabaseQuery *query = nil;
		
		count = 0;
		query = [YapDatabaseQuery queryWithFormat:@"WHERE someDate < ?", [startDate dateByAddingTimeInterval:5]];
		[[transaction ext:@"idx"] enumerateKeysMatchingQuery:query usingBlock:^(NSString *key, BOOL *stop) {
			
			count++;
		}];
		
		STAssertTrue(count == 5, @"Incorrect count: %lu", (unsigned long)count);
		
		count = 0;
		query = [YapDatabaseQuery queryWithFormat:@"WHERE someDate < ? AND someInt < ?",
				 [startDate dateByAddingTimeInterval:5],           @(104)];
		
		[[transaction ext:@"idx"] enumerateKeysMatchingQuery:query usingBlock:^(NSString *key, BOOL *stop) {
			
			count++;
		}];
		
		STAssertTrue(count == 4, @"Incorrect count: %lu", (unsigned long)count);
		
		count = 0;
		query = [YapDatabaseQuery queryWithFormat:@"WHERE someDate < ?", [startDate dateByAddingTimeInterval:5]];
		[[transaction ext:@"idx"] getNumberOfRows:&count matchingQuery:query];
		
		STAssertTrue(count == 5, @"Incorrect count: %lu", (unsigned long)count);
		
		count = 0;
		query = [YapDatabaseQuery queryWithFormat:@"WHERE someDate < ? AND someInt < ?",
				 [startDate dateByAddingTimeInterval:5],           @(104)];
		
		[[transaction ext:@"idx"] getNumberOfRows:&count matchingQuery:query];
		
		STAssertTrue(count == 4, @"Incorrect count: %lu", (unsigned long)count);
	}];
}

@end
