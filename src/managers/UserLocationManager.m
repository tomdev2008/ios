//
//  UserLocationManager.m
//  CycleStreets
//
//  Created by Neil Edwards on 28/09/2012.
//  Copyright (c) 2012 CycleStreets. All rights reserved.
//

// Handles gobal lgps lookups

#import "UserLocationManager.h"
#import "DeviceUtilities.h"
#import "GlobalUtilities.h"

@interface UserLocationManager(Private)

-(void)initialiseCorelocation;
-(void)resetLocationAndReAssess;
-(void)assessUserLocation;
- (void)stopUpdatingLocation:(NSString *)subscriberId;
-(void)UserLocationWasUpdated;

-(BOOL)addSubscriber:(NSString*)subscriberId;
-(BOOL)removeSubscriber:(NSString*)subscriberId;
-(int)findSubscriber:(NSString*)subscriberId;
-(void)removeAllSubscribers;


@end

@implementation UserLocationManager
SYNTHESIZE_SINGLETON_FOR_CLASS(UserLocationManager);

@synthesize didFindDeviceLocation;
@synthesize locationState;
@synthesize isLocating;
@synthesize locationSubscribers;
@synthesize locationManager;
@synthesize locationMeasurements;
@synthesize bestEffortAtLocation;
@synthesize delegate;
@synthesize authorisationSubscriber;


+ (CLLocationCoordinate2D)defaultCoordinate {
	CLLocationCoordinate2D coordinate;
	coordinate.latitude = 52.00;
	coordinate.longitude = 0.0;
	return coordinate;
}

+ (CLLocation*)defaultLocation {
	
	CLLocationCoordinate2D coordinate=[UserLocationManager defaultCoordinate];
	CLLocation *location=[[CLLocation alloc] initWithLatitude:coordinate.latitude longitude:coordinate.longitude];
    
	return location;
}


-(id)init{
	
	if (self = [super init])
	{
        BetterLog(@"");
		
		didFindDeviceLocation=NO;
        isLocating=NO;
		
		
		self.locationSubscribers=[NSMutableArray array];
		
		locationState=kConnectLocationStateSingle;
		
        [self initialiseCorelocation];
        
		
	}
	return self;
}


//
/***********************************************
 * @description		NOTIFICATIONS
 ***********************************************/
//

-(void)listNotificationInterests{
    
	
	
	[super listNotificationInterests];
	
}

-(void)didReceiveNotification:(NSNotification*)notification{
	
	
	
}


- (BOOL)hasSubscriber:(NSString*)subscriber{
	
	int index=[self findSubscriber:subscriber];
	
	return index!=NSNotFound;
    
}


-(BOOL)systemLocationServicesEnabled{
	
	BOOL result=[CLLocationManager locationServicesEnabled];
	
	return result;
	
}

-(BOOL)appLocationServicesEnabled{
	
	CLAuthorizationStatus status=[CLLocationManager authorizationStatus];
	
	BOOL result=status==kCLAuthorizationStatusAuthorized;
	
	return result;
	
}

-(BOOL)doesDeviceAllowLocation{
	
	return [self systemLocationServicesEnabled] && [self appLocationServicesEnabled];
	
}


-(BOOL)checkLocationStatus:(BOOL)showAlert{
	
	
	if([self doesDeviceAllowLocation]==NO){
        
		if(showAlert==YES){
			
			UIAlertView *servicesDisabledAlert = [[UIAlertView alloc] initWithTitle:@"Location Services Disabled"
																			message:@"Unable to retrieve location. Location services for the App may be off, please enable in Settings > General > Location Services to use location based features."
																		   delegate:nil
																  cancelButtonTitle:@"OK"
																  otherButtonTitles:nil];
			[servicesDisabledAlert show];
		}
		
	}
	
	
	return [self doesDeviceAllowLocation];
	
}



- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status{
    
    if(status==kCLAuthorizationStatusAuthorized){
        
        if(authorisationSubscriber!=nil){
            [self startUpdatingLocationForSubscriber:authorisationSubscriber];
            authorisationSubscriber=nil;
        }
        
        
    }
    
}


#pragma mark CoreLocation updating

//
/***********************************************
 * @description			Check for CL system pref status
 ***********************************************/
//
-(void)initialiseCorelocation{
	
	if(locationManager==nil){
			self.locationManager = [[CLLocationManager alloc] init];
			locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers;
			locationManager.distanceFilter =kCLDistanceFilterNone;
            locationManager.delegate=self;
    }
		
}



//
/***********************************************
 * @description			LOCATION LOOKUP AND ASSESSMENT
 ***********************************************/
//


-(void)resetLocationAndReAssess{
	
	self.bestEffortAtLocation=nil;
	
	[self startUpdatingLocationForSubscriber:nil];
	
}



//
/***********************************************
 * @description			Location subscribers
 ***********************************************/
//
-(BOOL)addSubscriber:(NSString*)subscriberId{
	
	int index=[self findSubscriber:subscriberId];
	
	if(index==NSNotFound){
		
		[locationSubscribers addObject:subscriberId];
		return YES;
		
	}
	return NO;
	
}

-(BOOL)removeSubscriber:(NSString*)subscriberId{
	
	int index=[self findSubscriber:subscriberId];
	
	if(index!=NSNotFound){
		
		[locationSubscribers removeObjectAtIndex:index];
		return YES;
		
	}
	return NO;
}

-(void)removeAllSubscribers{
	
	[locationSubscribers removeAllObjects];
	
}


-(int)findSubscriber:(NSString*)subscriberId{
	
	int index=[locationSubscribers indexOfObject:subscriberId];
	
	return index;
}



// both start and stop need to maintain a list of subscribers
// so only 1 can affect it, ie if we recieve a stop command it will only take affect if there is only 1 subscriber

-(void)startUpdatingLocationForSubscriber:(NSString*)subscriberId{
	
	BetterLog(@"");
    
    if(isLocating==NO){
		
		if([self doesDeviceAllowLocation]==YES){
			
			BOOL result=[self addSubscriber:subscriberId];
			
			if(result==YES){
                
                BetterLog(@"[MESSAGE]: Starting location...");
                
				[locationManager startUpdatingLocation];
				[self performSelector:@selector(stopUpdatingLocation:) withObject:subscriberId afterDelay:3000];
			}else{
                
                BetterLog(@"[WARNING]: unable to add subscriber");
                
            }
			
		}else {
            
            BetterLog(@"[WARNING]: GPSLOCATIONDISABLED");
			
			[[NSNotificationCenter defaultCenter] postNotificationName:GPSLOCATIONDISABLED object:nil userInfo:nil];
            
            CLAuthorizationStatus status=[CLLocationManager authorizationStatus];
            
            if(status==kCLAuthorizationStatusNotDetermined){
                
                authorisationSubscriber=subscriberId;
            
                [locationManager startUpdatingLocation];
                [self performSelector:@selector(stopUpdatingLocation:) withObject:SYSTEM afterDelay:0.1];
                
            }else{
                
                BetterLog(@"[WARNING]: GPS AUTHORISATION IS: kCLAuthorizationStatusDenied");
            }
		}
            
    }else{
		
		[self addSubscriber:subscriberId];
        
    }
    
}


//
/***********************************************
 * @description			CLLocationManager  delegate callback, receives new updated location. Asses wether this is inside our preferred accuracy
 ***********************************************/
//
- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation {
	
	BetterLog(@"");
	
	NSTimeInterval locationAge = -[newLocation.timestamp timeIntervalSinceNow];
	
    if (locationAge > 5.0) return;
    if (newLocation.horizontalAccuracy < 0) return;
    // test the measurement to see if it is more accurate than the previous measurement
    if (bestEffortAtLocation == nil || bestEffortAtLocation.horizontalAccuracy > newLocation.horizontalAccuracy) {
        self.bestEffortAtLocation = newLocation;
        
		BetterLog(@"newLocation.horizontalAccuracy=%f",newLocation.horizontalAccuracy);
		BetterLog(@"locationManager.desiredAccuracy=%f",locationManager.desiredAccuracy);
		
		[[NSNotificationCenter defaultCenter] postNotificationName:GPSLOCATIONUPDATE object:bestEffortAtLocation userInfo:nil];
		
        if (newLocation.horizontalAccuracy <= locationManager.desiredAccuracy) {
			
			BetterLog(@"Location found!");
            
			self.bestEffortAtLocation = newLocation;
			didFindDeviceLocation=YES;
			
        }
    }
	
	
	switch(locationState){
			
		case kConnectLocationStateSingle:
			
			if (didFindDeviceLocation==YES){
                
				[self UserLocationWasUpdated];
				[self stopUpdatingLocationForSubscriber:SYSTEM];
				
			}
			break;
		case kConnectLocationStateTracking:
			
			// GPSLOCATIONUPDATE is now sent in main loop
			
            break;
			
	}
    
	
	
}


- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error{
	
	BetterLog(@" Error:=%@",error.localizedDescription);
    
    isLocating=NO;
	
	[self removeAllSubscribers];
    
    [self stopUpdatingLocation:SYSTEM];
	
	[[NSNotificationCenter defaultCenter] postNotificationName:GPSLOCATIONFAILED object:[NSNumber numberWithBool:didFindDeviceLocation] userInfo:nil];
	
	
	
}


//
/***********************************************
 * @description		notify UI that the location has been determined
 ***********************************************/
//
-(void)UserLocationWasUpdated{
	
	BetterLog(@"");
	
	[[NSNotificationCenter defaultCenter] postNotificationName:GPSLOCATIONCOMPLETE object:bestEffortAtLocation userInfo:nil];
	
}


//
/***********************************************
 * @description		Stop Location tracking, can be called via an valid response or on a timeout error
 ***********************************************/
//
- (void)stopUpdatingLocationForSubscriber:(NSString *)subscriberId {
	
	BetterLog(@"");
	
	
	if(subscriberId==SYSTEM){
		
		[self removeAllSubscribers];
		
	}else{
		
		[self removeSubscriber:subscriberId];
		
	}
	
	if([locationSubscribers count]==0){
        
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(stopUpdatingLocation:) object:nil];
        
		isLocating=NO;
        
		[locationManager stopUpdatingLocation];
		
	}
	
}

-(void)stopUpdatingLocation:(NSString *)subscriberId{
	
	[self stopUpdatingLocationForSubscriber:subscriberId];
}


//------------------------------------------------------------------------------------
#pragma mark - GeoCoding
//------------------------------------------------------------------------------------

+(void)reverseGeoCodeLocation:(CLLocation*)location{
    
    CLGeocoder *geocoder=[[CLGeocoder alloc] init];
    
    [geocoder reverseGeocodeLocation:location completionHandler:^(NSArray *placemarks, NSError *error) {
        
        if([placemarks count]>0){
            [[NSNotificationCenter defaultCenter] postNotificationName:REVERSEGEOLOCATIONCOMPLETE object:[placemarks objectAtIndex:0] userInfo:nil];
        }else{
            // what is the error?
        }
        
    } ];
    
}

@end

