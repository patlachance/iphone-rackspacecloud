//
//  ServerViewController.m
//  Rackspace
//
//  Created by Michael Mayo on 7/1/09.
//  Copyright 2009 Rackspace Hosting. All rights reserved.
//

#import "ServerViewController.h"
#import "Server.h"
#import "ResizeServerController.h"
#import "RenameServerController.h"
#import "RackspaceAppDelegate.h"
#import "Flavor.h"
#import "ConfirmResizeServerController.h"
#import "RoundedRectView.h"
#import "ServersRootViewController.h"
#import "Response.h"
#import "ResetPasswordController.h"
#import "Image.h"
#import "TextFieldCell.h"

#define kServerDetails 0
#define kPublicIPs 1
#define kPrivateIPs 2
#define kActions 3

@implementation ServerViewController

@synthesize server, footerView, statusCell, spinnerView, serversRootViewController, saveButton;

NSString *rebootMode;
TextFieldCell *serverNameCell;
NSString *initialFlavorId;

- (void)loadValidActions {
	actions = [[NSMutableDictionary alloc] init];
	[actions setObject:NSLocalizedString(@"Reset Server", @"Server Reset Server button") forKey:@"reset"];
	if (![self.server isWindows]) {
		// Windows can't be resized
		[actions setObject:NSLocalizedString(@"Resize Server", @"Server Resize Server button") forKey:@"resize"];
	}
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];	
	
	NSString *protocol = [defaults stringForKey:@"ssh_app_protocol_preference"];
	if (!protocol) {
		protocol = @"ssh://";
	}
	NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", protocol, [[server.addresses objectForKey:@"public"] objectAtIndex:0]]];
	
	UIApplication *app = [UIApplication sharedApplication];
	BOOL sshEnabled = [defaults boolForKey:@"ssh_enabled_preference"];
	
	if (sshEnabled && [app canOpenURL:url]) {
		[actions setObject:NSLocalizedString(@"Launch SSH Client", @"Server Launch SSH Client button") forKey:@"ssh"];
	}
}

// The designated initializer.  Override if you create the controller programmatically and want to perform customization that is not appropriate for viewDidLoad.
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil server:(Server *)aServer {
    if (self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil]) {
		// make and disable the save button
		self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"Save", @"Save Server button") style:UIBarButtonItemStyleBordered target:self action:@selector(saveButtonPressed:)];
		self.saveButton = self.navigationItem.rightBarButtonItem;
		self.navigationItem.rightBarButtonItem.enabled = NO;

		// set up editable cell for server name
		serverNameCell = [[TextFieldCell alloc] initWithStyle:UITableViewCellStyleValue2 reuseIdentifier:@"ServerNameCell"];
		serverNameCell.textLabel.text = NSLocalizedString(@"Name", @"Server Name cell label");
		
		serverNameCell.textField.keyboardType = UIKeyboardTypeDefault;
		serverNameCell.textField.delegate = self;
		
		self.server = aServer;

		flavorName = [self.server flavorName];
		
		[self loadValidActions];
    }
    return self;
}


- (void)viewWillAppear:(BOOL)animated {
	self.navigationItem.title = self.server.serverName;
	[super viewWillAppear:animated];
}

// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidLoad {

	serverNameCell.textField.text = [self.server serverName];
	initialFlavorId = [self.server.flavorId copy];
	
	CGRect newFrame = CGRectMake(0.0, 0.0, self.tableView.bounds.size.width, footerView.frame.size.height);
	footerView.backgroundColor = [UIColor clearColor];
	footerView.frame = newFrame;
	self.tableView.tableFooterView = self.footerView;	// note this will override UITableView's 'sectionFooterHeight' property
	
	// poll if resizing or unknown
	if ([self.server.status isEqualToString:@"BUILD"] || [self.server.status isEqualToString:@"QUEUE_RESIZE"] || [self.server.status isEqualToString:@"PREP_RESIZE"] || [self.server.status isEqualToString:@"RESIZE"] || [self.server.status isEqualToString:@"UNKNOWN"]) {
		[NSThread detachNewThreadSelector:@selector(refreshProgress:) toTarget:self withObject:self];
	}
	
	// show a rounded rect view
	self.spinnerView = [[RoundedRectView alloc] initWithDefaultFrame];
	[self.view addSubview:self.spinnerView];
	
    [super viewDidLoad];
}

- (NSString *)tableView:(UITableView *)aTableView titleForHeaderInSection:(NSInteger)section {
	if (section == kServerDetails) {
		return NSLocalizedString(@"Server Details", @"Server Details table section header");
	} else if (section == kPublicIPs) {
		return NSLocalizedString(@"Public IP Addresses", @"Public IPs table section header");
	} else if (section == kPrivateIPs) {
		return NSLocalizedString(@"Private IP Addresses", @"Private IPs table section header");
	} else if (section == kActions) {
		return NSLocalizedString(@"Actions", @"Actions table section header");
	} else {
		return @"";
	}
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 4;
}

// Customize the number of rows in the table view.
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == kServerDetails) {
		return 6;
	} else if (section == kPublicIPs) {
		return [[server.addresses objectForKey:@"public"] count];
	} else if (section == kPrivateIPs) {
		return [[server.addresses objectForKey:@"private"] count];
	} else if (section == kActions) {
		return [actions count];
	} else {
		return 0;
	}
}

- (UITableViewCell *)tableView:(UITableView *)aTableView ipCellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *CellIdentifier = @"IPCell";
	UITableViewCell *cell = (UITableViewCell *) [aTableView dequeueReusableCellWithIdentifier:CellIdentifier];
	if (cell == nil) {
		cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier] autorelease];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
	}
	if (indexPath.section == kPublicIPs) {
		cell.textLabel.text = [[server.addresses objectForKey:@"public"] objectAtIndex:indexPath.row];
	} else if (indexPath.section == kPrivateIPs) {
		cell.textLabel.text = [[server.addresses objectForKey:@"private"] objectAtIndex:indexPath.row];
	}
	return cell;
}

- (UITableViewCell *)tableView:(UITableView *)aTableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	
	if (indexPath.section == kServerDetails) {
		
		RackspaceAppDelegate *app = (RackspaceAppDelegate *) [[UIApplication sharedApplication] delegate];
		Flavor *flavor = nil;
		for (int i = 0; i < [app.flavors count]; i++) {
			Flavor *f = [app.flavors objectAtIndex:i];
			if ([self.server.flavorId isEqualToString:f.flavorId]) {
				flavor = f;
			}
		}
		Image *image = nil;
		for (int i = 0; i < [app.images count]; i++) {
			Image *img = [app.images objectAtIndex:i];
			if ([self.server.imageId isEqualToString:img.imageId]) {
				image = img;
			}
		}
		
		static NSString *CellIdentifier = @"ViewServerCell";
		UITableViewCell *cell = (UITableViewCell *) [aTableView dequeueReusableCellWithIdentifier:CellIdentifier];
		if (cell == nil) {
			cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue2 reuseIdentifier:CellIdentifier] autorelease];
			cell.selectionStyle = UITableViewCellSelectionStyleNone;
			cell.accessoryType = UITableViewCellAccessoryNone;
		}
		if (statusCell == nil) {
			statusCell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue2 reuseIdentifier:@"StatusCell"] autorelease];
			statusCell.selectionStyle = UITableViewCellSelectionStyleNone;
			statusCell.accessoryType = UITableViewCellAccessoryNone;
			statusCell.textLabel.text = NSLocalizedString(@"Status", @"Server Status cell label");
		}
		
		if (indexPath.row == 0) {
			serverNameCell.selectionStyle = UITableViewCellSelectionStyleNone;
			return serverNameCell;
		} else if (indexPath.row == 1) {
			cell.textLabel.text = NSLocalizedString(@"Flavor", @"Server Flavor cell label");
			cell.detailTextLabel.text = flavorName;
			if ([self.server isWindows]) {
				cell.accessoryType = UITableViewCellAccessoryNone; // windows can't resize
			} else {
				cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
			}
			
			cell.selectionStyle = UITableViewCellSelectionStyleBlue;
			
			// if the server is resizing, disable this
			if ([self.server.status isEqualToString:@"QUEUE_RESIZE"] || [self.server.status isEqualToString:@"PREP_RESIZE"] || [self.server.status isEqualToString:@"RESIZE"] || [self.server.status isEqualToString:@"VERIFY_RESIZE"]) {
				cell.accessoryType = UITableViewCellAccessoryNone;
				cell.selectionStyle = UITableViewCellSelectionStyleNone;
			}
			
		} else if (indexPath.row == 2) {
			cell.textLabel.text = NSLocalizedString(@"Image", @"Server Image cell label");
			cell.detailTextLabel.text = [self.server imageName];
			cell.accessoryType = UITableViewCellAccessoryNone;
		} else if (indexPath.row == 3) {
			cell.textLabel.text = NSLocalizedString(@"Memory", @"Server Memory cell label");
			cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ MB", flavor.ram];
			cell.accessoryType = UITableViewCellAccessoryNone;
		} else if (indexPath.row == 4) {
			cell.textLabel.text = NSLocalizedString(@"Disk", @"Server Disk Space cell label");
			cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ GB", flavor.disk];
			cell.accessoryType = UITableViewCellAccessoryNone;
		} else if (indexPath.row == 5) {
			statusCell.selectionStyle == UITableViewCellSelectionStyleNone;
			if ([self.server.status isEqualToString:@"ACTIVE"]) {
				statusCell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue2 reuseIdentifier:@"StatusCell2"] autorelease];
				statusCell.textLabel.text = NSLocalizedString(@"Status", @"Server Status cell label");
				statusCell.detailTextLabel.text = NSLocalizedString(@"Active", @"Server Active Status");
				statusCell.selectionStyle == UITableViewCellSelectionStyleNone;
				statusCell.userInteractionEnabled = NO;
			} else {
				
				// set up the progress view
				UIProgressView *pv = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
				CGRect r = pv.frame;
				r.origin.x += 175;
				r.origin.y += 18;
				r.size.width -= 35;
				pv.frame = r;
				
				if ([self.server.status isEqualToString:@"QUEUE_RESIZE"]) {
					// progress goes up to 33.3%
					pv.progress = ([self.server.progress intValue] / 3.0 * 0.01);
					
					statusCell.detailTextLabel.textColor = [UIColor blackColor];
					statusCell.detailTextLabel.text = NSLocalizedString(@"Resizing...", @"Server Resizing Status");
					[statusCell addSubview:pv];
				} else if ([self.server.status isEqualToString:@"PREP_RESIZE"]) {
					// progress goes up to 66.7%
					pv.progress = 0.333 + (([self.server.progress intValue] / 3.0) * 0.01);
					statusCell.detailTextLabel.text = NSLocalizedString(@"Resizing...", @"Server Resizing Status");
					[statusCell addSubview:pv];
				} else if ([self.server.status isEqualToString:@"RESIZE"]) {
					// progress goes up to 100%
					pv.progress = 0.667 + (([self.server.progress intValue] / 3.0) * 0.01);
					
					statusCell.detailTextLabel.text = NSLocalizedString(@"Resizing...", @"Server Resizing Status");
					[statusCell addSubview:pv];
				} else if ([self.server.status isEqualToString:@"VERIFY_RESIZE"]) {
					
					// hiding the progress view doesn't work, so reallocate without it
					//[statusCell release];
					statusCell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue2 reuseIdentifier:@"StatusCell3"] autorelease];
					statusCell.textLabel.text = NSLocalizedString(@"Status", @"Server Status cell label");
					statusCell.detailTextLabel.text = NSLocalizedString(@"Resize Complete", @"Server Resize Complete Status");
					statusCell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
					statusCell.selectionStyle = UITableViewCellSelectionStyleBlue;
					statusCell.userInteractionEnabled = YES;
				} else if ([self.server.status isEqualToString:@"BUILD"]) {
					pv.progress = [self.server.progress intValue] * 0.01;
					
					statusCell.detailTextLabel.text = NSLocalizedString(@"Building...", @"Server Building Status");
					[statusCell addSubview:pv];
				} else {
					// no need for the progress view
					statusCell.detailTextLabel.textColor = [UIColor redColor];
					statusCell.detailTextLabel.text = self.server.status;
					statusCell.selectionStyle = UITableViewCellSelectionStyleNone;
					statusCell.userInteractionEnabled = NO;
					statusCell.accessoryType = UITableViewCellAccessoryNone;					
					pv.hidden = YES; // don't show it!
					[pv removeFromSuperview];
				}
			
				[pv release];
			}
			
			return statusCell;
			
		} else if (indexPath.row == 6) { // TODO: implement backups!
			cell.textLabel.text = NSLocalizedString(@"Backups", @"Server Backups cell label");
			cell.detailTextLabel.text = @"Weekdays at 4:00 PM";
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		}
		
		return cell;
	} else if (indexPath.section == kPublicIPs) {
		return [self tableView:aTableView ipCellForRowAtIndexPath:indexPath];
	} else if (indexPath.section == kPrivateIPs) {
		return [self tableView:aTableView ipCellForRowAtIndexPath:indexPath];
	} else if (indexPath.section == kActions) {
		UITableViewCell *cell = (UITableViewCell *) [aTableView dequeueReusableCellWithIdentifier:@"ActionCell"];
		if (cell == nil) {
			cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"ActionCell"] autorelease];
			//cell.selectionStyle = UITableViewCellSelectionStyleNone;
			cell.selectionStyle = UITableViewCellSelectionStyleBlue;
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		}
		
		NSArray *actionKeys = [actions allKeys];
		NSString *actionKey = [actionKeys objectAtIndex:indexPath.row];
		cell.textLabel.text = [actions objectForKey:actionKey];
		cell.textLabel.textColor = [UIColor blackColor];
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		
		if ([actionKey isEqualToString:@"resize"]) {
			// if resizing, disable
			if ([self.server.status isEqualToString:@"QUEUE_RESIZE"] || [self.server.status isEqualToString:@"PREP_RESIZE"] || [self.server.status isEqualToString:@"RESIZE"] || [self.server.status isEqualToString:@"VERIFY_RESIZE"]) {
				cell.textLabel.textColor = [UIColor grayColor];
				cell.selectionStyle = UITableViewCellSelectionStyleNone;
				cell.accessoryType = UITableViewCellAccessoryNone;
			} else {
				cell.textLabel.textColor = [UIColor blackColor];
				cell.selectionStyle = UITableViewCellSelectionStyleBlue;
				if ([self.server isWindows]) {
					cell.accessoryType = UITableViewCellAccessoryNone; // windows can't resize
				} else {
					cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
				}
			}
		}
		
		return cell;
	}
	
	return nil;
}

- (void)tableView:(UITableView *)aTableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == kServerDetails) {
		if (indexPath.row == 1) { // flavor
			// if resizing, do nothing
			if (!([self.server.status isEqualToString:@"QUEUE_RESIZE"] || [self.server.status isEqualToString:@"PREP_RESIZE"] || [self.server.status isEqualToString:@"RESIZE"] || [self.server.status isEqualToString:@"VERIFY_RESIZE"])) {
				ResizeServerController *vc = [[ResizeServerController alloc] initWithNibName:@"ResizeServerController" bundle:nil];
				vc.server = self.server;
				vc.serverViewController = self;
				vc.serversRootViewController = self.serversRootViewController;
				[self.navigationController pushViewController:vc animated:YES];
				[vc release];
				[aTableView deselectRowAtIndexPath:indexPath animated:NO];
			}
		} else if (indexPath.row == 5) { // status
			if ([self.server.status isEqualToString:@"VERIFY_RESIZE"]) {
				ConfirmResizeServerController *vc = [[ConfirmResizeServerController alloc] initWithNibName:@"ConfirmResizeServerController" bundle:nil];
				vc.server = self.server;
				vc.serverViewController = self;
				[self.navigationController pushViewController:vc animated:YES];
				[vc release];
				[aTableView deselectRowAtIndexPath:indexPath animated:NO];
			}
		}
	} else if (indexPath.section == kActions) {
		
		NSArray *actionKeys = [actions allKeys];
		NSString *actionKey = [actionKeys objectAtIndex:indexPath.row];
		
		
		if ([actionKey isEqualToString:@"reset"]) {
			// reset password
			ResetPasswordController *vc = [[ResetPasswordController alloc] initWithNibName:@"ResetPasswordController" bundle:nil];
			vc.server = self.server;
			vc.serverViewController = self;
			[self.navigationController pushViewController:vc animated:YES];
			[vc release];
			[aTableView deselectRowAtIndexPath:indexPath animated:NO];
		} else if ([actionKey isEqualToString:@"resize"]) {
			// no resizing if it's windows
			if (![self.server isWindows]) {
				// resize server.  if currently resizing, do nothing
				if (!([self.server.status isEqualToString:@"QUEUE_RESIZE"] || [self.server.status isEqualToString:@"PREP_RESIZE"] || [self.server.status isEqualToString:@"RESIZE"] || [self.server.status isEqualToString:@"VERIFY_RESIZE"])) {
					ResizeServerController *vc = [[ResizeServerController alloc] initWithNibName:@"ResizeServerController" bundle:nil];
					vc.server = self.server;
					vc.serverViewController = self;
					[self.navigationController pushViewController:vc animated:YES];
					[vc release];
					[aTableView deselectRowAtIndexPath:indexPath animated:NO];
				}
			}
		} else if ([actionKey isEqualToString:@"ssh"]) {
			NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];	
			NSString *protocol = [defaults stringForKey:@"ssh_app_protocol_preference"];			
			if (!protocol) {
				protocol = @"ssh://";
			}
			NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", protocol, [[server.addresses objectForKey:@"public"] objectAtIndex:0]]];
			
			UIApplication *app = [UIApplication sharedApplication];
			
			if ([app canOpenURL:url]) {
				[app openURL:url];
			} else {
				NSLog(@"can't open the ssh client url");
			}			
		}
	}
}

#pragma mark Keyboard Delegate Methods

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
	// they're editing, so enable the save button
	self.navigationItem.rightBarButtonItem.enabled = YES;
	return YES; // let them type whatever they want
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	// send it away.  they have to hit save to commit the changes
	[textField resignFirstResponder];
	return YES;
}


#pragma mark Spinner Methods

- (void)showSpinnerViewInThread {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	self.tableView.contentOffset = CGPointMake(0, 0);
	[self.spinnerView show];
	[pool release];
}

- (void)hideSpinnerViewInThread {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	[self.spinnerView hide];
	[pool release];
}

- (void)showSpinnerView {
	self.view.userInteractionEnabled = NO;
	[NSThread detachNewThreadSelector:@selector(showSpinnerViewInThread) toTarget:self withObject:nil];
}

- (void)hideSpinnerView {
	self.view.userInteractionEnabled = YES;
	[NSThread detachNewThreadSelector:@selector(hideSpinnerViewInThread) toTarget:self withObject:nil];
}

#pragma mark Button Handlers
- (void) softRebootButtonPressed:(id)sender {
	rebootMode = @"soft";
	[self showRebootDialog];
}

- (void) hardRebootButtonPressed:(id)sender {
	rebootMode = @"hard";
	[self showRebootDialog];
}

- (void) showRebootDialog {
	NSString *title;
	
	if ([@"soft" isEqualToString:rebootMode]) {
		title = NSLocalizedString(@"Are you sure you want to perform a soft reboot?", @"Soft Reboot confirmation warning");
	} else { // hard
		title = NSLocalizedString(@"Are you sure you want to perform a hard reboot?", @"Hard Reboot confirmation warning");
	}
	
	// open a dialog with two custom buttons
	UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:title
															 delegate:self cancelButtonTitle:NSLocalizedString(@"Cancel", @"Cancel Reboot button") destructiveButtonTitle:NSLocalizedString(@"Reboot Server", @"Reboot Server button")
															 otherButtonTitles:nil];
	actionSheet.actionSheetStyle = UIActionSheetStyleDefault;
	[actionSheet showInView:self.tabBarController.view]; // if it's not over the tab bar, the bottom half of the cancel button isn't touchable
	[actionSheet release];
}

- (void)handleFailedReboot:(Response *)response {
	UIAlertView *alert;
	if (response.statusCode == 413) {
		alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Reboot Failure", @"Reboot Failure alert title")
										   message:NSLocalizedString(@"This server was not rebooted because you have exceeded the API rate limit.  Please contact the Rackspace Cloud to increase your limit or try again later.", @"Reboot failed due to rate limit alert message")
										  delegate:self cancelButtonTitle:NSLocalizedString(@"OK", @"Reboot Failure alert message OK button") otherButtonTitles: nil];
	} else {
		alert = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Reboot Failure", @"Reboot Failure alert title")
										   message:NSLocalizedString(@"This server was not rebooted.  Please check your connection or server and try again.", @"Reboot failed due to connection or other error alert message")
										  delegate:self cancelButtonTitle:NSLocalizedString(@"OK", @"Reboot Failure alert message OK button") otherButtonTitles: nil];
	}
	[alert show];
	[alert release];	
}

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
	
	if (buttonIndex == 0) { // that's the reboot button
		
		if ([rebootMode isEqualToString:@"soft"]) {
			Response *res = [self.server softReboot];
			if ([res isError]) {
				[self handleFailedReboot:res];
			}
		} else if ([rebootMode isEqualToString:@"hard"]) {
			Response *res = [self.server hardReboot];
			if ([res isError]) {
				[self handleFailedReboot:res];
			}
		}
		
		[self.tableView reloadData];		
	}
}

- (void) reloadTableData {
	[self.tableView reloadData];
}

- (void)refreshProgress:(ServerViewController *)vc {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	Server *newServer = [Server findRemoteWithId:self.server.serverId andResponse:nil];

	self.server.serverName = [newServer.serverName copy];
	self.server.status = [newServer.status copy];	
	self.server.progress = [newServer.progress copy];
		
	[self performSelectorOnMainThread:@selector(hideSpinnerView) withObject:nil waitUntilDone:NO];
	[self performSelectorOnMainThread:@selector(reloadTableData) withObject:nil waitUntilDone:YES];
	
	if (!([self.server.status isEqualToString:@"VERIFY_RESIZE"] || [self.server.status isEqualToString:@"ACTIVE"])) {
		[self refreshProgress:vc]; // keep polling until it's done
	}
	[pool release];
}

-(void) detachProgressPollingThread {
	[NSThread detachNewThreadSelector:@selector(refreshProgress:) toTarget:self withObject:self];
}

- (void)saveButtonPressed:(id)sender {

	// the button is the first responder but the keyboard takes too long to hide so force it
	[serverNameCell.textField resignFirstResponder];

	[self showSpinnerView];
	
	BOOL success = NO;
	BOOL overRateLimit = NO;
	self.server.serverName = serverNameCell.textField.text;
	
	Response *saveResponse = [self.server saveRemote];
	
	if (![saveResponse isSuccess]) {
		success = NO;
		if (saveResponse.statusCode == 413) {
			overRateLimit = YES;
		}
	} else {
		success = YES;
		self.navigationItem.title = self.server.serverName;
	}
	[self hideSpinnerView];
	
	
	if (success) {
		// all is well, so disable the save button and hide the keyboard
		self.navigationItem.rightBarButtonItem.enabled = NO;
		
		// force the servers list to refresh
		self.serversRootViewController.serversLoaded = NO;
		[self.serversRootViewController.tableView reloadData];
		
		if ([serverNameCell.textField isFirstResponder]) {
			[serverNameCell.textField resignFirstResponder];
		}
	} else {
		UIAlertView *av;
		if (overRateLimit) {
			av = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Error Saving", @"Error Saving Server alert message title")
											message:NSLocalizedString(@"Your changes were not saved because you have exceeded the API rate limit.  Please contact the Rackspace Cloud to increase your limit or try again later.", @"Server save failed due to API rate limit alert message") 
										   delegate:self cancelButtonTitle:NSLocalizedString(@"OK", @"Server Save error alert message OK button") otherButtonTitles:nil];
		} else {
			av = [[UIAlertView alloc] initWithTitle:NSLocalizedString(@"Error Saving", @"Error Saving Server alert message title")
											message:NSLocalizedString(@"Your changes were not saved.  Please check your connection or the data you entered.", @"Server save failed due to connection or other error alert message")  
										   delegate:self cancelButtonTitle:NSLocalizedString(@"OK", @"Server Save error alert message OK button") otherButtonTitles:nil];
		}
	    [av show];
		[av release];
	}
}


- (void)didReceiveMemoryWarning {
	// Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
	
	// Release any cached data, images, etc that aren't in use.
}

- (void)viewDidUnload {
	// Release any retained subviews of the main view.
	// e.g. self.myOutlet = nil;
}


- (void)dealloc {
	[server release];
	[serverNameCell release];
	[saveButton release];
//		[statusCell release];
	[spinnerView release];
	[serversRootViewController release];
	[actions release];
    [super dealloc];
}


@end
