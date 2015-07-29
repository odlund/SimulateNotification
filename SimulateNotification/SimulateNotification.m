#import "SimulateNotification.h"

@interface SimulateNotification ()

@property (nonatomic) NSBundle *bundle;
@property (nonatomic) AsyncUdpSocket *udpSocket;
@property (nonatomic) NSMenuItem *selectedItem;
@property (nonatomic) NSMenuItem *notificationsMenu;
@property (nonatomic) NSArray *payloadPaths;

@end

@implementation SimulateNotification

+ (void)pluginDidLoad:(NSBundle *)plugin {
    static id sharedPlugin = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedPlugin = [[self alloc] initWithBundle:plugin];
    });
}

- (id)initWithBundle:(NSBundle *)plugin {
    if (self = [super init]) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(didApplicationFinishLaunchingNotification:)
                                                     name:NSApplicationDidFinishLaunchingNotification
                                                   object:nil];
        _bundle = plugin;
        _payloadPaths = @[];

    }
    return self;
}

- (void)didApplicationFinishLaunchingNotification:(NSNotification *)notification {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSApplicationDidFinishLaunchingNotification object:nil];
    
    [self addMenuItems];
    [self initializeUdpSocket];
    
    NSMenuItem *menuItem = [[NSApp mainMenu] itemWithTitle:@"Edit"];
    if (menuItem) {
        [[menuItem submenu] addItem:[NSMenuItem separatorItem]];
        NSMenuItem *actionMenuItem = [[NSMenuItem alloc] initWithTitle:@"Do Action" action:@selector(doMenuAction) keyEquivalent:@""];
        [actionMenuItem setTarget:self];
        [[menuItem submenu] addItem:actionMenuItem];
    }
}



- (void)initializeUdpSocket {
    self.udpSocket = [[AsyncUdpSocket alloc] initWithDelegate:self];
	
	NSError *error = nil;
	
	if (![self.udpSocket bindToPort:0 error:&error]) {
		NSLog(@"Error binding: %@", error);
		return;
	}
	
	[self.udpSocket receiveWithTimeout:-1 tag:0];
	
	NSLog(@"UDP Socket Ready");
}

#pragma mark - Menu

- (void)addMenuItems {
    NSMenuItem *topMenuItem = [[NSApp mainMenu] itemWithTitle:@"Debug"];
    if (topMenuItem) {
        self.notificationsMenu = [[NSMenuItem alloc] initWithTitle:@"Simulate Notification" action:nil keyEquivalent:@""];
        self.notificationsMenu.submenu = [[NSMenu alloc] initWithTitle:@"Simulate Notification"];
        
        [self addSendInputItem];
        [self.notificationsMenu.submenu addItem:[NSMenuItem separatorItem]];
        [self addFileManagementItem];
        
        [[topMenuItem submenu] insertItem:self.notificationsMenu atIndex:[topMenuItem.submenu indexOfItemWithTitle:@"Simulate Location"]];
    }
}

- (void)addSendInputItem {
    NSMenuItem *sendInputItem = [[NSMenuItem alloc] initWithTitle:@"Input Payload to Send" action:@selector(simulatePushNotificationUsingPayload) keyEquivalent:@"s"];
    sendInputItem.keyEquivalentModifierMask = NSAlternateKeyMask;
    sendInputItem.target = self;
    [self.notificationsMenu.submenu addItem:sendInputItem];
}

- (void)addFileManagementItem {
    NSMenuItem *fileManagementItem = [[NSMenuItem alloc] initWithTitle:@"Manage Payload Files" action:nil keyEquivalent:@""];
    fileManagementItem.submenu = [[NSMenu alloc] initWithTitle:@"Manage Payload Files"];

    NSMenuItem *addFilesItem = [[NSMenuItem alloc] initWithTitle:@"Add Payload Files" action:@selector(addPayloadFiles) keyEquivalent:@""];
    addFilesItem.target = self;
    
    [fileManagementItem.submenu addItem:addFilesItem];
    [self.notificationsMenu.submenu addItem:fileManagementItem];
}

- (void)addSendAndSelectItems {
    [self.notificationsMenu.submenu addItem:[NSMenuItem separatorItem]];
    
    NSMenuItem *sendSelectedItem = [[NSMenuItem alloc] initWithTitle:@"Send Selected Payload" action:@selector(simulatePushNotificationUsingSelectedItem) keyEquivalent:@"n"];
    sendSelectedItem.keyEquivalentModifierMask = NSAlternateKeyMask;
    sendSelectedItem.target = self;
    [self.notificationsMenu.submenu addItem:sendSelectedItem];
    
    NSMenuItem *selectNextItem = [[NSMenuItem alloc] initWithTitle:@"Select Next Payload" action:@selector(selectNextPayload) keyEquivalent:@"n"];
    selectNextItem.keyEquivalentModifierMask = NSControlKeyMask | NSAlternateKeyMask;
    selectNextItem.target = self;
    [self.notificationsMenu.submenu addItem:selectNextItem];
    
    NSMenuItem *selectPreviousItem = [[NSMenuItem alloc] initWithTitle:@"Select Previous Payload" action:@selector(selectPreviousPayload) keyEquivalent:@"n"];
    selectPreviousItem.keyEquivalentModifierMask = NSCommandKeyMask | NSAlternateKeyMask;
    selectPreviousItem.target = self;
    [self.notificationsMenu.submenu addItem:selectPreviousItem];
    
    [self.notificationsMenu.submenu addItem:[NSMenuItem separatorItem]];
}

- (void)addPayloadItems {
    [self.jsonItems enumerateObjectsUsingBlock:^(NSMenuItem *item, NSUInteger idx, BOOL *stop) {
        [self.notificationsMenu.submenu removeItem:item];
    }];

    [self.payloadPaths enumerateObjectsUsingBlock:^(NSURL *jsonFileURL, NSUInteger idx, BOOL *stop) {
        NSString *fileName = [[jsonFileURL lastPathComponent] stringByDeletingPathExtension];
        NSString *title = [fileName stringByReplacingOccurrencesOfString:@".json" withString:@""];
        title = [title stringByReplacingOccurrencesOfString:@"_" withString:@" "];
        NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:title.capitalizedString action:@selector(setItemSelected:) keyEquivalent:@""];
        menuItem.target = self;
        menuItem.representedObject = jsonFileURL;
        [self.notificationsMenu.submenu addItem:menuItem];
    }];
    
    if (!self.selectedItem) {
        self.selectedItem = self.jsonItems[0];
    }
}

- (void)addPayloadFiles {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:YES];
    [panel setTitle:@"Select JSON files for Remote Notification Payloads"];
    [panel beginWithCompletionHandler:^(NSInteger result) {
        if (NSFileHandlingPanelOKButton == result) {
            if (!self.payloadPaths.count) {
                [self addSendAndSelectItems];
            }
            NSSet *uniqueSet = [NSSet setWithArray:[self.payloadPaths arrayByAddingObjectsFromArray:panel.URLs]];
            self.payloadPaths = uniqueSet.allObjects;
            [self addPayloadItems];
        }
    }];
}

#pragma mark - Menu Actions

- (void)setItemSelected:(id)sender {
    self.selectedItem = sender;
}

- (void)simulatePushNotificationUsingPayload {
    NSAlert *alert = [NSAlert alertWithMessageText:@"Input a Vaild JSON Payload" defaultButton:@"OK" alternateButton:@"Cancel" otherButton:nil informativeTextWithFormat:@""];
    
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 40, 300, 300)];
    [input setStringValue:@"{ \n\t\"aps\": { \n \t\t\"alert\": \"Test\",\n\t\t\"sound\": \"default\",\n\t\t\"badge\": \"0\"\n\t}\n}"];
    [alert setAccessoryView:input];

    if (NSAlertDefaultReturn == [alert runModal]) {
        [input validateEditing];
    
        NSData *data = [input.stringValue dataUsingEncoding:NSUTF8StringEncoding];
        if ([self isValidJSONData:data]) {
            [self.udpSocket sendData:data toHost:@"localhost" port:9930 withTimeout:-1 tag:0];
        } else {
            if (NSAlertDefaultReturn == [[NSAlert alertWithMessageText:@"Invaild JSON Payload" defaultButton:@"Retry" alternateButton:@"Cancel" otherButton:nil informativeTextWithFormat:@""] runModal]) {
                [self simulatePushNotificationUsingPayload];
            }
        }
    }
}

- (void)simulatePushNotificationUsingSelectedItem {
    __block NSURL *fileURL = [self.selectedItem representedObject];
    
    if (!fileURL) {
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        [panel setAllowsMultipleSelection:NO];
        [panel setTitle:@"Select JSON file for Remote Notification Payload"];
        [panel beginWithCompletionHandler:^(NSInteger result) {
            if (NSFileHandlingPanelOKButton == result) {
                fileURL = panel.URL;
                self.payloadPaths = [self.payloadPaths arrayByAddingObject:panel.URL];
            } else {
                return;
            }
        }];
    }
    
    NSAssert([[NSFileManager defaultManager] isReadableFileAtPath:fileURL.path], @"It seems that there is no file at path");
    NSData *data = [NSData dataWithContentsOfURL:fileURL];
    
    if ([self isValidJSONData:data]) {
        [self.udpSocket sendData:data toHost:@"localhost" port:9930 withTimeout:-1 tag:0];
    } else {
        if (NSAlertDefaultReturn == [[NSAlert alertWithMessageText:@"Invaild JSON file" defaultButton:@"Retry" alternateButton:@"Cancel" otherButton:nil informativeTextWithFormat:@""] runModal]) {
        }
    }
}

- (void)selectNextPayload {
    NSInteger nextIndex = [self.jsonItems indexOfObject:self.selectedItem] + 1;
    self.selectedItem = self.jsonItems.count > nextIndex ? self.jsonItems[nextIndex] : self.jsonItems[0];
}

- (void)selectPreviousPayload {
    NSInteger previousIndex = [self.jsonItems indexOfObject:self.selectedItem] - 1;
    self.selectedItem = 0 < previousIndex ? self.jsonItems[previousIndex] : self.jsonItems.lastObject;
}

#pragma mark - Properties

- (BOOL)isValidJSONData:(NSData *)data {
    return [NSJSONSerialization isValidJSONObject:[NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:nil]];
}

- (NSArray *)jsonItems {
    return [self.notificationsMenu.submenu.itemArray filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"representedObject != nil"]];
}

- (void)setSelectedItem:(NSMenuItem *)selectedItem {
    if (_selectedItem != selectedItem) {
        [self.notificationsMenu.submenu.itemArray enumerateObjectsUsingBlock:^(NSMenuItem *item, NSUInteger idx, BOOL *stop) {
            item.state = NSOffState;
        }];
        _selectedItem = selectedItem;
        _selectedItem.state = NSOnState;
    }
}

#pragma mark - AsyncUdpSocketDelegate

- (void)onUdpSocket:(AsyncUdpSocket *)sock didNotSendDataWithTag:(long)tag dueToError:(NSError *)error {
    NSLog(@"================> fail for socket %@ error %@", sock, error);
}

- (BOOL)onUdpSocket:(AsyncUdpSocket *)sock didReceiveData:(NSData *)data withTag:(long)tag fromHost:(NSString *)host port:(UInt16)port {
	NSString *msg = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (msg) {
        NSLog(@"================> successful message %@", msg);
	} else {
		NSLog(@"================> fail for host:%@ port:%hu", host, port);
	}
	
	[self.udpSocket receiveWithTimeout:-1 tag:0];
	return YES;
}

@end
